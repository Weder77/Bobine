import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart';

import '../core/secrets.dart';

/// Schema version, bump when adding migrations in [_migrate].
const int kSchemaVersion = 4;

/// Opens the main (UI isolate) connection and applies migrations.
///
/// The UI isolate uses a short busy timeout so it never freezes while a
/// background import holds the write lock; writes from the UI are retried
/// asynchronously by the repository instead.
Database openAppDatabase(String path) {
  final db = sqlite3.open(path);
  _configure(db, busyTimeoutMs: 150);
  _migrate(db);
  _protectLegacySecrets(db);
  return db;
}

/// Opens a connection for a background isolate (imports).
Database openWorkerDatabase(String path) {
  final db = sqlite3.open(path);
  _configure(db, busyTimeoutMs: 15000);
  return db;
}

/// In-memory database for tests.
Database openMemoryDatabase() {
  final db = sqlite3.openInMemory();
  _configure(db, busyTimeoutMs: 0);
  _migrate(db);
  return db;
}

void _configure(Database db, {required int busyTimeoutMs}) {
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA synchronous = NORMAL');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA temp_store = MEMORY');
  db.execute('PRAGMA cache_size = -32000'); // ~32 MB page cache
  db.execute('PRAGMA mmap_size = 268435456'); // 256 MB memory mapped reads
  db.execute('PRAGMA busy_timeout = $busyTimeoutMs');
}

