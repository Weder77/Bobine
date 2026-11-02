import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/secrets.dart';
import '../core/text.dart';
import 'models.dart';

enum CatalogSort {
  provider('Ordre du fournisseur'),
  added('Ajouts récents'),
  name('Titre (A → Z)'),
  rating('Mieux notés'),
  year('Année');

  const CatalogSort(this.label);
  final String label;
}

class SearchResults {
  const SearchResults(this.channels, this.movies, this.series);
  final List<Channel> channels;
  final List<Movie> movies;
  final List<Series> series;
  bool get isEmpty => channels.isEmpty && movies.isEmpty && series.isEmpty;
}

/// Synchronous data access for the UI isolate.
///
/// Reads are indexed and take well under a millisecond for typical queries,
/// so they run directly on the UI isolate. Writes are tiny and retried
/// asynchronously when a background import holds the write lock.
class Repository {
  Repository(this.db);
  final Database db;

  int get _nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Runs a write, retrying later if the database is busy (background import).
  void write(void Function() action, {int attempt = 0}) {
    try {
      action();
    } on SqliteException catch (e) {
      final busy = e.extendedResultCode & 0xff == 5 || e.extendedResultCode & 0xff == 6;
      if (busy && attempt < 8) {
        Timer(Duration(milliseconds: 400 * (attempt + 1)),
            () => write(action, attempt: attempt + 1));
      } else {
        debugPrint('DB write failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------- sources

  List<Source> sources() => db
      .select('SELECT * FROM sources ORDER BY created_at')
      .map(Source.fromRow)
      .toList();

  Source? source(int id) {
    final rows = db.select('SELECT * FROM sources WHERE id = ?', [id]);
    return rows.isEmpty ? null : Source.fromRow(rows.first);
  }

  int insertSource({
    required String name,
    required SourceType type,
    required String url,
    String? username,
    String? password,
    String? epgUrl,
    String? userAgent,
    String liveFormat = 'ts',
    int epgOffset = 0,
  }) {
    db.execute(
      'INSERT INTO sources (name, type, url, username, password, epg_url, user_agent, live_format, epg_offset, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        name, type.name, Secrets.protect(url), username, Secrets.protect(password),
        Secrets.protect(_nz(epgUrl)), _nz(userAgent), liveFormat, epgOffset, _nowSec,
      ],
    );
    return db.lastInsertRowId;
  }

  void updateSource(
    int id, {
    required String name,
    required String url,
    String? username,
    String? password,
    String? epgUrl,
    String? userAgent,
    String liveFormat = 'ts',
    int epgOffset = 0,
  }) {
    db.execute(
      'UPDATE sources SET name = ?, url = ?, username = ?, password = ?, epg_url = ?, '
      'user_agent = ?, live_format = ?, epg_offset = ? WHERE id = ?',
      [
        name, Secrets.protect(url), username, Secrets.protect(password),
        Secrets.protect(_nz(epgUrl)), _nz(userAgent), liveFormat, epgOffset, id,
      ],
    );
  }

  void deleteSource(int id) {
    db.execute('BEGIN');
    try {
      for (final t in ['epg_programs', 'epg_channels']) {
        db.execute('DELETE FROM $t WHERE source_id = ?', [id]);
      }
      db.execute('DELETE FROM sources WHERE id = ?', [id]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static String? _nz(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  // ------------------------------------------------------------- categories

  List<ContentCategory> categories(int sourceId, ContentKind kind) {
    final table = switch (kind) {
      ContentKind.live => 'channels',
      ContentKind.movie => 'movies',
      _ => 'series',
    };
    return db.select(
      'SELECT c.*, (SELECT COUNT(*) FROM $table t WHERE t.source_id = c.source_id AND t.category_id = c.id) AS cnt '
      'FROM categories c WHERE c.source_id = ? AND c.kind = ? ORDER BY c.position',
      [sourceId, kind.db],
    ).map(ContentCategory.fromRow).where((c) => c.count > 0).toList();
  }

  int count(int sourceId, ContentKind kind) {
    final table = switch (kind) {
      ContentKind.live => 'channels',
      ContentKind.movie => 'movies',
      _ => 'series',
    };
    return db.select('SELECT COUNT(*) FROM $table WHERE source_id = ?', [sourceId])
        .first
        .columnAt(0) as int;
  }

  // --------------------------------------------------------------- channels

  List<Channel> channels(int sourceId, {int? categoryId}) {
    if (categoryId == null) {
      return db
          .select('SELECT * FROM channels WHERE source_id = ? ORDER BY position', [sourceId])
          .map(Channel.fromRow)
          .toList();
    }
    return db
        .select('SELECT * FROM channels WHERE source_id = ? AND category_id = ? ORDER BY position',
            [sourceId, categoryId])
        .map(Channel.fromRow)
        .toList();
  }

  List<Channel> favoriteChannels(int sourceId) => db
      .select(
          'SELECT c.* FROM favorites f JOIN channels c ON c.source_id = f.source_id AND c.ext_id = f.ext_id '
          'WHERE f.source_id = ? AND f.kind = ? GROUP BY c.ext_id ORDER BY f.added_at',
          [sourceId, ContentKind.live.db])
      .map(Channel.fromRow)
      .toList();

  List<Channel> recentChannels(int sourceId, {int limit = 40}) => db
      .select(
          'SELECT c.* FROM recent_channels r JOIN channels c ON c.source_id = r.source_id AND c.ext_id = r.ext_id '
          'WHERE r.source_id = ? GROUP BY c.ext_id ORDER BY MAX(r.watched_at) DESC LIMIT ?',
          [sourceId, limit])
      .map(Channel.fromRow)
      .toList();

  Channel? channelByExt(int sourceId, String extId) {
    final rows = db.select(
        'SELECT * FROM channels WHERE source_id = ? AND ext_id = ? LIMIT 1', [sourceId, extId]);
    return rows.isEmpty ? null : Channel.fromRow(rows.first);
  }

  void touchChannel(int sourceId, String extId) => write(() => db.execute(
      'INSERT OR REPLACE INTO recent_channels (source_id, ext_id, watched_at) VALUES (?, ?, ?)',
      [sourceId, extId, DateTime.now().millisecondsSinceEpoch]));

  // ----------------------------------------------------------------- movies

  String _order(CatalogSort sort) => switch (sort) {
        CatalogSort.provider => 'position',
        CatalogSort.added => 'added DESC NULLS LAST, position',
        CatalogSort.name => 'search',
        CatalogSort.rating => 'rating DESC NULLS LAST, position',
        CatalogSort.year => 'year DESC NULLS LAST, position',
      };

  List<Movie> movies(int sourceId,
      {int? categoryId, CatalogSort sort = CatalogSort.provider, int? limit}) {
    final where = categoryId == null ? '' : ' AND category_id = $categoryId';
    final lim = limit == null ? '' : ' LIMIT $limit';
    return db
        .select('SELECT * FROM movies WHERE source_id = ?$where ORDER BY ${_order(sort)}$lim',
            [sourceId])
        .map(Movie.fromRow)
        .toList();
  }

  List<Movie> favoriteMovies(int sourceId) => db
      .select(
          'SELECT m.* FROM favorites f JOIN movies m ON m.source_id = f.source_id AND m.ext_id = f.ext_id '
          'WHERE f.source_id = ? AND f.kind = ? GROUP BY m.ext_id ORDER BY f.added_at DESC',
          [sourceId, ContentKind.movie.db])
      .map(Movie.fromRow)
      .toList();

  Movie? movieByExt(int sourceId, String extId) {
    final rows = db.select(
        'SELECT * FROM movies WHERE source_id = ? AND ext_id = ? LIMIT 1', [sourceId, extId]);
    return rows.isEmpty ? null : Movie.fromRow(rows.first);
  }

  // ----------------------------------------------------------------- series

  List<Series> series(int sourceId,
      {int? categoryId, CatalogSort sort = CatalogSort.provider, int? limit}) {
    final where = categoryId == null ? '' : ' AND category_id = $categoryId';
    final lim = limit == null ? '' : ' LIMIT $limit';
    return db
        .select('SELECT * FROM series WHERE source_id = ?$where ORDER BY ${_order(sort)}$lim',
            [sourceId])
        .map(Series.fromRow)
        .toList();
  }

  List<Series> favoriteSeries(int sourceId) => db
      .select(
          'SELECT s.* FROM favorites f JOIN series s ON s.source_id = f.source_id AND s.ext_id = f.ext_id '
          'WHERE f.source_id = ? AND f.kind = ? GROUP BY s.ext_id ORDER BY f.added_at DESC',
          [sourceId, ContentKind.series.db])
      .map(Series.fromRow)
      .toList();

  Series? seriesByExt(int sourceId, String extId) {
    final rows = db.select(
        'SELECT * FROM series WHERE source_id = ? AND ext_id = ? LIMIT 1', [sourceId, extId]);
    return rows.isEmpty ? null : Series.fromRow(rows.first);
  }

  List<Episode> episodes(int sourceId, String seriesExt) => db
      .select(
          'SELECT * FROM episodes WHERE source_id = ? AND series_ext = ? ORDER BY season, episode',
          [sourceId, seriesExt])
      .map(Episode.fromRow)
      .toList();

  void replaceEpisodes(int sourceId, String seriesExt, List<Episode> list) {
    write(() {
      db.execute('BEGIN');
      try {
        db.execute('DELETE FROM episodes WHERE source_id = ? AND series_ext = ?',
            [sourceId, seriesExt]);
        final stmt = db.prepare(
            'INSERT INTO episodes (source_id, series_ext, ext_id, season, episode, title, plot, image, duration_s, container, url, added) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
        for (final e in list) {
          stmt.execute([
            sourceId, seriesExt, e.extId, e.season, e.episode, e.title, e.plot,
            e.image, e.durationSec, e.container, e.url, null,
          ]);
        }
        stmt.close();
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    });
  }

  // ----------------------------------------------------------------- search

  SearchResults search(int sourceId, String query, {int limit = 60}) {
    final words = searchKey(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const SearchResults([], [], []);
    final clause = List.filled(words.length, "search LIKE ? ESCAPE '\\'").join(' AND ');
    final args = <Object?>[
      sourceId,
      ...words.map((w) => '%${w.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%'),
    ];
    // Prefer titles that start with the query.
    final prefix = '${words.join(' ')}%';
    List<Row> run(String table) => db.select(
        'SELECT * FROM $table WHERE source_id = ? AND $clause '
        'ORDER BY (search LIKE ?) DESC, length(name) LIMIT $limit',
        [...args, prefix]);
    return SearchResults(
      run('channels').map(Channel.fromRow).toList(),
      run('movies').map(Movie.fromRow).toList(),
      run('series').map(Series.fromRow).toList(),
    );
  }

  // -------------------------------------------------------------- favorites

  Set<String> favoriteKeys(int sourceId, ContentKind kind) => db
      .select('SELECT ext_id FROM favorites WHERE source_id = ? AND kind = ?',
          [sourceId, kind.db])
      .map((r) => r['ext_id'] as String)
      .toSet();

  bool isFavorite(int sourceId, ContentKind kind, String extId) => db.select(
          'SELECT 1 FROM favorites WHERE source_id = ? AND kind = ? AND ext_id = ?',
          [sourceId, kind.db, extId]).isNotEmpty;

  /// Toggles and returns the new state.
  bool toggleFavorite(int sourceId, ContentKind kind, String extId) {
    final fav = isFavorite(sourceId, kind, extId);
    write(() {
      if (fav) {
        db.execute('DELETE FROM favorites WHERE source_id = ? AND kind = ? AND ext_id = ?',
            [sourceId, kind.db, extId]);
      } else {
        db.execute(
            'INSERT OR REPLACE INTO favorites (source_id, kind, ext_id, added_at) VALUES (?, ?, ?, ?)',
            [sourceId, kind.db, extId, DateTime.now().millisecondsSinceEpoch]);
      }
    });
    return !fav;
  }

  // --------------------------------------------------------------- progress

  ProgressEntry? progress(int sourceId, ContentKind kind, String extId) {
    final rows = db.select(
        'SELECT * FROM progress WHERE source_id = ? AND kind = ? AND ext_id = ?',
        [sourceId, kind.db, extId]);
    return rows.isEmpty ? null : ProgressEntry.fromRow(rows.first);
  }

  Map<String, ProgressEntry> seriesProgress(int sourceId, String seriesExt) => {
        for (final r in db.select(
            'SELECT * FROM progress WHERE source_id = ? AND kind = ? AND series_ext = ?',
            [sourceId, ContentKind.episode.db, seriesExt]))
          r['ext_id'] as String: ProgressEntry.fromRow(r),
      };

  /// Most recently watched episode of a series (to offer "Reprendre").
  ProgressEntry? lastEpisodeProgress(int sourceId, String seriesExt) {
    final rows = db.select(
        'SELECT * FROM progress WHERE source_id = ? AND kind = ? AND series_ext = ? '
        'ORDER BY updated_at DESC LIMIT 1',
        [sourceId, ContentKind.episode.db, seriesExt]);
    return rows.isEmpty ? null : ProgressEntry.fromRow(rows.first);
  }

  void saveProgress({
    required int sourceId,
    required ContentKind kind,
    required String extId,
    required Duration position,
    required Duration duration,
    required String title,
    String? subtitle,
    String? image,
    String? seriesExt,
  }) {
    if (duration.inSeconds <= 0) return;
    final finished = position.inMilliseconds >= duration.inMilliseconds * 0.92 ||
        (duration - position).inSeconds < 120 && duration.inMinutes > 10;
    write(() => db.execute(
          'INSERT OR REPLACE INTO progress (source_id, kind, ext_id, position_ms, duration_ms, finished, updated_at, title, subtitle, image, series_ext) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            sourceId, kind.db, extId, position.inMilliseconds, duration.inMilliseconds,
            finished ? 1 : 0, DateTime.now().millisecondsSinceEpoch, title, subtitle,
            image, seriesExt,
          ],
        ));
  }

  /// Items to show in "Continuer à regarder": unfinished movies, plus for each
  /// series the most recent episode.
  List<ProgressEntry> continueWatching(int sourceId, {int limit = 20}) {
    final rows = db.select(
        'SELECT * FROM progress WHERE source_id = ? AND finished = 0 AND position_ms > 30000 '
        'ORDER BY updated_at DESC LIMIT 200',
        [sourceId]);
    final seenSeries = <String>{};
    final out = <ProgressEntry>[];
    for (final r in rows) {
      final p = ProgressEntry.fromRow(r);
      if (p.seriesExt != null && !seenSeries.add(p.seriesExt!)) continue;
      out.add(p);
      if (out.length >= limit) break;
    }
    return out;
  }

  void removeProgress(int sourceId, ContentKind kind, String extId) => write(() => db.execute(
      'DELETE FROM progress WHERE source_id = ? AND kind = ? AND ext_id = ?',
      [sourceId, kind.db, extId]));

  // -------------------------------------------------------------------- EPG

  Program? programAt(int sourceId, String channelKey, DateTime t) {
    final sec = t.millisecondsSinceEpoch ~/ 1000;
    final rows = db.select(
        'SELECT * FROM epg_programs WHERE source_id = ? AND channel = ? AND start <= ? '
        'ORDER BY start DESC LIMIT 1',
        [sourceId, channelKey, sec]);
    if (rows.isEmpty) return null;
    final p = Program.fromRow(rows.first);
    return p.stop.millisecondsSinceEpoch ~/ 1000 > sec ? p : null;
  }

  List<Program> programs(int sourceId, String channelKey, DateTime from, DateTime to) {
    final f = from.millisecondsSinceEpoch ~/ 1000;
    final t = to.millisecondsSinceEpoch ~/ 1000;
    // Start a few hours earlier so the program overlapping [from] is included.
    return db
        .select(
            'SELECT * FROM epg_programs WHERE source_id = ? AND channel = ? AND start >= ? AND start < ? '
            'ORDER BY start',
            [sourceId, channelKey, f - 6 * 3600, t])
        .map(Program.fromRow)
        .where((p) => p.stop.millisecondsSinceEpoch ~/ 1000 > f)
        .toList();
  }

  bool hasEpgFor(int sourceId, String channelKey) => db.select(
      'SELECT 1 FROM epg_programs WHERE source_id = ? AND channel = ? LIMIT 1',
      [sourceId, channelKey]).isNotEmpty;

  String? epgIdForNameKey(int sourceId, String nameKey) {
    final rows = db.select(
        'SELECT epg_id FROM epg_channels WHERE source_id = ? AND name_key = ?', [sourceId, nameKey]);
    return rows.isEmpty ? null : rows.first['epg_id'] as String;
  }

  int epgProgramCount(int sourceId) => db
      .select('SELECT COUNT(*) FROM epg_programs WHERE source_id = ?', [sourceId])
      .first
      .columnAt(0) as int;

  // --------------------------------------------------------------------- kv

  String? kvGet(String key) {
    final rows = db.select('SELECT value FROM kv WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void kvSet(String key, String? value) => write(() => db.execute(
      'INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)', [key, value]));

  Map<String, Object?>? kvGetJson(String key) {
    final v = kvGet(key);
    if (v == null) return null;
    try {
      return (jsonDecode(v) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }
}
