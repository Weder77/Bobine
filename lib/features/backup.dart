import 'dart:convert';
import 'dart:io';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/settings.dart';

/// What a restore brought back.
class RestoreReport {
  int sourcesCreated = 0;
  int sourcesMatched = 0;
  int profilesCreated = 0;
  int favorites = 0;
  int progress = 0;
  int other = 0;

  /// Sources of the file that exist neither here nor in the file (saved
  /// without credentials): their favourites and progress were skipped.
  final List<String> skippedSources = [];

  /// Profiles of the file not created: there were already [Profile.max]
  /// here. Their favourites and progress were skipped.
  final List<String> skippedProfiles = [];

  @override
  String toString() => [
    if (sourcesCreated > 0) '$sourcesCreated source(s) ajoutée(s)',
    if (sourcesMatched > 0) '$sourcesMatched source(s) retrouvée(s)',
    if (profilesCreated > 0) '$profilesCreated profil(s) créé(s)',
    if (favorites > 0) '$favorites favori(s)',
    if (progress > 0) '$progress reprise(s)',
    if (favorites == 0 &&
        progress == 0 &&
        sourcesCreated == 0 &&
        profilesCreated == 0 &&
        skippedSources.isEmpty &&
        skippedProfiles.isEmpty)
      'rien de nouveau, tout était déjà là',
    if (skippedSources.isNotEmpty) 'ignoré : ${skippedSources.join(', ')} (source absente)',
    if (skippedProfiles.isNotEmpty) 'ignoré : ${skippedProfiles.join(', ')} (${Profile.max} profils au maximum)',
  ].join(' · ');
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Exports and restores everything the user made: profiles, favourites,
/// progress, hidden / locked categories, reminders, preferences and,
/// optionally, the sources with their credentials.
class BackupService {
  BackupService(this._repo, this._settings);

  static const format = 'bobine-backup';

  /// Files saved when the app was called Lumen.
  static const _legacyFormats = {'lumen-backup'};
  static const version = 1;

  final Repository _repo;
  final AppSettings _settings;

  String suggestedFileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'bobine-sauvegarde-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  /// The backup as JSON. Without [credentials] the file holds no password,
  /// address with credentials, parental code or TMDB key.
  Map<String, Object?> build({required bool credentials}) {
    List<Map<String, Object?>> rows(String sql, [List<Object?> args = const []]) => [
      for (final r in _repo.db.select(sql, args)) {for (final c in r.keys) c: r[c]},
    ];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'withCredentials': credentials,
      'settings': _settings.backupJson(secrets: credentials),
      'sources': [
        for (final s in _repo.sources())
          {
            'id': s.id,
            'name': s.name,
            'type': s.type.name,
            'fingerprint': sourceFingerprint(s),
            'liveFormat': s.liveFormat,
            'epgOffset': s.epgOffsetMinutes,
            'userAgent': s.userAgent,
            if (credentials) ...{'url': s.url, 'username': s.username, 'password': s.password, 'epgUrl': s.epgUrl},
          },
      ],
      'profiles': rows('SELECT id, name, color, kids, avatar FROM profiles ORDER BY id'),
      'favorites': rows('SELECT * FROM favorites'),
      'progress': rows('SELECT * FROM progress'),
      'recent_channels': rows('SELECT * FROM recent_channels'),
      'category_prefs': rows('SELECT * FROM category_prefs'),
      'channel_prefs': rows('SELECT * FROM channel_prefs'),
      'reminders': rows(
        'SELECT profile_id, source_id, channel_ext, channel_name, title, start, stop FROM reminders WHERE stop > ?',
        [now],
      ),
    };
  }

  Future<void> exportTo(String path, {required bool credentials}) async {
    final json = const JsonEncoder.withIndent('  ').convert(build(credentials: credentials));
    await File(path).writeAsString(json, flush: true);
  }

  Future<RestoreReport> restoreFrom(String path) async {
    final Object? json;
    try {
      json = jsonDecode(await File(path).readAsString());
    } catch (_) {
      throw BackupException("Ce fichier n'est pas une sauvegarde Bobine lisible.");
    }
    if (json is! Map) throw BackupException("Ce fichier n'est pas une sauvegarde Bobine.");
    return restore(json.cast<String, Object?>());
  }

