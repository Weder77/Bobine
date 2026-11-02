import 'package:sqlite3/sqlite3.dart';

/// Schema version, bump when adding migrations in [_migrate].
const int kSchemaVersion = 1;

/// Opens the main (UI isolate) connection and applies migrations.
///
/// The UI isolate uses a short busy timeout so it never freezes while a
/// background import holds the write lock; writes from the UI are retried
/// asynchronously by the repository instead.
Database openAppDatabase(String path) {
  final db = sqlite3.open(path);
  _configure(db, busyTimeoutMs: 150);
  _migrate(db);
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
    db.execute('PRAGMA user_version = $kSchemaVersion');
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

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
  db.execute(
      'CREATE INDEX idx_categories ON categories(source_id, kind, position)');

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
