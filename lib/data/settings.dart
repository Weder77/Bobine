import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/secrets.dart';
import 'repository.dart';

/// User preferences, persisted as JSON in the `kv` table.
class AppSettings extends ChangeNotifier {
  AppSettings(this._repo) {
    _read(_repo.kvGetJson(_key) ?? const {});
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

  void update(void Function(AppSettings s) change) {
    change(this);
    _save();
    notifyListeners();
  }

  /// Persists without notifying (for high frequency values like volume).
  void saveQuietly() => _save();

  void _save() => _repo.kvSet(_key, jsonEncode(_json()));

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
    final current = _json()
      ..['parentalPin'] = parentalPin
      ..['tmdbKey'] = tmdbKey;
    final merged = {
      ...current,
      for (final e in backup.entries)
        if (!_localOnly.contains(e.key) && current.containsKey(e.key)) e.key: e.value,
    };
    try {
      _read(merged);
    } catch (_) {
      _read(current); // a malformed file must not break the settings
    }
    _save();
    notifyListeners();
  }
}
