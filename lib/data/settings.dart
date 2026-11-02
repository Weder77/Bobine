import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'repository.dart';

/// User preferences, persisted as JSON in the `kv` table.
class AppSettings extends ChangeNotifier {
  AppSettings(this._repo) {
    final json = _repo.kvGetJson(_key) ?? const {};
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

  void update(void Function(AppSettings s) change) {
    change(this);
    _save();
    notifyListeners();
  }

  /// Persists without notifying (for high frequency values like volume).
  void saveQuietly() => _save();

  void _save() {
    _repo.kvSet(
      _key,
      jsonEncode({
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
      }),
    );
  }
}
