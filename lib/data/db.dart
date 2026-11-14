import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart';

import '../core/secrets.dart';
import '../core/text.dart';

/// Schema version, bump when adding migrations in [_migrate].
const int kSchemaVersion = 11;

/// Opens the main (UI isolate) connection and applies migrations.
///
/// The UI isolate uses a short busy timeout so it never freezes while a
/// background import holds the write lock; writes from the UI are retried
/// asynchronously by the repository instead.
Database openAppDatabase(String path) {
  final db = sqlite3.open(path);
  _ownerOnly(path);
  _configure(db, busyTimeoutMs: 150);
  _migrate(db);
  _protectLegacySecrets(db);
  return db;
}

/// Outside Windows the secrets are not encrypted in the file (see
/// [Secrets]): it is made readable by this user account only. SQLite gives
/// its -wal and -shm files the same rights. On Android the app's folder is
/// already private to the app.
void _ownerOnly(String path) {
  if (Platform.isWindows || Platform.isAndroid || !File(path).existsSync()) return;
  try {
    Process.runSync('chmod', ['600', path]);
  } catch (_) {}
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

/// The database was made by a newer Bobine: this one does not know its
/// tables, and writing to it could break it for the newer one.
class NewerDatabaseException implements Exception {
  @override
  String toString() =>
      "Les données ont été créées par une version plus récente de Bobine : installe la dernière version.";
}

void _migrate(Database db) {
  final version = db.select('PRAGMA user_version').first.columnAt(0) as int;
  if (version > kSchemaVersion) {
    db.close();
    throw NewerDatabaseException();
  }
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
    if (version < 5) _migrateV5(db);
    if (version < 6) _migrateV6(db);
    if (version < 7) _migrateV7(db);
    if (version < 8) _migrateV8(db);
    if (version < 9) _migrateV9(db);
    if (version < 10) _migrateV10(db);
    if (version < 11) _migrateV11(db);
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

/// Uid of the profile every installation starts with ("Moi"), the same on
/// every device so that it is one profile once the devices are synchronised.
const String kDefaultProfileUid = 'default';

/// Tables whose rows are synchronised with the account, and how a row is
/// identified in `sync_log` (local ids: they are turned into uids when sent).
const Map<String, List<String>> kSyncKeys = {
  'favorites': ['profile_id', 'source_id', 'kind', 'ext_id'],
  'progress': ['profile_id', 'source_id', 'kind', 'ext_id'],
  'recent_channels': ['profile_id', 'source_id', 'ext_id'],
  'category_prefs': ['source_id', 'kind', 'ext_id'],
  'channel_prefs': ['source_id', 'ext_id'],
  'reminders': ['profile_id', 'source_id', 'channel_ext', 'start'],
};

/// Current time in ms, in SQL.
const String _sqlNowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Condition of the sync triggers: not while changes from the account are applied.
const String _syncLive = 'NOT EXISTS (SELECT 1 FROM sync_mute)';

/// Notes [key] of [table] as changed now, from a trigger.
///
/// An upsert, not INSERT OR REPLACE: inside a trigger, SQLite applies the
/// conflict policy of the statement that fired it (ABORT for an upsert,
/// IGNORE for INSERT OR IGNORE) to "OR" clauses, not to upserts.
String _syncLogSql(String table, String key) =>
    "INSERT INTO sync_log (tbl, key, changed_at) VALUES ('$table', $key, $_sqlNowMs) "
    'ON CONFLICT (tbl, key) DO UPDATE SET changed_at = excluded.changed_at;';

/// v5: synchronisation between devices.
///
/// Sources and profiles get a `uid` shared by all devices. Every change to
/// the user's data is noted in `sync_log` by triggers, so nothing else has to
/// think about it; changes coming from the account are applied while a row
/// sits in `sync_mute`, so they are not sent back.
void _migrateV5(Database db) {
  db.execute('ALTER TABLE sources ADD COLUMN uid TEXT');
  db.execute('ALTER TABLE profiles ADD COLUMN uid TEXT');
  db.execute('UPDATE sources SET uid = lower(hex(randomblob(16)))');
  db.execute(
    "UPDATE profiles SET uid = CASE WHEN id = 1 THEN '$kDefaultProfileUid' ELSE lower(hex(randomblob(16))) END",
  );
  db.execute('CREATE UNIQUE INDEX idx_sources_uid ON sources(uid)');
  db.execute('CREATE UNIQUE INDEX idx_profiles_uid ON profiles(uid)');

  db.execute('''
    CREATE TABLE sync_log (
      tbl TEXT NOT NULL,
      key TEXT NOT NULL,
      changed_at INTEGER NOT NULL,
      PRIMARY KEY (tbl, key)
    ) WITHOUT ROWID''');
  db.execute('CREATE TABLE sync_mute (muted INTEGER)');

  const live = _syncLive;
  const log = _syncLogSql;

  // Sources and profiles: a uid is given to new rows, and logged under it.
  const syncedColumns = {
    'sources': 'name, type, url, username, password, epg_url, user_agent, live_format, epg_offset, uid',
    // bad_cert_ok (v10) is added to the sources trigger by its migration.
    'profiles': 'name, color, kids, uid',
  };
  // Where the source / profile id sits in the log keys of the other tables.
  final parentIndex = {
    'sources': {for (final e in kSyncKeys.entries) e.key: e.value.indexOf('source_id')},
    'profiles': {
      for (final e in kSyncKeys.entries)
        if (e.value.contains('profile_id')) e.key: e.value.indexOf('profile_id'),
    },
  };
  for (final t in ['sources', 'profiles']) {
    db.execute(
      'CREATE TRIGGER ${t}_uid AFTER INSERT ON $t WHEN NEW.uid IS NULL BEGIN '
      'UPDATE $t SET uid = lower(hex(randomblob(16))) WHERE id = NEW.id; END',
    );
    // A new row may reuse the id of a deleted one: forget what was noted for
    // the rows that belonged to it.
    final purge = [
      for (final e in parentIndex[t]!.entries)
        "DELETE FROM sync_log WHERE tbl = '${e.key}' AND json_extract(key, '\$[${e.value}]') = NEW.id;",
    ].join(' ');
    db.execute('CREATE TRIGGER ${t}_reused AFTER INSERT ON $t BEGIN $purge END');
    db.execute(
      'CREATE TRIGGER sync_${t}_ins AFTER INSERT ON $t WHEN NEW.uid IS NOT NULL AND $live '
      'BEGIN ${log(t, 'NEW.uid')} END',
    );
    db.execute(
      'CREATE TRIGGER sync_${t}_upd AFTER UPDATE OF ${syncedColumns[t]} ON $t WHEN NEW.uid IS NOT NULL AND $live '
      'BEGIN ${log(t, 'NEW.uid')} END',
    );
    db.execute('CREATE TRIGGER sync_${t}_del AFTER DELETE ON $t WHEN $live BEGIN ${log(t, 'OLD.uid')} END');
  }

  for (final e in kSyncKeys.entries) {
    final t = e.key;
    String key(String row) => 'json_array(${e.value.map((c) => '$row.$c').join(', ')})';
    db.execute('CREATE TRIGGER sync_${t}_ins AFTER INSERT ON $t WHEN $live BEGIN ${log(t, key('NEW'))} END');
    db.execute(
      'CREATE TRIGGER sync_${t}_upd AFTER UPDATE ON $t WHEN $live BEGIN ${log(t, key('OLD'))} ${log(t, key('NEW'))} END',
    );
    db.execute('CREATE TRIGGER sync_${t}_del AFTER DELETE ON $t WHEN $live BEGIN ${log(t, key('OLD'))} END');
  }
}

/// v6: profile pictures. `avatar` is null (the initial on the profile's
/// colour), `preset:<name>` (a picture of assets/avatars) or a small photo
/// as a `data:image/jpeg;base64,` address. It follows the account like the
/// name and the colour.
void _migrateV6(Database db) {
  db.execute('ALTER TABLE profiles ADD COLUMN avatar TEXT');
  db.execute('DROP TRIGGER sync_profiles_upd');
  db.execute(
    'CREATE TRIGGER sync_profiles_upd AFTER UPDATE OF name, color, kids, avatar, uid ON profiles '
    'WHEN NEW.uid IS NOT NULL AND $_syncLive BEGIN ${_syncLogSql('profiles', 'NEW.uid')} END',
  );
}

/// v7: the newest version of each item received from or sent to the
/// account, by item id. An account (or a server) that hands back an older
/// version of an item than one already seen here is not followed: it could
/// otherwise bring back, say, a parental code removed since.
void _migrateV7(Database db) {
  db.execute('CREATE TABLE sync_seen (id TEXT PRIMARY KEY, modified_at INTEGER NOT NULL) WITHOUT ROWID');
}

/// v8: channel name keys keep other alphabets and are null when nothing is
/// left to tell a channel by (see [channelMatchKey]). Guides are imported
/// again at the next start, to be stored with the same keys.
void _migrateV8(Database db) {
  final rows = db.select('SELECT id, name FROM channels');
  final update = db.prepare('UPDATE channels SET match_key = ? WHERE id = ?');
  for (final r in rows) {
    final key = channelMatchKey(r['name'] as String);
    update.execute([key.isEmpty ? null : key, r['id']]);
  }
  update.close();
  db.execute('UPDATE sources SET epg_updated_at = NULL');
}

/// v9: recordings are no longer deleted with their source: the files stay
/// on the disk, and the list is the only way to find and play them.
void _migrateV9(Database db) {
  db.execute('''
    CREATE TABLE recordings_v9 (
      id INTEGER PRIMARY KEY,
      source_id INTEGER NOT NULL,
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
  db.execute(
    'INSERT INTO recordings_v9 SELECT id, source_id, channel_ext, channel_name, title, start, stop, path, status, '
    'error, size, created_at FROM recordings',
  );
  db.execute('DROP TABLE recordings');
  db.execute('ALTER TABLE recordings_v9 RENAME TO recordings');
}

/// v10: certificates of https providers are checked; a source can accept
/// an invalid one (`bad_cert_ok`). It follows the account like the rest of
/// the source.
void _migrateV10(Database db) {
  db.execute('ALTER TABLE sources ADD COLUMN bad_cert_ok INTEGER NOT NULL DEFAULT 0');
  // Sources already in https keep working as before (any certificate was
  // accepted until now): the option is on for them, and can be turned off
  // in the source. Done before the trigger below includes the column, so
  // each device decides for its own sources.
  for (final r in db.select('SELECT id, url, epg_url FROM sources')) {
    bool https(Object? v) => (Secrets.reveal(v as String?) ?? '').trim().toLowerCase().startsWith('https://');
    if (https(r['url']) || https(r['epg_url'])) {
      db.execute('UPDATE sources SET bad_cert_ok = 1 WHERE id = ?', [r['id']]);
    }
  }
  db.execute('DROP TRIGGER sync_sources_upd');
  db.execute(
    'CREATE TRIGGER sync_sources_upd AFTER UPDATE OF name, type, url, username, password, epg_url, user_agent, '
    'live_format, epg_offset, bad_cert_ok, uid ON sources '
    'WHEN NEW.uid IS NOT NULL AND $_syncLive BEGIN ${_syncLogSql('sources', 'NEW.uid')} END',
  );
}

/// v11: the id of a deleted profile or source is given again to the next
/// one: what was kept under it goes with it, however it is deleted (here,
/// by the account, by a restore). A new profile got the last searches of
/// the one deleted, a new source its guide.
void _migrateV11(Database db) {
  db.execute(
    "CREATE TRIGGER profiles_forget AFTER DELETE ON profiles BEGIN "
    "DELETE FROM kv WHERE key = 'search_recent_' || OLD.id; END",
  );
  db.execute(
    'CREATE TRIGGER sources_forget AFTER DELETE ON sources BEGIN '
    'DELETE FROM epg_programs WHERE source_id = OLD.id; '
    'DELETE FROM epg_channels WHERE source_id = OLD.id; '
    'DELETE FROM tmdb_cache WHERE source_id = OLD.id; '
    "DELETE FROM kv WHERE key = 'live.cat.' || OLD.id; END",
  );
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
