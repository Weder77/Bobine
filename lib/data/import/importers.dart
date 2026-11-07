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

Source _loadSource(Database db, int sourceId) {
  final rows = db.select('SELECT * FROM sources WHERE id = ?', [sourceId]);
  if (rows.isEmpty) throw StateError('Source $sourceId introuvable');
  return Source.fromRow(rows.first);
}

void _clearContent(Database db, int sourceId) {
  for (final t in ['channels', 'movies', 'series', 'episodes', 'categories']) {
    db.execute('DELETE FROM $t WHERE source_id = ?', [sourceId]);
  }
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
}) {
  progress('Enregistrement', 0);
  db.execute('BEGIN IMMEDIATE');
  try {
    _clearContent(db, sourceId);
    batch.write(db, sourceId, progress);
    db.execute(
      'UPDATE sources SET content_updated_at = ?, last_error = NULL, '
      'epg_url = COALESCE(epg_url, ?), account_info = COALESCE(?, account_info) WHERE id = ?',
      [_now(), Secrets.protect(discoveredEpg), account == null ? null : jsonEncode(account), sourceId],
    );
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
  final client = createHttpClient();
  try {
    final source = _loadSource(db, sourceId);
    final batch = _Batch();
    final seenIds = <String>{};
    final seriesByKey = <String, ({String extId, int position})>{};
    var count = 0;

    String uniqueId(String base) {
      var id = stableHash(base);
      var n = 1;
      while (!seenIds.add(id)) {
        id = stableHash('$base#${n++}');
      }
      return id;
    }

    final parser = M3uParser((e) {
      count++;
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
            e.attr('catchup-source'),
            channelMatchKey(e.name),
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
    await for (final line in gunzipIfNeeded(
      bytes,
    ).transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter())) {
      parser.addLine(line);
    }
    if (count == 0) {
      throw NetException("La playlist est vide ou n'est pas au format M3U.");
    }
    progress('Analyse', count);
    _commit(db, sourceId, batch, progress, discoveredEpg: parser.epgUrl);
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
  final client = createHttpClient();
  try {
    final source = _loadSource(db, sourceId);
    final api = XtreamApi.forSource(source, client: client);
    progress('Connexion', 0);
    final account = await api.authenticate();

    progress('Téléchargement', 0);
    final warnings = <String>[];
    Future<List<Map<String, Object?>>> safe(
      Future<List<Map<String, Object?>>> f,
      String what, {
      bool required = false,
    }) async {
      try {
        return await f;
      } catch (e) {
        if (required) rethrow;
        warnings.add('$what : $e');
        return const [];
      }
    }

    final results = await Future.wait([
      safe(api.liveCategories(), 'Catégories TV'),
      safe(api.liveStreams(), 'Chaînes', required: true),
      safe(api.vodCategories(), 'Catégories films'),
      safe(api.vodStreams(), 'Films'),
      safe(api.seriesCategories(), 'Catégories séries'),
      safe(api.seriesList(), 'Séries'),
    ]);
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
      final name = asString(s['name']) ?? 'Chaîne $id';
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
        channelMatchKey(name),
        batch.channels.length,
      ]);
    }
    for (final m in results[3]) {
      final id = asString(m['stream_id']);
      if (id == null || !seen.add('m$id')) continue;
      final name = asString(m['name']) ?? 'Film $id';
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
      final name = asString(s['name']) ?? 'Série $id';
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

    _commit(db, sourceId, batch, progress, account: account);
    return ContentImportResult(
      live: batch.channels.length,
      movies: batch.movies.length,
      series: batch.series.length,
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
  final client = createHttpClient();
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

    final parser = XmltvParser(
      onProgramme: (channel, rawStart, rawStop, title, desc) {
        seen++;
        if (seen % 5000 == 0) progress('Guide TV', seen);
        final start = rawStart + shift;
        final stop = rawStop + shift;
        if (stop < minStop || start > maxStart) return;
        programmes.add([channel.toLowerCase(), start, stop, title, desc, searchKey(title)]);
      },
      onChannel: (id, names) {
        final lid = id.toLowerCase();
        for (final n in [...names, id]) {
          final key = channelMatchKey(n);
          if (key.isNotEmpty) channelNames.putIfAbsent(key, () => lid);
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
    await for (final chunk in gunzipIfNeeded(bytes).transform(const Utf8Decoder(allowMalformed: true))) {
      parser.add(chunk);
    }
    parser.close();

    progress('Enregistrement', 0);
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('DELETE FROM epg_programs WHERE source_id = ?', [sourceId]);
      db.execute('DELETE FROM epg_channels WHERE source_id = ?', [sourceId]);
      final p = db.prepare(
        'INSERT OR REPLACE INTO epg_programs (source_id, channel, start, stop, title, description, search) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
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