void _migrate(Database db) {
  final version = db.select('PRAGMA user_version').first.columnAt(0) as int;
  if (version >= kSchemaVersion) return;
  db.execute('BEGIN');
  try {
    if (version < 1) _createV1(db);
    if (version < 2) {
      // EPG time shift (minutes) for guides published with a wrong timezone.
      db.execute('ALTER TABLE sources ADD COLUMN epg_offset INTEGER NOT NULL DEFAULT 0');
    }
    if (version < 3) _migrateV3(db);
    if (version < 4) {
      // Programme genres ("Sport · Rugby"); guides are imported again.
      db.execute('ALTER TABLE epg_programs ADD COLUMN category TEXT');
      db.execute('UPDATE sources SET epg_updated_at = NULL');
    }
    db.execute('PRAGMA user_version = $kSchemaVersion');
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

/// Encrypts credentials stored in clear by older versions (Windows only).
void _protectLegacySecrets(Database db) {
  if (!Secrets.supported) return;
  final rows = db.select('SELECT id, url, password, epg_url FROM sources');
  for (final r in rows) {
    String? fix(Object? v) => v == null ? null : Secrets.protect(v as String);
    final url = fix(r['url']), password = fix(r['password']), epg = fix(r['epg_url']);
    if (url != r['url'] || password != r['password'] || epg != r['epg_url']) {
      db.execute('UPDATE sources SET url = ?, password = ?, epg_url = ? WHERE id = ?', [url, password, epg, r['id']]);
    }
  }
}

/// v3: local profiles, category / channel preferences (hide, lock, order),
/// programme reminders, recordings, TMDB cache, replay and guide search.
void _migrateV3(Database db) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // Replay: how the provider builds catch-up addresses (M3U playlists).
  db.execute('ALTER TABLE channels ADD COLUMN catchup_type TEXT');
  db.execute('ALTER TABLE channels ADD COLUMN catchup_source TEXT');
  // Name key used to find a channel's guide when it has no guide id.
  db.execute('ALTER TABLE channels ADD COLUMN match_key TEXT');
  db.execute('CREATE INDEX idx_channels_epg ON channels(source_id, lower(epg_id))');
  db.execute('CREATE INDEX idx_channels_match ON channels(source_id, match_key)');
  db.execute('UPDATE sources SET content_updated_at = NULL');
  // Accent-free programme titles for the guide search. Guides are re-imported
  // at the next start (epg_updated_at cleared) so it gets filled.
  db.execute('ALTER TABLE epg_programs ADD COLUMN search TEXT');
  db.execute('UPDATE sources SET epg_updated_at = NULL');

  db.execute('''
    CREATE TABLE profiles (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      kids INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''');
  db.execute("INSERT INTO profiles (id, name, color, kids, created_at) VALUES (1, 'Moi', ${0xFFFFB547}, 0, $now)");

  // User data now belongs to a profile.
  db.execute('''
    CREATE TABLE favorites_v3 (
      profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES profiles(id) ON DELETE CASCADE,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      PRIMARY KEY (profile_id, source_id, kind, ext_id)
    ) WITHOUT ROWID''');
  db.execute('INSERT INTO favorites_v3 SELECT 1, source_id, kind, ext_id, added_at FROM favorites');
  db.execute('DROP TABLE favorites');
  db.execute('ALTER TABLE favorites_v3 RENAME TO favorites');

  db.execute('''
    CREATE TABLE progress_v3 (
      profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES profiles(id) ON DELETE CASCADE,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      position_ms INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL,
      finished INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      title TEXT NOT NULL,
      subtitle TEXT,
      image TEXT,
      series_ext TEXT,
      PRIMARY KEY (profile_id, source_id, kind, ext_id)
    ) WITHOUT ROWID''');
  db.execute(
    'INSERT INTO progress_v3 SELECT 1, source_id, kind, ext_id, position_ms, duration_ms, finished, updated_at, '
    'title, subtitle, image, series_ext FROM progress',
  );
  db.execute('DROP TABLE progress');
  db.execute('ALTER TABLE progress_v3 RENAME TO progress');
  db.execute('CREATE INDEX idx_progress_recent ON progress(profile_id, source_id, updated_at DESC)');

  db.execute('''
    CREATE TABLE recent_v3 (
      profile_id INTEGER NOT NULL DEFAULT 1 REFERENCES profiles(id) ON DELETE CASCADE,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      ext_id TEXT NOT NULL,
      watched_at INTEGER NOT NULL,
      PRIMARY KEY (profile_id, source_id, ext_id)
    ) WITHOUT ROWID''');
  db.execute('INSERT INTO recent_v3 SELECT 1, source_id, ext_id, watched_at FROM recent_channels');
  db.execute('DROP TABLE recent_channels');
  db.execute('ALTER TABLE recent_v3 RENAME TO recent_channels');

  // Category preferences, keyed by the provider's category id (row ids change
  // at every import).
  db.execute('''
    CREATE TABLE category_prefs (
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      hidden INTEGER NOT NULL DEFAULT 0,
      locked INTEGER NOT NULL DEFAULT 0,
      position INTEGER,
      PRIMARY KEY (source_id, kind, ext_id)
    ) WITHOUT ROWID''');
  db.execute('''
    CREATE TABLE channel_prefs (
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      ext_id TEXT NOT NULL,
      hidden INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (source_id, ext_id)
    ) WITHOUT ROWID''');

  db.execute('''
    CREATE TABLE reminders (
      id INTEGER PRIMARY KEY,
      profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      channel_ext TEXT NOT NULL,
      channel_name TEXT NOT NULL,
      title TEXT NOT NULL,
      start INTEGER NOT NULL,
      stop INTEGER NOT NULL,
      UNIQUE (profile_id, source_id, channel_ext, start)
    )''');

  db.execute('''
    CREATE TABLE recordings (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      channel_ext TEXT NOT NULL,
      channel_name TEXT NOT NULL,
      title TEXT NOT NULL,
      start INTEGER NOT NULL,
      stop INTEGER NOT NULL,
      path TEXT,
      status TEXT NOT NULL,
      error TEXT,
      size INTEGER,
      created_at INTEGER NOT NULL
    )''');

  db.execute('''
    CREATE TABLE tmdb_cache (
      source_id INTEGER NOT NULL,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      json TEXT,
      fetched_at INTEGER NOT NULL,
      PRIMARY KEY (source_id, kind, ext_id)
    ) WITHOUT ROWID''');
}

/// The first schema, as created by Bobine 1.0 (to test migrations).
@visibleForTesting
void createSchemaV1(Database db) => _createV1(db);

void _createV1(Database db) {
  db.execute('''
    CREATE TABLE sources (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      url TEXT NOT NULL,
      username TEXT,
      password TEXT,
      epg_url TEXT,
      user_agent TEXT,
      live_format TEXT NOT NULL DEFAULT 'ts',
      created_at INTEGER NOT NULL,
      content_updated_at INTEGER,
      epg_updated_at INTEGER,
      account_info TEXT,
      last_error TEXT
    )''');

  db.execute('''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      name TEXT NOT NULL,
      position INTEGER NOT NULL
    )''');
  db.execute('CREATE INDEX idx_categories ON categories(source_id, kind, position)');

  db.execute('''
    CREATE TABLE channels (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      ext_id TEXT NOT NULL,
      category_id INTEGER,
      name TEXT NOT NULL,
      search TEXT NOT NULL,
      logo TEXT,
      url TEXT,
      epg_id TEXT,
      number INTEGER,
      catchup_days INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL
    )''');
  db.execute('CREATE INDEX idx_channels_cat ON channels(source_id, category_id, position)');
  db.execute('CREATE INDEX idx_channels_pos ON channels(source_id, position)');
  db.execute('CREATE INDEX idx_channels_ext ON channels(source_id, ext_id)');

  db.execute('''
    CREATE TABLE movies (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      ext_id TEXT NOT NULL,
      category_id INTEGER,
      name TEXT NOT NULL,
      search TEXT NOT NULL,
      poster TEXT,
      rating REAL,
      year INTEGER,
      added INTEGER,
      container TEXT,
      url TEXT,
      position INTEGER NOT NULL
    )''');
  db.execute('CREATE INDEX idx_movies_cat ON movies(source_id, category_id, position)');
  db.execute('CREATE INDEX idx_movies_added ON movies(source_id, added DESC)');
  db.execute('CREATE INDEX idx_movies_ext ON movies(source_id, ext_id)');

  db.execute('''
    CREATE TABLE series (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      ext_id TEXT NOT NULL,
      category_id INTEGER,
      name TEXT NOT NULL,
      search TEXT NOT NULL,
      poster TEXT,
      backdrop TEXT,
      plot TEXT,
      genre TEXT,
      rating REAL,
      year INTEGER,
      added INTEGER,
      position INTEGER NOT NULL
    )''');
  db.execute('CREATE INDEX idx_series_cat ON series(source_id, category_id, position)');
  db.execute('CREATE INDEX idx_series_added ON series(source_id, added DESC)');
  db.execute('CREATE INDEX idx_series_ext ON series(source_id, ext_id)');

  db.execute('''
    CREATE TABLE episodes (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      series_ext TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      season INTEGER NOT NULL,
      episode INTEGER NOT NULL,
      title TEXT,
      plot TEXT,
      image TEXT,
      duration_s INTEGER,
      container TEXT,
      url TEXT,
      added INTEGER
    )''');
  db.execute('CREATE INDEX idx_episodes ON episodes(source_id, series_ext, season, episode)');

  // EPG, clustered on (source, channel, start) for fast range lookups.
  db.execute('''
    CREATE TABLE epg_programs (
      source_id INTEGER NOT NULL,
      channel TEXT NOT NULL,
      start INTEGER NOT NULL,
      stop INTEGER NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      PRIMARY KEY (source_id, channel, start)
    ) WITHOUT ROWID''');
  db.execute('''
    CREATE TABLE epg_channels (
      source_id INTEGER NOT NULL,
      name_key TEXT NOT NULL,
      epg_id TEXT NOT NULL,
      PRIMARY KEY (source_id, name_key)
    ) WITHOUT ROWID''');

  // User data. Keyed by stable external ids so it survives playlist refreshes
  // (and can later be synchronised with a cloud account).
  db.execute('''
    CREATE TABLE favorites (
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      added_at INTEGER NOT NULL,
      PRIMARY KEY (source_id, kind, ext_id)
    ) WITHOUT ROWID''');
  db.execute('''
    CREATE TABLE progress (
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      ext_id TEXT NOT NULL,
      position_ms INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL,
      finished INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      title TEXT NOT NULL,
      subtitle TEXT,
      image TEXT,
      series_ext TEXT,
      PRIMARY KEY (source_id, kind, ext_id)
    ) WITHOUT ROWID''');
  db.execute('CREATE INDEX idx_progress_recent ON progress(source_id, updated_at DESC)');
  db.execute('''
    CREATE TABLE recent_channels (
      source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
      ext_id TEXT NOT NULL,
      watched_at INTEGER NOT NULL,
      PRIMARY KEY (source_id, ext_id)
    ) WITHOUT ROWID''');
  db.execute('''
    CREATE TABLE kv (
      key TEXT PRIMARY KEY,
      value TEXT
    ) WITHOUT ROWID''');
}
