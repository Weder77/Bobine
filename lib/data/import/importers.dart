/// Import pipelines. These functions run inside background isolates
/// (see ImportService) with their own SQLite connection, so even playlists
/// with 100k entries never block the UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../../core/net.dart';
import '../../core/secrets.dart';
import '../../core/text.dart';
import '../db.dart';
import '../models.dart';
import '../stream_urls.dart';
import 'm3u_parser.dart';
import 'xmltv_parser.dart';
import 'xtream_api.dart';

/// Progress message sent from workers: [stage, count].
typedef ProgressSink = void Function(String stage, int count);

ProgressSink sinkFor(SendPort? port) {
  if (port == null) return (_, _) {};
  var last = DateTime.fromMillisecondsSinceEpoch(0);
  return (stage, count) {
    final now = DateTime.now();
    if (now.difference(last).inMilliseconds < 120 && count != 0) return;
    last = now;
    port.send([stage, count]);
  };
}

class ContentImportResult {
  ContentImportResult({this.live = 0, this.movies = 0, this.series = 0, this.warnings = const []});
  final int live;
  final int movies;
  final int series;
  final List<String> warnings;
}

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A `catchup-source` template, unless it names an address that is not a
/// network stream. A relative one (no "://") is appended to the channel's
/// own address, already checked.
String? _catchupSource(String? template) =>
    template == null || !template.contains('://') || isStreamUrl(template) ? template : null;

Source _loadSource(Database db, int sourceId) {
  final rows = db.select('SELECT * FROM sources WHERE id = ?', [sourceId]);
  if (rows.isEmpty) throw StateError('Source $sourceId introuvable');
  return Source.fromRow(rows.first);
}

/// Removes the content of a source before writing the new one. The kinds
/// in [keep] (films, series) are left as they are, with their categories:
/// their download failed, and an empty list must not replace them.
void _clearContent(Database db, int sourceId, {Set<ContentKind> keep = const {}}) {
  final tables = [
    'channels',
    if (!keep.contains(ContentKind.movie)) 'movies',
    if (!keep.contains(ContentKind.series)) ...['series', 'episodes'],
  ];
  for (final t in tables) {
    db.execute('DELETE FROM $t WHERE source_id = ?', [sourceId]);
  }
  final kinds = [
    for (final k in [ContentKind.live, ContentKind.movie, ContentKind.series])
      if (!keep.contains(k)) "'${k.db}'",
  ].join(', ');
  db.execute('DELETE FROM categories WHERE source_id = ? AND kind IN ($kinds)', [sourceId]);
}

/// Row buffers filled during download/parse, then written in one short transaction.
class _Batch {
  final categories = <String, ({ContentKind kind, String extId, String name, int position})>{};
  final channels = <List<Object?>>[];
  final movies = <List<Object?>>[];
  final series = <List<Object?>>[];
  final episodes = <List<Object?>>[];

  int _catPos = 0;

  /// Registers a category and returns its key.
  String category(ContentKind kind, String extId, String name) {
    final key = '${kind.db}|$extId';
    categories.putIfAbsent(key, () => (kind: kind, extId: extId, name: name, position: _catPos++));
    return key;
  }

  void write(Database db, int sourceId, ProgressSink progress) {
    final catIds = <String, int>{};
    final catStmt = db.prepare(
      'INSERT INTO categories (source_id, kind, ext_id, name, position) VALUES (?, ?, ?, ?, ?)',
    );
    for (final e in categories.entries) {
      catStmt.execute([sourceId, e.value.kind.db, e.value.extId, e.value.name, e.value.position]);
      catIds[e.key] = db.lastInsertRowId;
    }
    catStmt.close();

    var done = 0;
    void insertAll(String sql, List<List<Object?>> rows) {
      final stmt = db.prepare(sql);
      for (final r in rows) {
        // Column 1 holds the category key; replace it with the real id.
        final key = r[1] as String?;
        r[1] = key == null ? null : catIds[key];
        stmt.execute([sourceId, ...r]);
        if (++done % 2000 == 0) progress('Enregistrement', done);
      }
      stmt.close();
    }

    insertAll(
      'INSERT INTO channels (source_id, ext_id, category_id, name, search, logo, url, epg_id, number, catchup_days, '
      'catchup_type, catchup_source, match_key, position) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      channels,
    );
    insertAll(
      'INSERT INTO movies (source_id, ext_id, category_id, name, search, poster, rating, year, added, container, url, position) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      movies,
    );
    insertAll(
      'INSERT INTO series (source_id, ext_id, category_id, name, search, poster, backdrop, plot, genre, rating, year, added, position) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      series,
    );
    final epStmt = db.prepare(
      'INSERT INTO episodes (source_id, series_ext, ext_id, season, episode, title, plot, image, duration_s, container, url, added) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    for (final r in episodes) {
      epStmt.execute([sourceId, ...r]);
    }
    epStmt.close();
  }
}

