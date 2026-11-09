import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/secrets.dart';
import '../sync/sync_engine.dart' show SyncedSettings;
import 'repository.dart';

/// User preferences, persisted as JSON in the `kv` table.
class AppSettings extends ChangeNotifier implements SyncedSettings {
  AppSettings(this._repo) {
    _read(_repo.kvGetJson(_key) ?? const {});
    _synced = syncedValues();
  }

  void _read(Map<String, Object?> json) {
    activeSourceId = json['activeSourceId'] as int?;
    cacheMb = (json['cacheMb'] as int?) ?? 1024;
    backCacheMb = (json['backCacheMb'] as int?) ?? 384;
    diskCache = (json['diskCache'] as bool?) ?? true;
    seekStep = (json['seekStep'] as int?) ?? 10;
    hardwareDecoding = (json['hardwareDecoding'] as bool?) ?? true;
    deinterlace = (json['deinterlace'] as String?) ?? 'auto';
    audioLang = (json['audioLang'] as String?) ?? 'fr,fre,fra';
    subtitleLang = (json['subtitleLang'] as String?) ?? '';
    autoFullscreen = (json['autoFullscreen'] as bool?) ?? false;
    final preview = json['seekPreview'];
    seekPreview = preview == 'always' || preview == 'never' ? preview as String : 'auto';
    autoNextEpisode = (json['autoNextEpisode'] as bool?) ?? true;
    epgRefreshHours = (json['epgRefreshHours'] as int?) ?? 12;
    contentRefreshHours = (json['contentRefreshHours'] as int?) ?? 24;
    epgDays = (json['epgDays'] as int?) ?? 3;
    volume = (json['volume'] as num?)?.toDouble() ?? 100;
    activeProfileId = (json['activeProfileId'] as int?) ?? 1;
    parentalPin = Secrets.reveal(json['parentalPin'] as String?);
    tmdbKey = Secrets.reveal(json['tmdbKey'] as String?);
    recordingsDir = json['recordingsDir'] as String?;
    reminderLeadMinutes = (json['reminderLeadMinutes'] as int?) ?? 2;
    checkUpdates = (json['checkUpdates'] as bool?) ?? true;
    askProfileAtStart = (json['askProfileAtStart'] as bool?) ?? true;
    heroAutoplay = (json['heroAutoplay'] as bool?) ?? true;
    cleanNames = (json['cleanNames'] as bool?) ?? true;
    groupQualities = (json['groupQualities'] as bool?) ?? true;
    subtitleScale = (json['subtitleScale'] as num?)?.toDouble() ?? 1.0;
    preferredQuality = (json['preferredQuality'] as String?) ?? 'Auto';
    themeMode = (json['themeMode'] as String?) ?? 'dark';
  }

  static const _key = 'settings';
  final Repository _repo;

  int? activeSourceId;

  /// Forward demuxer cache in MiB (stored on disk when [diskCache] is on).
  late int cacheMb;

  /// Backward cache in MiB: keeps what was already watched so rewinding is instant.
  late int backCacheMb;
  late bool diskCache;

  /// Seconds jumped by ←/→.
  late int seekStep;
  late bool hardwareDecoding;

  /// 'auto' | 'yes' | 'no'
  late String deinterlace;
  late String audioLang;
  late String subtitleLang;
  late bool autoFullscreen;

  /// Picture of the instant hovered on the seek bar: 'auto' (unless the
  /// subscription allows a single connection) | 'always' | 'never'.
  late String seekPreview;
  late bool autoNextEpisode;
  late int epgRefreshHours;
  late int contentRefreshHours;
  late int epgDays;
  late double volume;

  /// Profile whose favourites and progress are shown.
  late int activeProfileId;

  /// Parental code (4 digits) or null when parental control is off. Stored
  /// encrypted on Windows like the source passwords.
  String? parentalPin;
  bool get parentalEnabled => parentalPin != null && parentalPin!.isNotEmpty;

  /// The Movie Database key (v3 key or v4 read token), or null.
  String? tmdbKey;

  /// Folder for recordings (null: Videos/Bobine).
  String? recordingsDir;

  /// How many minutes before a programme its reminder pops up.
  late int reminderLeadMinutes;
  late bool checkUpdates;

  /// Show "Qui regarde ?" at start when there are several profiles.
  late bool askProfileAtStart;

  /// The billboards of the home, films and series pages change by themselves.
  late bool heroAutoplay;

  /// "|FR| TF1 FHD ★" is shown as "TF1".
  late bool cleanNames;

  /// One channel for its FHD, HD and SD streams (the best one plays).
  late bool groupQualities;

  /// Size of the subtitles (mpv sub-scale: 0.75, 1 or 1.35).
  late double subtitleScale;

