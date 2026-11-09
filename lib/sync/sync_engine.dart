import 'dart:convert';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../core/secrets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../features/backup.dart' show sourceFingerprint;
import 'sync_crypto.dart';

/// An item as the server stores it: an opaque id, the time it was changed on
/// its device, whether it was deleted, and its encrypted content.
class RemoteItem {
  const RemoteItem({
    required this.id,
    required this.modifiedAt,
    required this.payload,
    this.deleted = false,
    this.rev = 0,
  });

  final String id;
  final int modifiedAt;
  final bool deleted;
  final String payload;

  /// Server order of the change (set by the server).
  final int rev;

  Map<String, Object?> toJson() => {'id': id, 'modified_at': modifiedAt, 'deleted': deleted, 'payload': payload};

  factory RemoteItem.fromJson(Map<String, Object?> j) => RemoteItem(
    id: j['id'] as String,
    modifiedAt: (j['modified_at'] as num).toInt(),
    deleted: j['deleted'] == true,
    payload: j['payload'] as String,
    rev: (j['rev'] as num?)?.toInt() ?? 0,
  );
}

/// The account's storage.
abstract class SyncRemote {
  /// Items changed after [afterRev], in the order they were changed.
  Future<List<RemoteItem>> pull(int afterRev, {int limit});

  /// Stores [items] where they are newer than the server's; returns the
  /// server's versions that are newer than the ones sent.
  Future<List<RemoteItem>> push(List<RemoteItem> items);
}

/// The preferences that follow the account.
abstract class SyncedSettings {
  /// Current values (secrets in clear).
  Map<String, Object?> syncedValues();

  /// Applies values received from the account (not noted as local changes).
  void applySynced(Map<String, Object?> values);
}

/// What a synchronisation brought.
class SyncChanges {
  /// Sources created on this device (to import).
  final Set<int> sourcesAdded = {};
  bool sources = false;
  bool profiles = false;
  bool userData = false;
  bool settings = false;
  int received = 0;
  int sent = 0;

  /// Items left aside: unreadable on the account, or impossible to apply or
  /// to send. The others went through.
  int skipped = 0;

  bool get any => sources || profiles || userData || settings;
}

/// The run was abandoned: the account it served is not this device's any
/// more (signed out, or another account, while it was on the network).
class SyncCancelled implements Exception {
  const SyncCancelled();
  @override
  String toString() => 'Synchronisation abandonnée.';
}

/// Synchronises the user's data with the account.
///
/// Local changes are noted in `sync_log` by triggers (see the v5 migration);
/// a run receives what changed on the account since the last one, applies
/// it where it is newer than the local change, then sends the local changes.
/// The first run on a device ("linking") notes everything the device holds,
/// and finds the sources and profiles that already exist on the account
/// (same server and login, same profile name) instead of duplicating them.
class SyncEngine {
  SyncEngine({required this.repo, required this.codec, required this.remote, required this.settings, this.cancelled});

  final Repository repo;
  final SyncCodec codec;
  final SyncRemote remote;
  final SyncedSettings settings;

  /// Asked after each wait on the network, before anything is written: true
  /// stops the run with [SyncCancelled].
  final bool Function()? cancelled;

  static const cursorKey = 'sync.cursor';
  static const pageSize = 1000;
  static const batchSize = 500;
  static const _version = 1;

  /// Largest payload the account accepts (`sync_items.payload`). A larger
  /// one makes the server refuse the whole batch it travels in.
  static const maxPayload = 16384;

  void _alive() {
    if (cancelled?.call() ?? false) throw const SyncCancelled();
  }

  Database get _db => repo.db;

  /// Last server change applied here, or null before the first sync.
  int? get cursor => int.tryParse(repo.kvGet(cursorKey) ?? '');

  /// Makes the next run a first sync (other account, or keys changed).
  void reset() => _db.execute('DELETE FROM kv WHERE key = ?', [cursorKey]);

