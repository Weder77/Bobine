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

  /// Profile whose favourites, progress and recent channels are used.
  int profileId = 1;

  /// When true, categories behind the parental code are left out everywhere.
  bool hideLocked = false;

  /// SQL condition keeping the items of [table] the user can see: not in a
  /// hidden (or, when [hideLocked], locked) category, and for channels not
  /// hidden one by one. [t] is the table name or alias used in the query.
  String _visible(String t, ContentKind kind, int sourceId) {
    final locked = hideLocked ? ' OR p.locked = 1' : '';
    var w =
        '($t.category_id IS NULL OR $t.category_id NOT IN (SELECT c.id FROM categories c JOIN category_prefs p '
        'ON p.source_id = c.source_id AND p.kind = c.kind AND p.ext_id = c.ext_id '
        "WHERE c.source_id = $sourceId AND c.kind = '${kind.db}' AND (p.hidden = 1$locked)))";
    if (kind == ContentKind.live) {
      w += ' AND $t.ext_id NOT IN (SELECT ext_id FROM channel_prefs WHERE source_id = $sourceId AND hidden = 1)';
    }
    return w;
  }

  /// SQL condition: the row of [t] sits in a category the parental control
  /// locks, and the code is required now ([hideLocked]). Unlike [_visible],
  /// hidden categories do not count: hiding tidies up, locking protects.
  String _lockedOut(String t, ContentKind kind, int sourceId) {
    if (!hideLocked) return '0';
    return '$t.category_id IN (SELECT c.id FROM categories c JOIN category_prefs p '
        'ON p.source_id = c.source_id AND p.kind = c.kind AND p.ext_id = c.ext_id '
        "WHERE c.source_id = $sourceId AND c.kind = '${kind.db}' AND p.locked = 1)";
  }

  /// Whether the parental control keeps this item away now: a channel, a
  /// film, a series or an episode (through its series) of a locked category
  /// while the code was not typed. Used wherever an item is reached by its
  /// id and not through a list ("Reprendre", multi-view, recordings, reminders).
  bool isLocked(int sourceId, ContentKind kind, String extId, {String? seriesExt}) {
    if (!hideLocked) return false;
    final (table, of, id) = switch (kind) {
      ContentKind.live => ('channels', ContentKind.live, extId),
      ContentKind.movie => ('movies', ContentKind.movie, extId),
      ContentKind.series => ('series', ContentKind.series, extId),
      ContentKind.episode => ('series', ContentKind.series, seriesExt ?? _seriesOfEpisode(sourceId, extId)),
    };
    if (id == null) return false;
    return db.select(
      'SELECT 1 FROM $table t WHERE t.source_id = ? AND t.ext_id = ? AND ${_lockedOut('t', of, sourceId)} LIMIT 1',
      [sourceId, id],
    ).isNotEmpty;
  }

  String? _seriesOfEpisode(int sourceId, String extId) {
    final rows = db.select('SELECT series_ext FROM episodes WHERE source_id = ? AND ext_id = ? LIMIT 1', [
      sourceId,
      extId,
    ]);
    return rows.isEmpty ? null : rows.first['series_ext'] as String?;
  }

  int get _nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Runs a write, retrying later if the database is busy (background import).
  void write(void Function() action, {int attempt = 0}) {
    try {
      action();
    } on SqliteException catch (e) {
      final busy = e.extendedResultCode & 0xff == 5 || e.extendedResultCode & 0xff == 6;
      if (busy && attempt < 8) {
        Timer(Duration(milliseconds: 400 * (attempt + 1)), () => write(action, attempt: attempt + 1));
      } else {
        debugPrint('DB write failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------- sources

  List<Source> sources() => db.select('SELECT * FROM sources ORDER BY created_at').map(Source.fromRow).toList();

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
        name,
        type.name,
        Secrets.protect(url),
        username,
        Secrets.protect(password),
        Secrets.protect(_nz(epgUrl)),
        _nz(userAgent),
        liveFormat,
        epgOffset,
        _nowSec,
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
        name,
        Secrets.protect(url),
        username,
        Secrets.protect(password),
        Secrets.protect(_nz(epgUrl)),
        _nz(userAgent),
        liveFormat,
        epgOffset,
        id,
      ],
    );
  }

  void deleteSource(int id) {
    db.execute('BEGIN');
    try {
      for (final t in ['epg_programs', 'epg_channels', 'tmdb_cache']) {
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

  /// Categories of [kind] in the user's order. Hidden (and, when
  /// [hideLocked], locked) ones are left out unless [includeHidden].
  List<ContentCategory> categories(
    int sourceId,
    ContentKind kind, {
    bool includeHidden = false,
    bool includeLocked = false,
  }) {
    final table = _table(kind);
    final hiddenChannels = kind == ContentKind.live
        ? ' AND t.ext_id NOT IN (SELECT ext_id FROM channel_prefs WHERE source_id = c.source_id AND hidden = 1)'
        : '';
    final filter = includeHidden
        ? ''
        : ' AND COALESCE(p.hidden, 0) = 0${hideLocked && !includeLocked ? ' AND COALESCE(p.locked, 0) = 0' : ''}';
    return db
        .select(
          'SELECT c.*, p.hidden AS p_hidden, p.locked AS p_locked, '
          '(SELECT COUNT(*) FROM $table t WHERE t.source_id = c.source_id AND t.category_id = c.id$hiddenChannels) AS cnt '
          'FROM categories c LEFT JOIN category_prefs p '
          'ON p.source_id = c.source_id AND p.kind = c.kind AND p.ext_id = c.ext_id '
          'WHERE c.source_id = ? AND c.kind = ?$filter '
          'ORDER BY (p.position IS NULL), p.position, c.position',
          [sourceId, kind.db],
        )
        .map(ContentCategory.fromRow)
        .where((c) => c.count > 0)
        .toList();
  }

  static String _table(ContentKind kind) => switch (kind) {
    ContentKind.live => 'channels',
    ContentKind.movie => 'movies',
    _ => 'series',
  };

  /// Name of a category (for breadcrumbs), or null.
  String? categoryName(int? id) {
    if (id == null) return null;
    final rows = db.select('SELECT name FROM categories WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  int count(int sourceId, ContentKind kind) {
    final table = _table(kind);
    return db
            .select('SELECT COUNT(*) FROM $table WHERE source_id = ? AND ${_visible(table, kind, sourceId)}', [
              sourceId,
            ])
            .first
            .columnAt(0)
        as int;
  }

  // --------------------------------------------------------------- channels

  List<Channel> channels(int sourceId, {int? categoryId, int? limit}) {
    final where = categoryId == null ? '' : ' AND category_id = $categoryId';
    final lim = limit == null ? '' : ' LIMIT $limit';
    return db
        .select(
          'SELECT * FROM channels WHERE source_id = ?$where '
          'AND ${_visible('channels', ContentKind.live, sourceId)} ORDER BY position$lim',
          [sourceId],
        )
        .map(Channel.fromRow)
        .toList();
  }

  List<Channel> favoriteChannels(int sourceId) => db
      .select(
        'SELECT c.* FROM favorites f JOIN channels c ON c.source_id = f.source_id AND c.ext_id = f.ext_id '
        'WHERE f.profile_id = $profileId AND f.source_id = ? AND f.kind = ? '
        'AND ${_visible('c', ContentKind.live, sourceId)} GROUP BY c.ext_id ORDER BY f.added_at',
        [sourceId, ContentKind.live.db],
      )
      .map(Channel.fromRow)
      .toList();

  List<Channel> recentChannels(int sourceId, {int limit = 40}) => db
      .select(
        'SELECT c.* FROM recent_channels r JOIN channels c ON c.source_id = r.source_id AND c.ext_id = r.ext_id '
        'WHERE r.profile_id = $profileId AND r.source_id = ? AND ${_visible('c', ContentKind.live, sourceId)} '
        'GROUP BY c.ext_id ORDER BY MAX(r.watched_at) DESC LIMIT ?',
        [sourceId, limit],
      )
      .map(Channel.fromRow)
      .toList();

  /// Streams of the same channel in other qualities ("TF1 HD", "TF1 FHD"…),
  /// visible ones only, [c] included.
  List<Channel> channelVariants(Channel c) => db
      .select(
        'SELECT * FROM channels WHERE source_id = ? AND match_key = ? '
        'AND ${_visible('channels', ContentKind.live, c.sourceId)} ORDER BY position',
        [c.sourceId, channelMatchKey(c.name)],
      )
      .map(Channel.fromRow)
      .toList();

  Channel? channelByExt(int sourceId, String extId) {
    final rows = db.select('SELECT * FROM channels WHERE source_id = ? AND ext_id = ? LIMIT 1', [sourceId, extId]);
    return rows.isEmpty ? null : Channel.fromRow(rows.first);
  }

  void touchChannel(int sourceId, String extId) => write(
    () => db.execute(
      'INSERT OR REPLACE INTO recent_channels (profile_id, source_id, ext_id, watched_at) VALUES (?, ?, ?, ?)',
      [profileId, sourceId, extId, DateTime.now().millisecondsSinceEpoch],
    ),
  );

  // ----------------------------------------------------------------- movies

  String _order(CatalogSort sort) => switch (sort) {
    CatalogSort.provider => 'position',
    CatalogSort.added => 'added DESC NULLS LAST, position',
    CatalogSort.name => 'search',
    CatalogSort.rating => 'rating DESC NULLS LAST, position',
    CatalogSort.year => 'year DESC NULLS LAST, position',
  };

  List<Movie> movies(int sourceId, {int? categoryId, CatalogSort sort = CatalogSort.provider, int? limit}) {
    final where = categoryId == null ? '' : ' AND category_id = $categoryId';
    final lim = limit == null ? '' : ' LIMIT $limit';
    return db
        .select(
          'SELECT * FROM movies WHERE source_id = ?$where AND ${_visible('movies', ContentKind.movie, sourceId)} '
          'ORDER BY ${_order(sort)}$lim',
          [sourceId],
        )
        .map(Movie.fromRow)
        .toList();
  }

  List<Movie> favoriteMovies(int sourceId) => db
      .select(
        'SELECT m.* FROM favorites f JOIN movies m ON m.source_id = f.source_id AND m.ext_id = f.ext_id '
        'WHERE f.profile_id = $profileId AND f.source_id = ? AND f.kind = ? '
        'AND ${_visible('m', ContentKind.movie, sourceId)} GROUP BY m.ext_id ORDER BY f.added_at DESC',
        [sourceId, ContentKind.movie.db],
      )
      .map(Movie.fromRow)
      .toList();

  Movie? movieByExt(int sourceId, String extId) {
    final rows = db.select('SELECT * FROM movies WHERE source_id = ? AND ext_id = ? LIMIT 1', [sourceId, extId]);
    return rows.isEmpty ? null : Movie.fromRow(rows.first);
  }

  // ----------------------------------------------------------------- series

  List<Series> series(int sourceId, {int? categoryId, CatalogSort sort = CatalogSort.provider, int? limit}) {
    final where = categoryId == null ? '' : ' AND category_id = $categoryId';
    final lim = limit == null ? '' : ' LIMIT $limit';
    return db
        .select(
          'SELECT * FROM series WHERE source_id = ?$where AND ${_visible('series', ContentKind.series, sourceId)} '
          'ORDER BY ${_order(sort)}$lim',
          [sourceId],
        )
        .map(Series.fromRow)
        .toList();
  }

  List<Series> favoriteSeries(int sourceId) => db
      .select(
        'SELECT s.* FROM favorites f JOIN series s ON s.source_id = f.source_id AND s.ext_id = f.ext_id '
        'WHERE f.profile_id = $profileId AND f.source_id = ? AND f.kind = ? '
        'AND ${_visible('s', ContentKind.series, sourceId)} GROUP BY s.ext_id ORDER BY f.added_at DESC',
        [sourceId, ContentKind.series.db],
      )
      .map(Series.fromRow)
      .toList();

  Series? seriesByExt(int sourceId, String extId) {
    final rows = db.select('SELECT * FROM series WHERE source_id = ? AND ext_id = ? LIMIT 1', [sourceId, extId]);
    return rows.isEmpty ? null : Series.fromRow(rows.first);
  }

  List<Episode> episodes(int sourceId, String seriesExt) => db
      .select('SELECT * FROM episodes WHERE source_id = ? AND series_ext = ? ORDER BY season, episode', [
        sourceId,
        seriesExt,
      ])
      .map(Episode.fromRow)
      .toList();

  void replaceEpisodes(int sourceId, String seriesExt, List<Episode> list) {
    write(() {
      db.execute('BEGIN');
      try {
        db.execute('DELETE FROM episodes WHERE source_id = ? AND series_ext = ?', [sourceId, seriesExt]);
        final stmt = db.prepare(
          'INSERT INTO episodes (source_id, series_ext, ext_id, season, episode, title, plot, image, duration_s, container, url, added) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        );
        for (final e in list) {
          stmt.execute([
            sourceId,
            seriesExt,
            e.extId,
            e.season,
            e.episode,
            e.title,
            e.plot,
            e.image,
            e.durationSec,
            e.container,
            e.url,
            null,
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
    final words = searchWords(query);
    if (words.isEmpty) return const SearchResults([], [], []);
    final clause = List.filled(words.length, "search LIKE ? ESCAPE '\\'").join(' AND ');
    final args = <Object?>[
      sourceId,
      ...words.map((w) => '%${w.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%'),
    ];
    // Prefer titles that start with the query.
    final prefix = '${words.join(' ')}%';
    List<Row> run(String table, ContentKind kind) => db.select(
      'SELECT * FROM $table WHERE source_id = ? AND $clause AND ${_visible(table, kind, sourceId)} '
      'ORDER BY (search LIKE ?) DESC, length(name) LIMIT $limit',
      [...args, prefix],
    );
    return SearchResults(
      run('channels', ContentKind.live).map(Channel.fromRow).toList(),
      run('movies', ContentKind.movie).map(Movie.fromRow).toList(),
      run('series', ContentKind.series).map(Series.fromRow).toList(),
    );
  }

  // -------------------------------------------------------------- favorites

  Set<String> favoriteKeys(int sourceId, ContentKind kind) => db
      .select('SELECT ext_id FROM favorites WHERE profile_id = $profileId AND source_id = ? AND kind = ?', [
        sourceId,
        kind.db,
      ])
      .map((r) => r['ext_id'] as String)
      .toSet();

  bool isFavorite(int sourceId, ContentKind kind, String extId) => db.select(
    'SELECT 1 FROM favorites WHERE profile_id = $profileId AND source_id = ? AND kind = ? AND ext_id = ?',
    [sourceId, kind.db, extId],
  ).isNotEmpty;

  /// Toggles and returns the new state.
  bool toggleFavorite(int sourceId, ContentKind kind, String extId) {
    final fav = isFavorite(sourceId, kind, extId);
    write(() {
      if (fav) {
        db.execute(
          'DELETE FROM favorites WHERE profile_id = $profileId AND source_id = ? AND kind = ? AND ext_id = ?',
          [sourceId, kind.db, extId],
        );
      } else {
        db.execute(
          'INSERT OR REPLACE INTO favorites (profile_id, source_id, kind, ext_id, added_at) VALUES (?, ?, ?, ?, ?)',
          [profileId, sourceId, kind.db, extId, DateTime.now().millisecondsSinceEpoch],
        );
      }
    });
    return !fav;
  }

  // --------------------------------------------------------------- progress

  ProgressEntry? progress(int sourceId, ContentKind kind, String extId) {
    final rows = db.select(
      'SELECT * FROM progress WHERE profile_id = $profileId AND source_id = ? AND kind = ? AND ext_id = ?',
      [sourceId, kind.db, extId],
    );
    return rows.isEmpty ? null : ProgressEntry.fromRow(rows.first);
  }

  Map<String, ProgressEntry> seriesProgress(int sourceId, String seriesExt) => {
    for (final r in db.select(
      'SELECT * FROM progress WHERE profile_id = $profileId AND source_id = ? AND kind = ? AND series_ext = ?',
      [sourceId, ContentKind.episode.db, seriesExt],
    ))
      r['ext_id'] as String: ProgressEntry.fromRow(r),
  };

  /// Most recently watched episode of a series (to offer "Reprendre").
  ProgressEntry? lastEpisodeProgress(int sourceId, String seriesExt) {
    final rows = db.select(
      'SELECT * FROM progress WHERE profile_id = $profileId AND source_id = ? AND kind = ? AND series_ext = ? '
      'ORDER BY updated_at DESC LIMIT 1',
      [sourceId, ContentKind.episode.db, seriesExt],
    );
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
    final finished =
        position.inMilliseconds >= duration.inMilliseconds * 0.92 ||
        (duration - position).inSeconds < 120 && duration.inMinutes > 10;
    write(
      () => db.execute(
        'INSERT OR REPLACE INTO progress (profile_id, source_id, kind, ext_id, position_ms, duration_ms, finished, '
        'updated_at, title, subtitle, image, series_ext) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          profileId,
          sourceId,
          kind.db,
          extId,
          position.inMilliseconds,
          duration.inMilliseconds,
          finished ? 1 : 0,
          DateTime.now().millisecondsSinceEpoch,
          title,
          subtitle,
          image,
          seriesExt,
        ],
      ),
    );
  }

  /// Items to show in "Continuer à regarder": unfinished movies, plus for each
  /// series the most recent episode. Films and series of a locked category
  /// stay out while the parental code is required.
  List<ProgressEntry> continueWatching(int sourceId, {int limit = 20}) {
    // A series is where its last episode watched is: an episode left at
    // the credits and followed by others seen to the end is not offered
    // again. Its newest progress decides, finished or not.
    final rows = db.select(
      'SELECT * FROM ('
      'SELECT pr.*, ROW_NUMBER() OVER (PARTITION BY '
      "CASE WHEN pr.kind = '${ContentKind.episode.db}' AND pr.series_ext IS NOT NULL "
      "THEN 's:' || pr.series_ext ELSE pr.kind || ':' || pr.ext_id END "
      'ORDER BY pr.updated_at DESC) AS newest '
      'FROM progress pr WHERE pr.profile_id = $profileId AND pr.source_id = ? '
      "AND NOT EXISTS (SELECT 1 FROM movies m WHERE pr.kind = '${ContentKind.movie.db}' "
      'AND m.source_id = pr.source_id AND m.ext_id = pr.ext_id AND ${_lockedOut('m', ContentKind.movie, sourceId)}) '
      "AND NOT EXISTS (SELECT 1 FROM series sr WHERE pr.kind = '${ContentKind.episode.db}' "
      'AND sr.source_id = pr.source_id AND sr.ext_id = pr.series_ext '
      'AND ${_lockedOut('sr', ContentKind.series, sourceId)})'
      ') WHERE newest = 1 AND finished = 0 AND position_ms > 30000 '
      'ORDER BY updated_at DESC LIMIT ?',
      [sourceId, limit],
    );
    return rows.map(ProgressEntry.fromRow).toList();
  }

  /// Marks a film or an episode as seen (it leaves "Reprendre"), or with
  /// [seen] false forgets that it was watched.
  void setWatched(
    int sourceId,
    ContentKind kind,
    String extId, {
    required bool seen,
    required String title,
    String? subtitle,
    String? image,
    String? seriesExt,
  }) {
    if (!seen) return removeProgress(sourceId, kind, extId);
    final old = progress(sourceId, kind, extId);
    final duration = old != null && old.duration.inMilliseconds > 0 ? old.duration.inMilliseconds : 1;
    write(
      () => db.execute(
        'INSERT OR REPLACE INTO progress (profile_id, source_id, kind, ext_id, position_ms, duration_ms, finished, '
        'updated_at, title, subtitle, image, series_ext) VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)',
        [
          profileId,
          sourceId,
          kind.db,
          extId,
          duration,
          duration,
          DateTime.now().millisecondsSinceEpoch,
          old?.title ?? title,
          old?.subtitle ?? subtitle,
          old?.image ?? image,
          old?.seriesExt ?? seriesExt,
        ],
      ),
    );
  }

  void removeProgress(int sourceId, ContentKind kind, String extId) => write(
    () => db.execute(
      'DELETE FROM progress WHERE profile_id = $profileId AND source_id = ? AND kind = ? AND ext_id = ?',
      [sourceId, kind.db, extId],
    ),
  );

  // -------------------------------------------------------------------- EPG

  Program? programAt(int sourceId, String channelKey, DateTime t) {
    final sec = t.millisecondsSinceEpoch ~/ 1000;
    final rows = db.select(
      'SELECT * FROM epg_programs WHERE source_id = ? AND channel = ? AND start <= ? '
      'ORDER BY start DESC LIMIT 1',
      [sourceId, channelKey, sec],
    );
    if (rows.isEmpty) return null;
    final p = Program.fromRow(rows.first);
    return p.stop.millisecondsSinceEpoch ~/ 1000 > sec ? p : null;
  }

  List<Program> programs(int sourceId, String channelKey, DateTime from, DateTime to) {
    final f = from.millisecondsSinceEpoch ~/ 1000;
    final t = to.millisecondsSinceEpoch ~/ 1000;
    // The programme already running at [from] (it may have started long
    // before, e.g. a 24 h block), then everything starting in the window.
    final running = programAt(sourceId, channelKey, from);
    final later = db
        .select(
          'SELECT * FROM epg_programs WHERE source_id = ? AND channel = ? AND start > ? AND start < ? '
          'ORDER BY start',
          [sourceId, channelKey, f, t],
        )
        .map(Program.fromRow);
    return [?running, ...later];
  }

  bool hasEpgFor(int sourceId, String channelKey) => db.select(
    'SELECT 1 FROM epg_programs WHERE source_id = ? AND channel = ? LIMIT 1',
    [sourceId, channelKey],
  ).isNotEmpty;

  String? epgIdForNameKey(int sourceId, String nameKey) {
    final rows = db.select('SELECT epg_id FROM epg_channels WHERE source_id = ? AND name_key = ?', [sourceId, nameKey]);
    return rows.isEmpty ? null : rows.first['epg_id'] as String;
  }

  int epgProgramCount(int sourceId) =>
      db.select('SELECT COUNT(*) FROM epg_programs WHERE source_id = ?', [sourceId]).first.columnAt(0) as int;

  /// Guide channels (keys of `epg_programs.channel`) that belong to a
  /// channel the user can see: by `tvg-id`, else by normalised name.
  String _visibleEpgKeys(int sourceId) =>
      'SELECT lower(ch.epg_id) FROM channels ch WHERE ch.source_id = $sourceId AND ch.epg_id IS NOT NULL '
      'AND ${_visible('ch', ContentKind.live, sourceId)} '
      'UNION SELECT e.epg_id FROM epg_channels e JOIN channels c2 '
      'ON c2.source_id = e.source_id AND c2.match_key = e.name_key '
      'WHERE e.source_id = $sourceId AND ${_visible('c2', ContentKind.live, sourceId)}';

  static String _like(String word) =>
      '%${word.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';

  /// The channel shown for the guide channel [key] (first of the list when
  /// several qualities share it), or null when the user sees none.
  Channel? _channelForEpgKey(int sourceId, String key) {
    final visible = _visible('ch', ContentKind.live, sourceId);
    // "+position": sort the few matches instead of walking the whole list.
    var rows = db.select(
      'SELECT ch.* FROM channels ch WHERE ch.source_id = ? AND lower(ch.epg_id) = ? AND $visible '
      'ORDER BY +ch.position LIMIT 1',
      [sourceId, key],
    );
    if (rows.isEmpty) {
      rows = db.select(
        'SELECT ch.* FROM channels ch WHERE ch.source_id = ? AND ch.match_key IN '
        '(SELECT e.name_key FROM epg_channels e WHERE e.source_id = ? AND e.epg_id = ?) AND $visible '
        'ORDER BY +ch.position LIMIT 1',
        [sourceId, sourceId, key],
      );
    }
    return rows.isEmpty ? null : Channel.fromRow(rows.first);
  }

  /// Searches programme titles of the guide in the next / last few days,
  /// for channels the user can see.
  ///
  /// The guide is read once (programmes first, their channel looked up
  /// afterwards): joining every matching programme to every channel made
  /// the search take minutes on big playlists.
  List<ProgramHit> searchPrograms(
    int sourceId,
    String query, {
    Duration back = const Duration(days: 7),
    Duration ahead = const Duration(days: 7),
    int limit = 40,
  }) {
    final words = searchWords(query);
    if (words.isEmpty) return const [];
    final now = DateTime.now();
    final from = now.subtract(back).millisecondsSinceEpoch ~/ 1000;
    final to = now.add(ahead).millisecondsSinceEpoch ~/ 1000;
    final clause = List.filled(words.length, "p.search LIKE ? ESCAPE '\\'").join(' AND ');
    final rows = db.select(
      'SELECT p.channel, p.start, p.stop, p.title, p.description, p.category FROM epg_programs p '
      'WHERE p.source_id = ? AND p.stop > ? AND p.start < ? AND $clause '
      'AND p.channel IN (${_visibleEpgKeys(sourceId)}) '
      'ORDER BY (p.stop < ?), p.start, p.channel LIMIT ?',
      [sourceId, from, to, ...words.map(_like), now.millisecondsSinceEpoch ~/ 1000, limit],
    );
    final channels = <String, Channel?>{};
    final out = <ProgramHit>[];
    for (final r in rows) {
      final key = r['channel'] as String;
      final channel = channels.putIfAbsent(key, () => _channelForEpgKey(sourceId, key));
      if (channel == null) continue;
      out.add(
        ProgramHit(
          channel,
          Program(
            start: DateTime.fromMillisecondsSinceEpoch((r['start'] as int) * 1000),
            stop: DateTime.fromMillisecondsSinceEpoch((r['stop'] as int) * 1000),
            title: r['title'] as String,
            description: r['description'] as String?,
            category: r['category'] as String?,
          ),
        ),
      );
    }
    return out;
  }

  /// Channels (provider ids, every quality of them) whose programme on air
  /// at [at] matches [query]: the "ligue 1" filter of Direct and multi-view.
  Set<String> channelsOnAir(int sourceId, String query, {DateTime? at}) {
    final words = searchWords(query);
    if (words.isEmpty) return const {};
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final clause = List.filled(words.length, "p.search LIKE ? ESCAPE '\\'").join(' AND ');
    final rows = db.select(
      'WITH hit(key) AS (SELECT DISTINCT p.channel FROM epg_programs p '
      'WHERE p.source_id = ? AND p.stop > ? AND p.start <= ? AND $clause) '
      'SELECT ch.ext_id FROM channels ch WHERE ch.source_id = ? AND ${_visible('ch', ContentKind.live, sourceId)} '
      'AND (lower(ch.epg_id) IN (SELECT key FROM hit) OR ch.match_key IN '
      '(SELECT e.name_key FROM epg_channels e WHERE e.source_id = ? AND e.epg_id IN (SELECT key FROM hit)))',
      [sourceId, now, now, ...words.map(_like), sourceId, sourceId],
    );
    return {for (final r in rows) r['ext_id'] as String};
  }

  // ------------------------------------------------- category / channel prefs

  void _upsertCategoryPref(int sourceId, ContentKind kind, String extId, String column, Object? value) {
    db.execute(
      'INSERT INTO category_prefs (source_id, kind, ext_id, $column) VALUES (?, ?, ?, ?) '
      'ON CONFLICT (source_id, kind, ext_id) DO UPDATE SET $column = excluded.$column',
      [sourceId, kind.db, extId, value],
    );
  }

  void setCategoryHidden(int sourceId, ContentKind kind, String extId, bool hidden) =>
      write(() => _upsertCategoryPref(sourceId, kind, extId, 'hidden', hidden ? 1 : 0));

  void setCategoryLocked(int sourceId, ContentKind kind, String extId, bool locked) =>
      write(() => _upsertCategoryPref(sourceId, kind, extId, 'locked', locked ? 1 : 0));

  /// Saves the order the user chose (provider ids, first to last).
  void setCategoryOrder(int sourceId, ContentKind kind, List<String> extIds) => write(() {
    db.execute('BEGIN');
    try {
      for (var i = 0; i < extIds.length; i++) {
        _upsertCategoryPref(sourceId, kind, extIds[i], 'position', i);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });

  /// Back to the provider's order.
  void resetCategoryOrder(int sourceId, ContentKind kind) => write(
    () => db.execute('UPDATE category_prefs SET position = NULL WHERE source_id = ? AND kind = ?', [sourceId, kind.db]),
  );

  static final _adult = RegExp(r'adult|xxx|porn|\b18\s*\+|\+\s*18\b|sexy|érotique|erotic|hot\b', caseSensitive: false);

  /// Locks the categories that look adult-only, unless the user already
  /// decided for them. Returns how many were locked.
  int autoLockAdult(int sourceId) {
    var n = 0;
    final rows = db.select(
      'SELECT c.kind, c.ext_id, c.name FROM categories c LEFT JOIN category_prefs p '
      'ON p.source_id = c.source_id AND p.kind = c.kind AND p.ext_id = c.ext_id '
      'WHERE c.source_id = ? AND p.ext_id IS NULL',
      [sourceId],
    );
    for (final r in rows) {
      if (!_adult.hasMatch(r['name'] as String)) continue;
      write(
        () =>
            _upsertCategoryPref(sourceId, ContentKind.fromDb(r['kind'] as String), r['ext_id'] as String, 'locked', 1),
      );
      n++;
    }
    return n;
  }

  void setChannelHidden(int sourceId, String extId, bool hidden) => write(
    () => db.execute(
      'INSERT INTO channel_prefs (source_id, ext_id, hidden) VALUES (?, ?, ?) '
      'ON CONFLICT (source_id, ext_id) DO UPDATE SET hidden = excluded.hidden',
      [sourceId, extId, hidden ? 1 : 0],
    ),
  );

  List<Channel> hiddenChannels(int sourceId) => db
      .select(
        'SELECT c.* FROM channel_prefs p JOIN channels c ON c.source_id = p.source_id AND c.ext_id = p.ext_id '
        'WHERE p.source_id = ? AND p.hidden = 1 GROUP BY c.ext_id ORDER BY c.position',
        [sourceId],
      )
      .map(Channel.fromRow)
      .toList();

  // --------------------------------------------------------------- profiles

  List<Profile> profiles() => db.select('SELECT * FROM profiles ORDER BY id').map(Profile.fromRow).toList();

  Profile? profile(int id) {
    final rows = db.select('SELECT * FROM profiles WHERE id = ?', [id]);
    return rows.isEmpty ? null : Profile.fromRow(rows.first);
  }

  int profileCount() => db.select('SELECT count(*) AS n FROM profiles').first['n'] as int;

  /// Whether one more profile can be created here ([Profile.max] at most).
  /// Profiles received from the account are never refused: devices that
  /// each created some can bring the total over it.
  bool get canAddProfile => profileCount() < Profile.max;

  /// Creates a profile; throws a [StateError] when there are already [Profile.max].
  int createProfile({required String name, required int color, bool kids = false, String? avatar}) {
    if (!canAddProfile) throw StateError('${Profile.max} profils au maximum');
    db.execute('INSERT INTO profiles (name, color, kids, avatar, created_at) VALUES (?, ?, ?, ?, ?)', [
      name,
      color,
      kids ? 1 : 0,
      avatar,
      _nowSec,
    ]);
    return db.lastInsertRowId;
  }

  void updateProfile(int id, {required String name, required int color, required bool kids, required String? avatar}) =>
      db.execute('UPDATE profiles SET name = ?, color = ?, kids = ?, avatar = ? WHERE id = ?', [
        name,
        color,
        kids ? 1 : 0,
        avatar,
        id,
      ]);

  /// Deletes a profile and its favourites, progress and reminders.
  void deleteProfile(int id) => db.execute('DELETE FROM profiles WHERE id = ?', [id]);

  // -------------------------------------------------------------- reminders

  List<Reminder> reminders({bool upcomingOnly = true}) => db
      .select('SELECT * FROM reminders WHERE profile_id = ?${upcomingOnly ? ' AND stop > ?' : ''} ORDER BY start', [
        profileId,
        if (upcomingOnly) _nowSec,
      ])
      .map(Reminder.fromRow)
      .toList();

  bool hasReminder(int sourceId, String channelExt, DateTime start) => db.select(
    'SELECT 1 FROM reminders WHERE profile_id = ? AND source_id = ? AND channel_ext = ? AND start = ?',
    [profileId, sourceId, channelExt, start.millisecondsSinceEpoch ~/ 1000],
  ).isNotEmpty;

  /// Adds or removes a reminder; returns whether one is now set.
  bool toggleReminder(Channel channel, Program program) {
    final start = program.start.millisecondsSinceEpoch ~/ 1000;
    if (hasReminder(channel.sourceId, channel.extId, program.start)) {
      db.execute('DELETE FROM reminders WHERE profile_id = ? AND source_id = ? AND channel_ext = ? AND start = ?', [
        profileId,
        channel.sourceId,
        channel.extId,
        start,
      ]);
      return false;
    }
    db.execute(
      'INSERT OR REPLACE INTO reminders (profile_id, source_id, channel_ext, channel_name, title, start, stop) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        profileId,
        channel.sourceId,
        channel.extId,
        channel.name,
        program.title,
        start,
        program.stop.millisecondsSinceEpoch ~/ 1000,
      ],
    );
    return true;
  }

  void deleteReminder(int id) => write(() => db.execute('DELETE FROM reminders WHERE id = ?', [id]));

  // ------------------------------------------------------------- recordings

  List<Recording> recordings() =>
      db.select('SELECT * FROM recordings ORDER BY start DESC').map(Recording.fromRow).toList();

  Recording? recording(int id) {
    final rows = db.select('SELECT * FROM recordings WHERE id = ?', [id]);
    return rows.isEmpty ? null : Recording.fromRow(rows.first);
  }

  int addRecording({
    required int sourceId,
    required String channelExt,
    required String channelName,
    required String title,
    required DateTime start,
    required DateTime stop,
    RecordingStatus status = RecordingStatus.scheduled,
    String? path,
  }) {
    db.execute(
      'INSERT INTO recordings (source_id, channel_ext, channel_name, title, start, stop, path, status, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        sourceId,
        channelExt,
        channelName,
        title,
        start.millisecondsSinceEpoch ~/ 1000,
        stop.millisecondsSinceEpoch ~/ 1000,
        path,
        status.name,
        _nowSec,
      ],
    );
    return db.lastInsertRowId;
  }

  void updateRecording(int id, {RecordingStatus? status, String? path, String? error, int? size, DateTime? stop}) {
    final sets = <String>[];
    final args = <Object?>[];
    void put(String column, Object? value) {
      sets.add('$column = ?');
      args.add(value);
    }

    if (status != null) put('status', status.name);
    if (path != null) put('path', path);
    if (error != null) put('error', error);
    if (size != null) put('size', size);
    if (stop != null) put('stop', stop.millisecondsSinceEpoch ~/ 1000);
    if (sets.isEmpty) return;
    write(() => db.execute('UPDATE recordings SET ${sets.join(', ')} WHERE id = ?', [...args, id]));
  }

  void deleteRecording(int id) => write(() => db.execute('DELETE FROM recordings WHERE id = ?', [id]));

  bool hasRecording(int sourceId, String channelExt, DateTime start) => db.select(
    "SELECT 1 FROM recordings WHERE source_id = ? AND channel_ext = ? AND start = ? AND status IN ('scheduled', 'recording')",
    [sourceId, channelExt, start.millisecondsSinceEpoch ~/ 1000],
  ).isNotEmpty;

  /// Whether [channelExt] is being recorded at [at], or about to be (a
  /// recording started by hand begins "now", not at the programme's start).
  bool isRecordingAt(int sourceId, String channelExt, DateTime at) => db.select(
    "SELECT 1 FROM recordings WHERE source_id = ? AND channel_ext = ? AND start <= ? AND stop > ? "
    "AND status IN ('scheduled', 'recording')",
    [sourceId, channelExt, at.millisecondsSinceEpoch ~/ 1000, at.millisecondsSinceEpoch ~/ 1000],
  ).isNotEmpty;

  // ------------------------------------------------------------------- TMDB

  /// Cached TMDB match: (json or null for "no match", fetched at).
  (String?, DateTime)? tmdbCached(int sourceId, ContentKind kind, String extId) {
    final rows = db.select('SELECT json, fetched_at FROM tmdb_cache WHERE source_id = ? AND kind = ? AND ext_id = ?', [
      sourceId,
      kind.db,
      extId,
    ]);
    if (rows.isEmpty) return null;
    return (
      rows.first['json'] as String?,
      DateTime.fromMillisecondsSinceEpoch((rows.first['fetched_at'] as int) * 1000),
    );
  }

  void tmdbStore(int sourceId, ContentKind kind, String extId, String? json) => write(
    () => db.execute(
      'INSERT OR REPLACE INTO tmdb_cache (source_id, kind, ext_id, json, fetched_at) VALUES (?, ?, ?, ?, ?)',
      [sourceId, kind.db, extId, json, _nowSec],
    ),
  );

  void tmdbClear() => write(() => db.execute('DELETE FROM tmdb_cache'));

  // ------------------------------------------------------------- tendances

  /// "Top 10 aujourd'hui" / "Tendances": the best rated of the latest
  /// additions, films and series together (providers give no audience
  /// figures).
  List<Object> trending(int sourceId, {int limit = 10}) {
    final items = <(Object, double, int)>[
      for (final m in movies(sourceId, sort: CatalogSort.added, limit: 160))
        (m, m.rating ?? 0, m.added?.millisecondsSinceEpoch ?? 0),
      for (final s in series(sourceId, sort: CatalogSort.added, limit: 80))
        (s, s.rating ?? 0, s.added?.millisecondsSinceEpoch ?? 0),
    ];
    items.sort((a, b) {
      final r = b.$2.compareTo(a.$2);
      return r != 0 ? r : b.$3.compareTo(a.$3);
    });
    return [for (final i in items.take(limit)) i.$1];
  }

  /// Last searches of this profile (most recent first).
  List<String> recentSearches() {
    final v = kvGet('search_recent_$profileId');
    if (v == null) return const [];
    try {
      return (jsonDecode(v) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  void addRecentSearch(String q) {
    final t = q.trim();
    if (t.length < 2) return;
    final list = [t, ...recentSearches().where((x) => x.toLowerCase() != t.toLowerCase())].take(8).toList();
    kvSet('search_recent_$profileId', jsonEncode(list));
  }

  // --------------------------------------------------------------------- kv

  String? kvGet(String key) {
    final rows = db.select('SELECT value FROM kv WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void kvSet(String key, String? value) =>
      write(() => db.execute('INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)', [key, value]));

  /// Notes a change to send to the account (the tables are noted by
  /// triggers; this is for what lives elsewhere, like the preferences).
  void noteSyncChange(String table, String key) => write(
    () => db.execute('INSERT OR REPLACE INTO sync_log (tbl, key, changed_at) VALUES (?, ?, ?)', [
      table,
      key,
      DateTime.now().millisecondsSinceEpoch,
    ]),
  );

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