  /// Stream played for a channel with several qualities: 'Auto' (the best),
  /// 'FHD', 'HD' or 'SD'.
  late String preferredQuality;

  /// 'dark', 'light' or 'system' (follows the operating system).
  late String themeMode;

  void update(void Function(AppSettings s) change) {
    change(this);
    _save();
    notifyListeners();
  }

  /// Persists without notifying (for high frequency values like volume).
  void saveQuietly() => _save();

  void _save() {
    _repo.kvSet(_key, jsonEncode(_json()));
    // Preferences that follow the account: note the ones that changed.
    final now = syncedValues();
    for (final e in now.entries) {
      if (_synced[e.key] != e.value) _repo.noteSyncChange('settings', e.key);
    }
    _synced = now;
  }

  /// Preferences that follow the account to the user's other devices. The
  /// others (cache, decoding, volume, folders…) depend on the computer.
  static const syncedKeys = {
    'seekStep',
    'audioLang',
    'subtitleLang',
    'autoFullscreen',
    'autoNextEpisode',
    'epgRefreshHours',
    'contentRefreshHours',
    'epgDays',
    'parentalPin',
    'tmdbKey',
    'reminderLeadMinutes',
    'askProfileAtStart',
    'heroAutoplay',
    'cleanNames',
    'groupQualities',
    'subtitleScale',
    'preferredQuality',
  };

  /// Last synchronised values seen (to tell which ones the user changed).
  Map<String, Object?> _synced = const {};

  @override
  Map<String, Object?> syncedValues() {
    final j = _json()
      ..['parentalPin'] = parentalPin
      ..['tmdbKey'] = tmdbKey;
    return {for (final k in syncedKeys) k: j[k]};
  }

  @override
  void applySynced(Map<String, Object?> values) {
    _merge(values, syncedKeys);
    _synced = syncedValues();
    _repo.kvSet(_key, jsonEncode(_json()));
    notifyListeners();
  }

  /// Reads [values] (secrets in clear) over the current preferences, for
  /// the [allowed] keys; a malformed value leaves everything as it was.
  void _merge(Map<String, Object?> values, Set<String> allowed) {
    final current = _json()
      ..['parentalPin'] = parentalPin
      ..['tmdbKey'] = tmdbKey;
    final merged = {
      ...current,
      for (final e in values.entries)
        if (allowed.contains(e.key) && current.containsKey(e.key)) e.key: e.value,
    };
    try {
      _read(merged);
    } catch (_) {
      _read(current);
    }
  }

  Map<String, Object?> _json() => {
    'activeSourceId': activeSourceId,
    'cacheMb': cacheMb,
    'backCacheMb': backCacheMb,
    'diskCache': diskCache,
    'seekStep': seekStep,
    'hardwareDecoding': hardwareDecoding,
    'deinterlace': deinterlace,
    'audioLang': audioLang,
    'subtitleLang': subtitleLang,
    'autoFullscreen': autoFullscreen,
    'seekPreview': seekPreview,
    'autoNextEpisode': autoNextEpisode,
    'epgRefreshHours': epgRefreshHours,
    'contentRefreshHours': contentRefreshHours,
    'epgDays': epgDays,
    'volume': volume,
    'activeProfileId': activeProfileId,
    'parentalPin': Secrets.protect(parentalPin),
    'tmdbKey': Secrets.protect(tmdbKey),
    'recordingsDir': recordingsDir,
    'reminderLeadMinutes': reminderLeadMinutes,
    'checkUpdates': checkUpdates,
    'askProfileAtStart': askProfileAtStart,
    'heroAutoplay': heroAutoplay,
    'cleanNames': cleanNames,
    'groupQualities': groupQualities,
    'subtitleScale': subtitleScale,
    'preferredQuality': preferredQuality,
    'themeMode': themeMode,
  };

  /// Keys left out of backups: they only make sense on this computer.
  static const _localOnly = {'activeSourceId', 'activeProfileId', 'recordingsDir'};

  /// Preferences for a backup file. The parental code and the TMDB key are
  /// included (in clear) only with [secrets].
  Map<String, Object?> backupJson({required bool secrets}) {
    final j = _json()..removeWhere((k, _) => _localOnly.contains(k) || k == 'parentalPin' || k == 'tmdbKey');
    if (secrets) {
      j['parentalPin'] = parentalPin;
      j['tmdbKey'] = tmdbKey;
    }
    return j;
  }

  /// Applies the preferences of a backup file over the current ones.
  void restoreBackup(Map<String, Object?> backup) {
    // A malformed file must not break the settings.
    _merge(backup, _json().keys.toSet().difference(_localOnly));
    _save();
    notifyListeners();
  }
}