  Future<SyncChanges> run() async {
    final changes = SyncChanges();
    final linking = cursor == null;
    if (linking) _seed();

    // Receive.
    var after = cursor ?? 0;
    final received = <RemoteItem>[];
    while (true) {
      final page = await remote.pull(after, limit: pageSize);
      _alive();
      received.addAll(page);
      for (final i in page) {
        after = math.max(after, i.rev);
      }
      if (page.length < pageSize) break;
    }
    final opened = await _open(received, changes);
    _alive();
    _apply(opened, changes, linking: linking, cursor: after);
    changes.received = received.length;

    // Send.
    for (var round = 0; round < 200; round++) {
      final (selected, batch) = _collect();
      var again = false;
      if (batch.isNotEmpty) {
        final items = <RemoteItem>[];
        final sent = <_Outgoing>[];
        for (final b in batch) {
          final payload = await codec.seal(b.id, b.record);
          if (payload.length > maxPayload) {
            // Alone it would make the server refuse everything sent with it,
            // at every synchronisation: it stays on this device.
            _acknowledge([b]);
            changes.skipped++;
            continue;
          }
          items.add(RemoteItem(id: b.id, modifiedAt: b.changedAt, deleted: b.record['d'] == null, payload: payload));
          sent.add(b);
        }
        _alive();
        final newer = items.isEmpty ? const <RemoteItem>[] : await remote.push(items);
        _alive();
        _acknowledge(sent);
        changes.sent += sent.length;
        if (newer.isNotEmpty) {
          // The account kept its version of these: its time is later.
          final mine = {for (final b in sent) b.id: b};
          final unseen = <RemoteItem>[];
          for (final theirs in newer) {
            final b = mine[theirs.id];
            if (b != null && theirs.rev > 0 && theirs.rev <= after && !await _fromNewerVersion(theirs)) {
              // A version this device had already received: the change sent
              // was made after it, on top of it. Its time says otherwise
              // only because a clock is wrong (this one late, or the one of
              // the device that wrote the other version ahead: until real
              // time caught up, that device won against every later
              // change). Sent again, dated after the version it replaces.
              _noteAfter(b.table, b.key, theirs);
              again = true;
            } else {
              unseen.add(theirs);
            }
          }
          if (unseen.isNotEmpty) {
            final others = await _open(unseen, changes);
            _alive();
            _apply(others, changes, linking: false);
          }
        }
      }
      if (selected < batchSize && !again) break;
    }
    return changes;
  }

  // ------------------------------------------------------------------ local