  /// Merges a backup into this installation: existing data is kept, the
  /// file adds to it (and wins on preferences; the most recent position wins
  /// for progress).
  RestoreReport restore(Map<String, Object?> j) {
    if (j['format'] != format && !_legacyFormats.contains(j['format'])) {
      throw BackupException("Ce fichier n'est pas une sauvegarde Bobine.");
    }
    if ((j['version'] as int? ?? 0) > version) {
      throw BackupException('Sauvegarde faite par une version plus récente de Bobine : mets l’app à jour.');
    }
    final report = RestoreReport();
    List<Map<String, Object?>> list(String key) => [
      for (final r in (j[key] as List? ?? const [])) (r as Map).cast<String, Object?>(),
    ];

    // Everything in one transaction: a busy database (an import running) is
    // said so before anything is written, and a restore that fails halfway
    // leaves nothing behind (no profile without its favourites).
    final db = _repo.db;
    try {
      db.execute('BEGIN IMMEDIATE');
    } catch (_) {
      throw BackupException('Base occupée (mise à jour en cours) : réessaie dans un instant.');
    }
    try {
      // Sources: same server and account (fingerprint), else same name and type,
      // else created from the file when it carries the credentials.
      final sources = <int, int>{};
      final local = _repo.sources();
      for (final b in list('sources')) {
        final type = b['type'] == 'xtream' ? SourceType.xtream : SourceType.m3u;
        final match =
            local.where((s) => sourceFingerprint(s) == b['fingerprint']).firstOrNull ??
            local.where((s) => s.type == type && s.name == b['name']).firstOrNull;
        if (match != null) {
          sources[b['id'] as int] = match.id;
          report.sourcesMatched++;
        } else if (b['url'] is String && (b['url'] as String).isNotEmpty) {
          sources[b['id'] as int] = _repo.insertSource(
            name: '${b['name']}',
            type: type,
            url: b['url'] as String,
            username: b['username'] as String?,
            password: b['password'] as String?,
            epgUrl: b['epgUrl'] as String?,
            userAgent: b['userAgent'] as String?,
            liveFormat: (b['liveFormat'] as String?) ?? 'ts',
            epgOffset: (b['epgOffset'] as int?) ?? 0,
          );
          report.sourcesCreated++;
        } else {
          report.skippedSources.add('${b['name']}');
        }
      }

      // Profiles: matched by name, created while there is room for them.
      final profiles = <int, int>{};
      final skippedProfiles = <Object?>{};
      final localProfiles = _repo.profiles();
      for (final b in list('profiles')) {
        final name = '${b['name']}';
        final avatar = b['avatar'] is String ? b['avatar'] as String : null;
        final match = localProfiles.where((p) => p.name.toLowerCase() == name.toLowerCase()).firstOrNull;
        if (match != null) {
          profiles[b['id'] as int] = match.id;
          // "Moi" exists on every installation: without this, its picture
          // would never come back on a new computer. One chosen here stays.
          if (match.avatar == null && avatar != null) {
            _repo.updateProfile(match.id, name: match.name, color: match.color, kids: match.kids, avatar: avatar);
          }
        } else if (_repo.canAddProfile) {
          profiles[b['id'] as int] = _repo.createProfile(
            name: name,
            color: (b['color'] as int?) ?? 0xFFFFB547,
            kids: (b['kids'] as int?) == 1,
            avatar: avatar,
          );
          report.profilesCreated++;
        } else {
          skippedProfiles.add(b['id']);
          report.skippedProfiles.add(name);
        }
      }

      int? src(Map<String, Object?> r) => sources[r['source_id']];
      // Null for the rows of a profile left out.
      int? prof(Map<String, Object?> r) =>
          skippedProfiles.contains(r['profile_id']) ? null : profiles[r['profile_id']] ?? 1;
      for (final r in list('favorites')) {
        final s = src(r), p = prof(r);
        if (s == null || p == null) continue;
        db.execute(
          'INSERT OR IGNORE INTO favorites (profile_id, source_id, kind, ext_id, added_at) VALUES (?, ?, ?, ?, ?)',
          [p, s, r['kind'], r['ext_id'], r['added_at']],
        );
        report.favorites += db.updatedRows;
      }
      for (final r in list('progress')) {
        final s = src(r), p = prof(r);
        if (s == null || p == null) continue;
        db.execute(
          'INSERT INTO progress (profile_id, source_id, kind, ext_id, position_ms, duration_ms, finished, updated_at, '
          'title, subtitle, image, series_ext) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT (profile_id, source_id, kind, ext_id) DO UPDATE SET position_ms = excluded.position_ms, '
          'duration_ms = excluded.duration_ms, finished = excluded.finished, updated_at = excluded.updated_at '
          'WHERE excluded.updated_at > progress.updated_at',
          [
            p,
            s,
            r['kind'],
            r['ext_id'],
            r['position_ms'],
            r['duration_ms'],
            r['finished'],
            r['updated_at'],
            r['title'],
            r['subtitle'],
            r['image'],
            r['series_ext'],
          ],
        );
        report.progress += db.updatedRows;
      }
      for (final r in list('recent_channels')) {
        final s = src(r), p = prof(r);
        if (s == null || p == null) continue;
        db.execute(
          'INSERT INTO recent_channels (profile_id, source_id, ext_id, watched_at) VALUES (?, ?, ?, ?) '
          'ON CONFLICT (profile_id, source_id, ext_id) DO UPDATE SET watched_at = max(watched_at, excluded.watched_at)',
          [p, s, r['ext_id'], r['watched_at']],
        );
        report.other++;
      }
      for (final r in list('category_prefs')) {
        final s = src(r);
        if (s == null) continue;
        db.execute(
          'INSERT OR REPLACE INTO category_prefs (source_id, kind, ext_id, hidden, locked, position) VALUES (?, ?, ?, ?, ?, ?)',
          [s, r['kind'], r['ext_id'], r['hidden'], r['locked'], r['position']],
        );
        report.other++;
      }
      for (final r in list('channel_prefs')) {
        final s = src(r);
        if (s == null) continue;
        db.execute('INSERT OR REPLACE INTO channel_prefs (source_id, ext_id, hidden) VALUES (?, ?, ?)', [
          s,
          r['ext_id'],
          r['hidden'],
        ]);
        report.other++;
      }
      for (final r in list('reminders')) {
        final s = src(r), p = prof(r);
        if (s == null || p == null) continue;
        db.execute(
          'INSERT OR IGNORE INTO reminders (profile_id, source_id, channel_ext, channel_name, title, start, stop) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [p, s, r['channel_ext'], r['channel_name'], r['title'], r['start'], r['stop']],
        );
        report.other++;
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      throw BackupException('Restauration interrompue : $e');
    }

    final settings = j['settings'];
    if (settings is Map) _settings.restoreBackup(settings.cast<String, Object?>());
    return report;
  }
}

/// Identifies a source (type, server, account) without its password, so a
/// backup made without credentials can still find it again.
String sourceFingerprint(Source s) {
  String id;
  if (s.isXtream) {
    final u = Uri.tryParse(s.baseUrl);
    id = 'xtream|${u?.host.toLowerCase()}:${u?.port}|${(s.username ?? '').toLowerCase()}';
  } else {
    final u = Uri.tryParse(s.url.trim());
    final user = u?.queryParameters['username'] ?? '';
    id = u == null || !u.hasScheme
        ? 'm3u|file|${s.url.trim().toLowerCase()}'
        : 'm3u|${u.host.toLowerCase()}${u.path}|$user';
  }
  // FNV-1a 64 bits: enough to tell sources apart, not reversible to the account.
  var h = -0x340d631b7bdddcdb; // 0xcbf29ce484222325 as a signed 64-bit int
  for (final b in utf8.encode(id)) {
    h ^= b;
    h *= 0x100000001b3;
  }
  String hex(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return hex(h >> 32) + hex(h);
}