void _commit(
  Database db,
  int sourceId,
  _Batch batch,
  ProgressSink progress, {
  String? discoveredEpg,
  Map<String, Object?>? account,
  Set<ContentKind> keep = const {},
  String? warning,
}) {
  progress('Enregistrement', 0);
  db.execute('BEGIN IMMEDIATE');
  try {
    _clearContent(db, sourceId, keep: keep);
    batch.write(db, sourceId, progress);
    db.execute(
      'UPDATE sources SET content_updated_at = ?, last_error = ?, account_info = COALESCE(?, account_info) '
      'WHERE id = ?',
      [_now(), warning, account == null ? null : jsonEncode(account), sourceId],
    );
    // The guide named by the playlist, when the source has none. A statement
    // of its own, run only then: naming epg_url in the UPDATE above noted the
    // source as changed (for the synchronisation) at every single import.
    if (discoveredEpg != null) {
      db.execute('UPDATE sources SET epg_url = ? WHERE id = ? AND epg_url IS NULL', [
        Secrets.protect(discoveredEpg),
        sourceId,
      ]);
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

// ------------------------------------------------------------------ M3U

Future<ContentImportResult> importM3u(String dbPath, int sourceId, SendPort? port) async {
  final progress = sinkFor(port);
  final db = openWorkerDatabase(dbPath);
  final client = createHttpClient(acceptInvalidCertificate: _acceptsInvalidCertificate(db, sourceId));
  try {
    final source = _loadSource(db, sourceId);
    final batch = _Batch();
    final seenIds = <String>{};
    final seriesByKey = <String, ({String extId, int position})>{};
    var count = 0, refused = 0;

    // Next suffix to try for a name already seen: counting from 1 again
    // for each copy made a list of the same entry repeated slow (the
    // square of its length). The ids are the same as before.
    final nextSuffix = <String, int>{};
    String uniqueId(String base) {
      var id = stableHash(base);
      if (seenIds.add(id)) return id;
      var n = nextSuffix[base] ?? 1;
      do {
        id = stableHash('$base#${n++}');
      } while (!seenIds.add(id));
      nextSuffix[base] = n;
      return id;
    }

    final parser = M3uParser((e) {
      // Only network streams: see [kStreamSchemes].
      if (!isStreamUrl(e.url)) {
        refused++;
        return;
      }
      count++;
      if (count > kMaxPlaylistEntries) {
        throw NetException(
          'Playlist trop grande (plus de $kMaxPlaylistEntries entrées) : import arrêté, le contenu déjà importé est gardé.',
        );
      }
      if (count % 1000 == 0) progress('Analyse', count);
      final kind = classifyEntry(e);
      final group = e.groupTitle;
      switch (kind) {
        case M3uKind.live:
          final cat = batch.category(ContentKind.live, group, group);
          batch.channels.add([
            uniqueId(e.url),
            cat,
            e.name,
            searchKey(e.name),
            e.logo,
            e.url,
            e.tvgId,
            asInt(e.attr('tvg-chno') ?? e.attr('channel-number')),
            asInt(e.attr('catchup-days') ?? e.attr('tvg-rec') ?? e.attr('timeshift')) ?? 0,
            e.attr('catchup') ?? e.attr('catchup-type'),
            _catchupSource(e.attr('catchup-source')),
            _matchKey(e.name),
            batch.channels.length,
          ]);
        case M3uKind.movie:
          final cat = batch.category(ContentKind.movie, group, group);
          batch.movies.add([
            uniqueId(e.url),
            cat,
            e.name,
            searchKey(e.name),
            e.logo,
            null,
            yearFromTitle(e.name),
            null,
            urlExtension(e.url),
            e.url,
            batch.movies.length,
          ]);
        case M3uKind.episode:
          final info = parseEpisode(e.name)!;
          final key = '${searchKey(info.seriesName)}|$group';
          var s = seriesByKey[key];
          if (s == null) {
            s = (extId: stableHash('series:$key'), position: batch.series.length);
            seriesByKey[key] = s;
            final cat = batch.category(ContentKind.series, group, group);
            batch.series.add([
              s.extId,
              cat,
              info.seriesName,
              searchKey(info.seriesName),
              e.logo,
              null,
              null,
              null,
              null,
              yearFromTitle(info.seriesName),
              null,
              s.position,
            ]);
          }
          batch.episodes.add([
            s.extId,
            uniqueId(e.url),
            info.season,
            info.episode,
            e.name,
            null,
            e.logo,
            null,
            urlExtension(e.url),
            e.url,
            null,
          ]);
      }
    });

    progress('Téléchargement', 0);
    final Stream<List<int>> bytes;
    final location = source.url.trim();
    final isFile = !location.startsWith(RegExp(r'https?://', caseSensitive: false));
    if (isFile) {
      final path = location.startsWith('file://') ? Uri.parse(location).toFilePath() : location;
      final file = File(path);
      if (!file.existsSync()) throw NetException('Fichier introuvable : $path');
      bytes = file.openRead();
    } else {
      bytes = await openGet(
        client,
        Uri.parse(location),
        userAgent: source.userAgent,
        timeout: const Duration(seconds: 60),
      );
    }
    final text = guardBody(gunzipIfNeeded(bytes), maxBytes: 1 << 30).transform(const Utf8Decoder(allowMalformed: true));
    await for (final line in limitLineLength(text).transform(const LineSplitter())) {
      parser.addLine(line);
      if (parser.notAPlaylist) {
        throw NetException(
          "Le serveur a renvoyé une page web ou un message d'erreur au lieu de la playlist. "
          'Les chaînes déjà importées sont gardées.',
        );
      }
    }
    if (count == 0) {
      throw NetException(
        refused > 0
            ? "Aucune adresse de flux réseau dans la playlist : $refused entrée(s) désignent un fichier ou un "
                  'protocole non pris en charge.'
            : "La playlist est vide ou n'est pas au format M3U.",
      );
    }
    progress('Analyse', count);
    _commit(
      db,
      sourceId,
      batch,
      progress,
      discoveredEpg: parser.epgUrl,
      warning: refused == 0
          ? null
          : '$refused entrée(s) ignorée(s) : elles désignent un fichier ou un protocole non pris en charge.',
    );
    return ContentImportResult(live: batch.channels.length, movies: batch.movies.length, series: batch.series.length);
  } finally {
    client.close(force: true);
    db.close();
  }
}

// --------------------------------------------------------------- Xtream

Future<ContentImportResult> importXtream(String dbPath, int sourceId, SendPort? port) async {
  final progress = sinkFor(port);
  final db = openWorkerDatabase(dbPath);
  final client = createHttpClient(acceptInvalidCertificate: _acceptsInvalidCertificate(db, sourceId));
  try {
    final source = _loadSource(db, sourceId);
    final api = XtreamApi.forSource(source, client: client);
    progress('Connexion', 0);
    final account = await api.authenticate();

    progress('Téléchargement', 0);
    final warnings = <String>[];
    // Films or series whose list (or categories) could not be downloaded:
    // what the source already has is kept instead of being emptied.
    final failed = <ContentKind>{};
    // The names of the TV categories could not be downloaded.
    var liveNamesMissing = false;
    Future<List<Map<String, Object?>>> safe(
      Future<List<Map<String, Object?>>> f,
      String what, {
      bool required = false,
      ContentKind? keeps,
    }) async {
      try {
        return await f;
      } catch (e) {
        // Channels are the heart of a source: without them the import fails
        // and nothing is touched.
        if (required) rethrow;
        if (keeps != null) {
          failed.add(keeps);
        } else {
          liveNamesMissing = true;
        }
        warnings.add('$what : ${redactCredentials('$e')}');
        return const [];
      }
    }

    final results = await Future.wait([
      safe(api.liveCategories(), 'Catégories TV'),
      safe(api.liveStreams(), 'Chaînes', required: true),
      safe(api.vodCategories(), 'Catégories films', keeps: ContentKind.movie),
      safe(api.vodStreams(), 'Films', keeps: ContentKind.movie),
      safe(api.seriesCategories(), 'Catégories séries', keeps: ContentKind.series),
      safe(api.seriesList(), 'Séries', keeps: ContentKind.series),
    ]);
    // An empty list in a 200 answer ("[]", null, {"error": …}) is a panel
    // having a bad moment far more often than a catalogue really emptied:
    // what the source has is kept, as when the download fails.
    int had(String table) => db.select('SELECT 1 FROM $table WHERE source_id = ? LIMIT 1', [sourceId]).length;
    final noChannels = results[1].isEmpty;
    if (noChannels && (had('channels') > 0 || (results[3].isEmpty && results[5].isEmpty))) {
      throw NetException(
        "Le serveur n'a renvoyé aucune chaîne (liste vide) : le contenu déjà importé est gardé. Réessaie plus tard.",
      );
    }
    if (results[3].isEmpty && !failed.contains(ContentKind.movie) && had('movies') > 0) {
      failed.add(ContentKind.movie);
      warnings.add('Films : liste vide');
    }
    if (results[5].isEmpty && !failed.contains(ContentKind.series) && had('series') > 0) {
      failed.add(ContentKind.series);
      warnings.add('Séries : liste vide');
    }
    // Half a kind is not written: its old content stays whole.
    if (failed.contains(ContentKind.movie)) results[2] = results[3] = const [];
    if (failed.contains(ContentKind.series)) results[4] = results[5] = const [];
    // The channels came without the names of their categories: they are
    // imported all the same, under the names (and in the order) the source
    // already had. A category never seen before is called "Autres".
    if (liveNamesMissing) {
      results[0] = [
        for (final r in db.select(
          'SELECT ext_id, name FROM categories WHERE source_id = ? AND kind = ? ORDER BY position',
          [sourceId, ContentKind.live.db],
        ))
          {'category_id': r['ext_id'], 'category_name': r['name']},
      ];
    }
    final total = results[1].length + results[3].length + results[5].length;
    progress('Analyse', total);

    final batch = _Batch();
    final catNames = <String, String>{};
    void registerCats(ContentKind kind, List<Map<String, Object?>> cats) {
      for (final c in cats) {
        final id = asString(c['category_id']);
        if (id == null) continue;
        final name = asString(c['category_name']) ?? 'Sans nom';
        catNames['${kind.db}|$id'] = name;
        batch.category(kind, id, name);
      }
    }

    String? catKey(ContentKind kind, Object? id) {
      final s = asString(id);
      if (s == null) return null;
      final key = '${kind.db}|$s';
      if (!catNames.containsKey(key)) {
        // Stream references an unknown category: create it on the fly.
        catNames[key] = 'Autres';
        batch.category(kind, s, 'Autres');
      }
      return key;
    }

    registerCats(ContentKind.live, results[0]);
    registerCats(ContentKind.movie, results[2]);
    registerCats(ContentKind.series, results[4]);

    final seen = <String>{};
    for (final s in results[1]) {
      final id = asString(s['stream_id']);
      if (id == null || !seen.add('l$id')) continue;
      final name = _name(asString(s['name'])) ?? 'Chaîne $id';
      final archive = asInt(s['tv_archive']) == 1 ? (asInt(s['tv_archive_duration']) ?? 0) : 0;
      batch.channels.add([
        id,
        catKey(ContentKind.live, s['category_id']),
        name,
        searchKey(name),
        asString(s['stream_icon']),
        null,
        asString(s['epg_channel_id']),
        asInt(s['num']),
        archive,
        archive > 0 ? 'xc' : null,
        null,
        _matchKey(name),
        batch.channels.length,
      ]);
    }
    for (final m in results[3]) {
      final id = asString(m['stream_id']);
      if (id == null || !seen.add('m$id')) continue;
      final name = _name(asString(m['name'])) ?? 'Film $id';
      batch.movies.add([
        id,
        catKey(ContentKind.movie, m['category_id']),
        name,
        searchKey(name),
        asString(m['stream_icon']),
        parseRating(m),
        asInt(m['year']) ?? yearFromTitle(name),
        asInt(m['added']),
        asString(m['container_extension']),
        null,
        batch.movies.length,
      ]);
    }
    for (final s in results[5]) {
      final id = asString(s['series_id']);
      if (id == null || !seen.add('s$id')) continue;
      final name = _name(asString(s['name'])) ?? 'Série $id';
      final release = asString(s['releaseDate']) ?? asString(s['release_date']);
      final year = (release != null && release.length >= 4) ? int.tryParse(release.substring(0, 4)) : null;
      final backdrop = s['backdrop_path'] is List && (s['backdrop_path'] as List).isNotEmpty
          ? asString((s['backdrop_path'] as List).first)
          : asString(s['backdrop_path']);
      batch.series.add([
        id,
        catKey(ContentKind.series, s['category_id']),
        name,
        searchKey(name),
        asString(s['cover']),
        backdrop,
        asString(s['plot']),
        asString(s['genre']),
        parseRating(s),
        year ?? yearFromTitle(name),
        asInt(s['last_modified']),
        batch.series.length,
      ]);
    }

    final warning = warnings.isEmpty
        ? null
        : 'Mise à jour incomplète, l’ancien contenu est gardé pour ce qui a échoué (${warnings.join(' ; ')}).';
    _commit(db, sourceId, batch, progress, account: account, keep: failed, warning: warning);
    int kept(String table) =>
        db.select('SELECT count(*) AS n FROM $table WHERE source_id = ?', [sourceId]).first['n'] as int;
    return ContentImportResult(
      live: batch.channels.length,
      movies: failed.contains(ContentKind.movie) ? kept('movies') : batch.movies.length,
      series: failed.contains(ContentKind.series) ? kept('series') : batch.series.length,
      warnings: warnings,
    );
  } finally {
    client.close(force: true);
    db.close();
  }
}

// ------------------------------------------------------------------ EPG

/// Downloads and stores the XMLTV guide. Returns the number of programmes kept.
Future<int> importEpg(String dbPath, int sourceId, int days, SendPort? port) async {
  final progress = sinkFor(port);
  final db = openWorkerDatabase(dbPath);
  final client = createHttpClient(acceptInvalidCertificate: _acceptsInvalidCertificate(db, sourceId));
  try {
    final source = _loadSource(db, sourceId);
    final url = source.effectiveEpgUrl;
    if (url == null) return 0;

    final now = _now();
    final shift = source.epgOffsetMinutes * 60;
    // Past week kept for replay (catch-up) from the guide.
    final minStop = now - 7 * 86400;
    final maxStart = now + days * 86400;

    final programmes = <List<Object?>>[];
    final channelNames = <String, String>{};
    var seen = 0;

    // Only the programmes of the source's channels are kept (by tvg-id, or
    // by a name of the guide channel): a guide of every channel of a
    // country held in memory before being written could exhaust it. A
    // source without channels yet keeps everything, up to a bound.
    final epgIds = {
      for (final r in db.select(
        'SELECT DISTINCT lower(epg_id) AS e FROM channels WHERE source_id = ? AND epg_id IS NOT NULL',
        [sourceId],
      ))
        r['e'] as String,
    };
    final matchKeys = {
      for (final r in db.select('SELECT DISTINCT name FROM channels WHERE source_id = ?', [sourceId]))
        channelMatchKey(r['name'] as String),
    }..remove('');
    final keepAll = epgIds.isEmpty && matchKeys.isEmpty;
    final known = <String>{...epgIds};

    final parser = XmltvParser(
      onProgramme: (channel, rawStart, rawStop, title, desc, category) {
        seen++;
        if (seen % 5000 == 0) progress('Guide TV', seen);
        final start = rawStart + shift;
        final stop = rawStop + shift;
        if (stop < minStop || start > maxStart) return;
        if (!keepAll && !known.contains(channel.toLowerCase())) return;
        if (programmes.length >= kMaxGuideProgrammes) return;
        programmes.add([channel.toLowerCase(), start, stop, title, desc, searchKey(title), category]);
      },
      onChannel: (id, names) {
        final lid = id.toLowerCase();
        for (final n in [...names, id]) {
          final key = channelMatchKey(n);
          if (key.isEmpty || channelNames.length >= kMaxGuideProgrammes) continue;
          if (keepAll || matchKeys.contains(key)) {
            channelNames.putIfAbsent(key, () => lid);
            known.add(lid);
          }
        }
      },
    );

    progress('Guide TV', 0);
    final Stream<List<int>> bytes;
    if (url.startsWith(RegExp(r'https?://', caseSensitive: false))) {
      bytes = await openGet(client, Uri.parse(url), userAgent: source.userAgent, timeout: const Duration(seconds: 90));
    } else {
      final file = File(url.startsWith('file://') ? Uri.parse(url).toFilePath() : url);
      if (!file.existsSync()) throw NetException('Fichier EPG introuvable : ${file.path}');
      bytes = file.openRead();
    }
    // A guide is read as it arrives, so its size costs time, not memory:
    // the bound only stops an endless answer.
    final guarded = guardBody(gunzipIfNeeded(bytes), maxBytes: 4 << 30);
    await for (final chunk in guarded.transform(const Utf8Decoder(allowMalformed: true))) {
      parser.add(chunk);
    }
    parser.close();
    // Nothing read (an empty answer, a web page, an archive this does not
    // open): the guide the source has is kept, and asked again next time.
    if (seen == 0) throw NetException('Le guide reçu est vide ou illisible : le guide déjà importé est gardé.');

    progress('Enregistrement', 0);
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('DELETE FROM epg_programs WHERE source_id = ?', [sourceId]);
      db.execute('DELETE FROM epg_channels WHERE source_id = ?', [sourceId]);
      final p = db.prepare(
        'INSERT OR REPLACE INTO epg_programs (source_id, channel, start, stop, title, description, search, category) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      );
      var i = 0;
      for (final row in programmes) {
        p.execute([sourceId, ...row]);
        if (++i % 5000 == 0) progress('Enregistrement', i);
      }
      p.close();
      final c = db.prepare('INSERT OR IGNORE INTO epg_channels (source_id, name_key, epg_id) VALUES (?, ?, ?)');
      channelNames.forEach((key, id) => c.execute([sourceId, key, id]));
      c.close();
      db.execute('UPDATE sources SET epg_updated_at = ? WHERE id = ?', [now, sourceId]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return programmes.length;
  } finally {
    client.close(force: true);
    db.close();
  }
}

/// Records an error message on the source (shown in settings).
void recordSourceError(String dbPath, int sourceId, String? message) {
  final db = openWorkerDatabase(dbPath);
  try {
    db.execute('UPDATE sources SET last_error = ? WHERE id = ?', [message, sourceId]);
  } finally {
    db.close();
  }
}

/// The name key stored with a channel, null when it has none: channels
/// without one must not all look like the same channel.
String? _matchKey(String name) {
  final k = channelMatchKey(name);
  return k.isEmpty ? null : k;
}

/// A name from the provider, cut to the length of the M3U ones: every name
/// goes through several expressions, and real ones are far shorter.
String? _name(String? v) => v == null || v.length <= kMaxEntryName ? v : v.substring(0, kMaxEntryName).trim();

/// Entries read from one playlist at most: all are held in memory before
/// being written. The largest real ones are a few hundred thousand.
const int kMaxPlaylistEntries = 1500000;

/// Programmes kept from one guide at most (held in memory the same way).
const int kMaxGuideProgrammes = 3000000;

/// The source accepts an invalid certificate from its server (its setting).
bool _acceptsInvalidCertificate(Database db, int sourceId) =>
    db.select('SELECT bad_cert_ok FROM sources WHERE id = ?', [sourceId]).firstOrNull?['bad_cert_ok'] == 1;