  /// Notes everything the device holds, without replacing changes already
  /// noted (their time is real). Sources, profiles and preferences get time 0:
  /// on the first sync, the account's version wins over them.
  void _seed() {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String key(String table) => 'json_array(${kSyncKeys[table]!.join(', ')})';
    final seeds = {
      'sources': ('uid', '0', ''),
      'profiles': ('uid', '0', ''),
      'favorites': (key('favorites'), 'added_at', ''),
      'progress': (key('progress'), 'updated_at', ''),
      'recent_channels': (key('recent_channels'), 'watched_at', ''),
      'category_prefs': (key('category_prefs'), '0', ''),
      'channel_prefs': (key('channel_prefs'), '0', ''),
      'reminders': (key('reminders'), '0', 'WHERE stop > $nowSec'),
    };
    _db.execute('BEGIN IMMEDIATE');
    try {
      for (final e in seeds.entries) {
        final (k, time, where) = e.value;
        _db.execute(
          "INSERT OR IGNORE INTO sync_log (tbl, key, changed_at) SELECT '${e.key}', $k, $time FROM ${e.key} $where",
        );
      }
      for (final name in settings.syncedValues().keys) {
        _db.execute("INSERT OR IGNORE INTO sync_log (tbl, key, changed_at) VALUES ('settings', ?, 0)", [name]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Columns sent for the rows of each synchronised table.
  static const _dataColumns = {
    'favorites': ['added_at'],
    'progress': ['position_ms', 'duration_ms', 'finished', 'updated_at', 'title', 'subtitle', 'image', 'series_ext'],
    'recent_channels': ['watched_at'],
    'category_prefs': ['hidden', 'locked', 'position'],
    'channel_prefs': ['hidden'],
    'reminders': ['channel_name', 'title', 'stop'],
  };

  String? _uidOf(String table, Object? id) {
    final rows = _db.select('SELECT uid FROM $table WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first['uid'] as String?;
  }

  int? _idOf(String table, Object? uid) {
    final rows = _db.select('SELECT id FROM $table WHERE uid = ?', [uid]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  String _naturalKey(String table, List<Object?> key) => jsonEncode([table, ...key]);

  /// Up to [batchSize] noted changes, as records to send. Notes that no
  /// longer lead anywhere (row of a deleted source or profile, preference
  /// that is not synchronised) are dropped.
  (int, List<_Outgoing>) _collect() {
    final rows = _db.select(
      'SELECT tbl, key, changed_at FROM sync_log '
      "ORDER BY CASE tbl WHEN 'profiles' THEN 0 WHEN 'sources' THEN 1 ELSE 2 END, changed_at LIMIT $batchSize",
    );
    final out = <_Outgoing>[];
    Map<String, Object?>? values;
    for (final r in rows) {
      final table = r['tbl'] as String, key = r['key'] as String, changedAt = r['changed_at'] as int;
      final record = switch (table) {
        'settings' => _settingRecord(key, values ??= settings.syncedValues()),
        'sources' => _sourceRecord(key),
        'profiles' => _profileRecord(key),
        _ => _rowRecord(table, key),
      };
      if (record == null) {
        _db.execute('DELETE FROM sync_log WHERE tbl = ? AND key = ? AND changed_at = ?', [table, key, changedAt]);
        continue;
      }
      record['v'] = _version;
      final id = codec.itemId(_naturalKey(table, record['k'] as List<Object?>));
      out.add(_Outgoing(table, key, changedAt, id, record));
    }
    return (rows.length, out);
  }

  Map<String, Object?>? _settingRecord(String name, Map<String, Object?> values) {
    if (!values.containsKey(name)) return null;
    return {
      't': 'settings',
      'k': [name],
      'd': {'value': values[name]},
    };
  }

  Map<String, Object?> _sourceRecord(String uid) {
    final rows = _db.select('SELECT * FROM sources WHERE uid = ?', [uid]);
    final s = rows.isEmpty ? null : Source.fromRow(rows.first);
    return {
      't': 'sources',
      'k': [uid],
      if (s != null)
        'd': {
          'name': s.name,
          'type': s.type.name,
          'url': s.url,
          'username': s.username,
          'password': s.password,
          'epg_url': s.epgUrl,
          'user_agent': s.userAgent,
          'live_format': s.liveFormat,
          'epg_offset': s.epgOffsetMinutes,
        },
    };
  }

  Map<String, Object?> _profileRecord(String uid) {
    final rows = _db.select('SELECT name, color, kids FROM profiles WHERE uid = ?', [uid]);
    return {
      't': 'profiles',
      'k': [uid],
      if (rows.isNotEmpty) 'd': {for (final c in rows.first.keys) c: rows.first[c]},
    };
  }

  Map<String, Object?>? _rowRecord(String table, String key) {
    final columns = kSyncKeys[table];
    if (columns == null) return null;
    final List<Object?> local;
    try {
      local = jsonDecode(key) as List<Object?>;
    } catch (_) {
      return null;
    }
    if (local.length != columns.length) return null;
    final natural = <Object?>[];
    for (var i = 0; i < columns.length; i++) {
      final parent = switch (columns[i]) {
        'profile_id' => 'profiles',
        'source_id' => 'sources',
        _ => null,
      };
      if (parent == null) {
        natural.add(local[i]);
      } else {
        final uid = _uidOf(parent, local[i]);
        if (uid == null) return null; // its source or profile is gone (and noted)
        natural.add(uid);
      }
    }
    final rows = _db.select(
      'SELECT ${_dataColumns[table]!.join(', ')} FROM $table WHERE ${columns.map((c) => '$c = ?').join(' AND ')}',
      local,
    );
    return {
      't': table,
      'k': natural,
      if (rows.isNotEmpty) 'd': {for (final c in rows.first.keys) c: rows.first[c]},
    };
  }

  /// Forgets the notes that were sent, unless they changed meanwhile.
  void _acknowledge(List<_Outgoing> sent) {
    for (final s in sent) {
      _db.execute('DELETE FROM sync_log WHERE tbl = ? AND key = ? AND changed_at = ?', [s.table, s.key, s.changedAt]);
    }
  }

  // --------------------------------------------------------------- incoming

  /// Decrypts [items]. One that cannot be read (damaged on the account) is
  /// left aside and counted in [SyncChanges.skipped]: it used to stop every
  /// synchronisation, for good, and sign the device out. When none can be
  /// read, the keys of this device are the ones in doubt: [SyncKeyException].
  Future<List<_Incoming>> _open(List<RemoteItem> items, SyncChanges changes) async {
    final out = <_Incoming>[];
    var read = 0, unreadable = 0;
    for (final i in items) {
      final Map<String, Object?> record;
      try {
        record = await codec.open(i.id, i.payload);
      } on SyncKeyException {
        unreadable++;
        continue;
      }
      read++;
      try {
        if ((record['v'] as int? ?? 0) > _version) continue; // made by a newer Bobine
        final key = record['k'];
        if (record['t'] is! String || key is! List) continue;
        // A record is only accepted under the id it belongs to.
        if (codec.itemId(_naturalKey(record['t'] as String, key)) != i.id) continue;
        final data = record['d'];
        out.add(
          _Incoming(record['t'] as String, key, i.deleted || data is! Map ? null : data.cast<String, Object?>(), i),
        );
      } catch (_) {
        changes.skipped++; // readable, but not a record
      }
    }
    if (unreadable > 0) {
      if (read == 0 && !await _keysReadTheAccount()) throw SyncKeyException();
      changes.skipped += unreadable;
    }
    const order = {'profiles': 0, 'sources': 1};
    out.sort((a, b) => (order[a.table] ?? 2).compareTo(order[b.table] ?? 2));
    return out;
  }

  /// Whether [item] was written by a newer Bobine than this one. Such an
  /// item was received and left aside, not applied: a change made here was
  /// not made "on top of it", and an old version must not write over what
  /// it could not read. (A damaged item is another matter: the device that
  /// holds the real thing does write over it.)
  Future<bool> _fromNewerVersion(RemoteItem item) async {
    try {
      final v = (await codec.open(item.id, item.payload))['v'];
      return v is int && v > _version;
    } on SyncKeyException {
      return false;
    }
  }

  /// Whether these keys read anything of what the account holds: yes means
  /// that what they cannot read is damaged, no that the account is encrypted
  /// with other keys (its password changed on another device).
  Future<bool> _keysReadTheAccount() async {
    for (final i in await remote.pull(0, limit: 40)) {
      try {
        await codec.open(i.id, i.payload);
        return true;
      } on SyncKeyException {
        continue;
      }
    }
    return false;
  }

  /// When the device holds a change of its own newer than [modifiedAt].
  bool _localIsNewer(String table, String key, int modifiedAt) {
    final rows = _db.select('SELECT changed_at FROM sync_log WHERE tbl = ? AND key = ?', [table, key]);
    return rows.isNotEmpty && (rows.first['changed_at'] as int) > modifiedAt;
  }

  void _forget(String table, String key) => _db.execute('DELETE FROM sync_log WHERE tbl = ? AND key = ?', [table, key]);

  /// Notes [key] as changed after [received], so that this device's version
  /// is sent and wins: used when what the account says (a deletion, an empty
  /// value) is deliberately not applied here.
  void _noteAfter(String table, String key, RemoteItem received) => _db.execute(
    'INSERT OR REPLACE INTO sync_log (tbl, key, changed_at) VALUES (?, ?, ?)',
    [table, key, math.max(DateTime.now().millisecondsSinceEpoch, received.modifiedAt + 1)],
  );

  /// Profiles that hold favourites, progress, recent channels or reminders.
  Set<int> _profilesWithData() => {
    for (final t in kSyncKeys.entries.where((e) => e.value.contains('profile_id')))
      for (final r in _db.select('SELECT DISTINCT profile_id FROM ${t.key}')) r['profile_id'] as int,
  };

  /// Applies received items in one transaction, without noting them as
  /// local changes. The account wins ties.
  void _apply(List<_Incoming> items, SyncChanges changes, {required bool linking, int? cursor}) {
    final settingValues = <String, Object?>{};
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('INSERT INTO sync_mute VALUES (1)');
      final adopted = <int>{};
      final remoteUids = {
        for (final i in items)
          if (i.table == 'sources' || i.table == 'profiles') '${i.table} ${i.key.first}',
      };
      // What this device held before its first sync (never sent anywhere).
      final ownData = linking ? _profilesWithData() : const <int>{};
      Map<String, Object?>? localSettings;
      final deletedProfiles = <_Incoming>[];
      // Each item on its own: one that cannot be applied (a shape this
      // version does not expect) is undone and left aside, instead of
      // failing the whole synchronisation, this time and every next one.
      void each(_Incoming i, void Function() apply) {
        _db.execute('SAVEPOINT sync_item');
        try {
          apply();
        } catch (_) {
          _db.execute('ROLLBACK TO sync_item');
          changes.skipped++;
        }
        _db.execute('RELEASE sync_item');
      }

      for (final i in items) {
        each(i, () {
          switch (i.table) {
            case 'profiles':
              if (i.data == null) {
                deletedProfiles.add(i);
              } else {
                _applyProfile(i, changes, linking, adopted, remoteUids, ownData);
              }
            case 'sources':
              _applySource(i, changes, linking, adopted, remoteUids);
            case 'settings':
              final name = '${i.key.first}';
              if (!_localIsNewer('settings', name, i.item.modifiedAt) && i.data != null) {
                final value = i.data!['value'];
                if (linking && value == null && (localSettings ??= settings.syncedValues())[name] != null) {
                  // First sync: an account without this value (parental code,
                  // TMDB key) does not erase the one set on this device, which
                  // is sent to the account instead.
                  _noteAfter('settings', name, i.item);
                } else {
                  settingValues[name] = value;
                  _forget('settings', name);
                }
              }
            default:
              _applyRow(i, changes);
          }
        });
      }
      // Deleted profiles last: whether one is the only profile left here is
      // known once the others are in.
      for (final i in deletedProfiles) {
        each(i, () => _applyProfile(i, changes, linking, adopted, remoteUids, ownData));
      }
      if (cursor != null) {
        _db.execute('INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)', [cursorKey, '$cursor']);
      }
      _db.execute('DELETE FROM sync_mute');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    if (settingValues.isNotEmpty) {
      settings.applySynced(settingValues);
      changes.settings = true;
    }
  }

  /// On the first sync, a local profile / source not yet on the account takes
  /// the uid of its twin there; what was noted for it follows.
  void _adopt(String table, int id, String oldUid, String uid, Set<int> adopted) {
    _db.execute('UPDATE $table SET uid = ? WHERE id = ?', [uid, id]);
    _db.execute('UPDATE OR REPLACE sync_log SET key = ? WHERE tbl = ? AND key = ?', [uid, table, oldUid]);
    adopted.add(id);
  }

  void _applyProfile(
    _Incoming i,
    SyncChanges changes,
    bool linking,
    Set<int> adopted,
    Set<String> remoteUids,
    Set<int> ownData,
  ) {
    final uid = '${i.key.first}';
    final d = i.data;
    var id = _idOf('profiles', uid);
    if (id == null && d != null && linking) {
      final twin = _db
          .select('SELECT id, uid FROM profiles WHERE lower(name) = lower(?)', [d['name']])
          .where((r) => !adopted.contains(r['id']) && !remoteUids.contains('profiles ${r['uid']}'))
          .firstOrNull;
      if (twin != null) {
        _adopt('profiles', twin['id'] as int, twin['uid'] as String, uid, adopted);
        id = twin['id'] as int;
      }
    }
    if (_localIsNewer('profiles', uid, i.item.modifiedAt)) return;
    _forget('profiles', uid);
    if (d == null) {
      if (id == null) return;
      // A device always keeps one profile. On its first sync it also keeps a
      // profile it used: "Moi" has the same uid on every device, and its
      // favourites and progress here were never on the account, so deleting
      // it with them (because "Moi" was deleted elsewhere) would lose them.
      final last = (_db.select('SELECT count(*) AS n FROM profiles').first['n'] as int) <= 1;
      if (last || (linking && ownData.contains(id))) {
        // It stays here, so it lives on the account again.
        _noteAfter('profiles', uid, i.item);
      } else {
        _db.execute('DELETE FROM profiles WHERE id = ?', [id]);
        changes.profiles = true;
      }
      return;
    }
    final values = [d['name'] ?? 'Profil', d['color'] ?? 0xFFFFB547, d['kids'] ?? 0];
    if (id != null) {
      _db.execute('UPDATE profiles SET name = ?, color = ?, kids = ? WHERE id = ?', [...values, id]);
    } else {
      _db.execute('INSERT INTO profiles (name, color, kids, created_at, uid) VALUES (?, ?, ?, ?, ?)', [
        ...values,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        uid,
      ]);
    }
    changes.profiles = true;
  }

  static Source? _sourceFrom(Map<String, Object?>? d) {
    if (d == null) return null;
    return Source(
      id: 0,
      name: '${d['name'] ?? 'Source'}',
      type: d['type'] == 'xtream' ? SourceType.xtream : SourceType.m3u,
      url: '${d['url'] ?? ''}',
      username: d['username'] as String?,
      password: d['password'] as String?,
      epgUrl: d['epg_url'] as String?,
      userAgent: d['user_agent'] as String?,
      liveFormat: (d['live_format'] as String?) ?? 'ts',
      epgOffsetMinutes: (d['epg_offset'] as int?) ?? 0,
    );
  }

  void _applySource(_Incoming i, SyncChanges changes, bool linking, Set<int> adopted, Set<String> remoteUids) {
    final uid = '${i.key.first}';
    final s = _sourceFrom(i.data);
    var id = _idOf('sources', uid);
    if (id == null && s != null && linking) {
      final fingerprint = sourceFingerprint(s);
      final twin = _db
          .select('SELECT * FROM sources')
          .where((r) => !adopted.contains(r['id']) && !remoteUids.contains('sources ${r['uid']}'))
          .where((r) => sourceFingerprint(Source.fromRow(r)) == fingerprint)
          .firstOrNull;
      if (twin != null) {
        _adopt('sources', twin['id'] as int, twin['uid'] as String, uid, adopted);
        id = twin['id'] as int;
      }
    }
    if (_localIsNewer('sources', uid, i.item.modifiedAt)) return;
    _forget('sources', uid);
    if (s == null) {
      if (id != null) {
        for (final t in ['epg_programs', 'epg_channels', 'tmdb_cache']) {
          _db.execute('DELETE FROM $t WHERE source_id = ?', [id]);
        }
        _db.execute('DELETE FROM sources WHERE id = ?', [id]);
        changes.sources = true;
      }
      return;
    }
    final values = [
      s.name,
      Secrets.protect(s.url),
      s.username,
      Secrets.protect(s.password),
      Secrets.protect(s.epgUrl),
      s.userAgent,
      s.liveFormat,
      s.epgOffsetMinutes,
    ];
    if (id != null) {
      _db.execute(
        'UPDATE sources SET name = ?, url = ?, username = ?, password = ?, epg_url = ?, user_agent = ?, '
        'live_format = ?, epg_offset = ?, type = ? WHERE id = ?',
        [...values, s.type.name, id],
      );
    } else {
      _db.execute(
        'INSERT INTO sources (name, url, username, password, epg_url, user_agent, live_format, epg_offset, type, '
        'created_at, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, s.type.name, DateTime.now().millisecondsSinceEpoch ~/ 1000, uid],
      );
      changes.sourcesAdded.add(_db.lastInsertRowId);
    }
    changes.sources = true;
  }

  void _applyRow(_Incoming i, SyncChanges changes) {
    final columns = kSyncKeys[i.table];
    final dataColumns = _dataColumns[i.table];
    if (columns == null || dataColumns == null || i.key.length != columns.length) return; // newer Bobine
    final local = <Object?>[];
    for (var c = 0; c < columns.length; c++) {
      final parent = switch (columns[c]) {
        'profile_id' => 'profiles',
        'source_id' => 'sources',
        _ => null,
      };
      if (parent == null) {
        local.add(i.key[c]);
      } else {
        final id = _idOf(parent, i.key[c]);
        if (id == null) return; // its source or profile was deleted
        local.add(id);
      }
    }
    final key =
        _db.select('SELECT json_array(${List.filled(local.length, '?').join(', ')}) AS k', local).first['k'] as String;
    if (_localIsNewer(i.table, key, i.item.modifiedAt)) return;
    _forget(i.table, key);
    final where = columns.map((c) => '$c = ?').join(' AND ');
    if (i.data == null) {
      _db.execute('DELETE FROM ${i.table} WHERE $where', local);
    } else {
      final all = [...columns, ...dataColumns];
      try {
        _db.execute(
          'INSERT OR REPLACE INTO ${i.table} (${all.join(', ')}) VALUES (${List.filled(all.length, '?').join(', ')})',
          [...local, for (final c in dataColumns) i.data![c]],
        );
      } on SqliteException {
        return; // incomplete record: the local row stays as it is
      }
    }
    changes.userData = true;
  }
}

class _Outgoing {
  _Outgoing(this.table, this.key, this.changedAt, this.id, this.record);
  final String table;
  final String key;
  final int changedAt;
  final String id;
  final Map<String, Object?> record;
}

class _Incoming {
  _Incoming(this.table, this.key, this.data, this.item);
  final String table;
  final List<Object?> key;
  final Map<String, Object?>? data;
  final RemoteItem item;
}
