import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/settings.dart';

/// Something the player can open.
class PlayItem {
  const PlayItem({
    required this.kind,
    required this.sourceId,
    required this.extId,
    required this.url,
    required this.title,
    this.subtitle,
    this.image,
    this.userAgent,
    this.seriesExt,
  });

  final ContentKind kind;
  final int sourceId;
  final String extId;
  final String url;
  final String title;
  final String? subtitle;
  final String? image;
  final String? userAgent;
  final String? seriesExt;

  bool get isLive => kind == ContentKind.live;
}

/// A contiguous range of the stream that is already in the demuxer cache.
class CachedRange {
  const CachedRange(this.start, this.end);
  final Duration start;
  final Duration end;
}

class CacheState {
  const CacheState({this.ranges = const [], this.forwardBytes = 0, this.inputRate = 0, this.cacheEnd});
  final List<CachedRange> ranges;
  final int forwardBytes;

  /// Download speed of the stream in bytes/s.
  final int inputRate;
  final Duration? cacheEnd;
}

/// Owns the single, long-lived libmpv instance.
///
/// Keeping one player for the whole app session means no player / GPU texture
/// re-creation between channels, and the live preview can turn into the full
/// screen player without re-opening the stream.
///
/// Caching strategy (what makes seeking instant):
///  * a large forward demuxer cache filled as fast as the network allows
///    (`cache-secs` very high, bounded by `demuxer-max-bytes`), so jumping
///    +10/+30 s lands inside data that is already downloaded;
///  * a backward cache (`demuxer-max-back-bytes`) so going back is instant too;
///  * `demuxer-seekable-cache` lets mpv seek inside those cached ranges
///    without any network request (also gives "pause / rewind" on live TV);
///  * cache stored on disk by default so a 1 GiB cache does not cost RAM;
///  * persistent HTTP connections + automatic reconnection for flaky IPTV
///    servers; seeks outside the cache reuse the connection (HTTP range).
class PlayerService {
  PlayerService(this.settings, this.cacheDir);

  final AppSettings settings;
  final String cacheDir;

  late final Player player;
  late final VideoController video;

  final ValueNotifier<PlayItem?> current = ValueNotifier(null);

  /// Human readable status ("Reconnexion…") or null.
  final ValueNotifier<String?> status = ValueNotifier(null);

  /// Completes once libmpv is configured. The UI does not wait for it (the
  /// video texture needs a visible window on some platforms), only [play].
  late final Future<void> ready;

  bool _autoDeinterlaceNative = false;
  DateTime? _bufferingSince;
  Timer? _watchdog;
  int _reconnects = 0;
  DateTime _lastReconnect = DateTime.fromMillisecondsSinceEpoch(0);
  final List<StreamSubscription> _subs = [];
  Timer? _volumeSave;

  static const _protocols = [
    'udp', 'rtp', 'rtsp', 'rtmp', 'rtmps', 'tcp', 'tls', 'data', 'file', 'http', 'https',
    'httpproxy', 'crypto', 'hls', 'mmsh', 'mmst', 'srt',
  ];

  /// Creates the player synchronously and finishes configuration in the
  /// background (see [ready]).
  void init() {
    ready = _init();
  }

  Future<void> _init() async {
    player = Player(
      configuration: PlayerConfiguration(
        title: 'Lumen',
        // libass renders every subtitle type (ASS styling, PGS/DVB bitmaps)
        // directly into the video, which is the most compatible option.
        libass: true,
        logLevel: MPVLogLevel.warn,
        bufferSize: settings.cacheMb * 1024 * 1024,
        protocolWhitelist: _protocols,
      ),
    );
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        hwdec: settings.hardwareDecoding ? 'auto-safe' : 'no',
        enableHardwareAcceleration: true,
      ),
    );
    await applyTuning();
    await player.setVolume(settings.volume);

    _subs.add(player.stream.completed.listen((done) {
      if (done) _onEnded();
    }));
    _subs.add(player.stream.error.listen((e) {
      debugPrint('mpv error: $e');
      final item = current.value;
      // Only network / loading failures interrupt a live stream; decoder or
      // audio-device messages are not fatal.
      if (item != null && item.isLive && isFatalError(e)) _onEnded();
    }));
    _subs.add(player.stream.buffering.listen((b) {
      _bufferingSince = b ? (_bufferingSince ?? DateTime.now()) : null;
    }));
    // A live stream stuck buffering (server stopped sending) is reopened.
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      final item = current.value;
      final since = _bufferingSince;
      if (item != null && item.isLive && since != null &&
          DateTime.now().difference(since).inSeconds >= 20) {
        _bufferingSince = null;
        _onEnded();
      }
    });
    _subs.add(player.stream.playing.listen((p) {
      if (p) {
        status.value = null;
        // A stream that plays for a while resets the reconnection budget.
        if (DateTime.now().difference(_lastReconnect).inSeconds > 30) _reconnects = 0;
      }
    }));
    _subs.add(player.stream.videoParams.listen((_) => _maybeDeinterlace()));
    _subs.add(player.stream.volume.listen((v) {
      settings.volume = v;
      _volumeSave?.cancel();
      _volumeSave = Timer(const Duration(seconds: 2), settings.saveQuietly);
    }));
    settings.addListener(applyTuning);
  }

  static final RegExp _fatal = RegExp(
      r'failed to open|failed to recognize|tcp:|http error|server returned|connection (refused|reset|timed out)|'
      r'timed out|no route|not found|forbidden|unauthorized|input/output error|invalid data found|'
      r'end of file|could not open (the )?(stream|file)',
      caseSensitive: false);

  /// Whether an mpv error message means the stream could not be read.
  static bool isFatalError(String message) => _fatal.hasMatch(message);

  NativePlayer? get _native {
    final p = player.platform;
    return p is NativePlayer ? p : null;
  }

  Future<void> setProp(String name, String value) async {
    try {
      await _native?.setProperty(name, value);
    } catch (e) {
      debugPrint('setProperty $name failed: $e');
    }
  }

  Future<String> prop(String name) async {
    try {
      return await _native?.getProperty(name) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> command(List<String> args) async {
    try {
      await _native?.command(args);
    } catch (e) {
      debugPrint('command $args failed: $e');
    }
  }

  /// Applies settings-dependent mpv options. Called at start and whenever
  /// settings change; affects the current and next streams.
  Future<void> applyTuning() async {
    final props = <String, String>{
      'cache': 'yes',
      'cache-on-disk': settings.diskCache ? 'yes' : 'no',
      'demuxer-cache-dir': cacheDir,
      'demuxer-max-bytes': '${settings.cacheMb}MiB',
      'demuxer-max-back-bytes': '${settings.backCacheMb}MiB',
      'demuxer-seekable-cache': 'yes',
      'demuxer-donate-buffer': 'yes',
      'force-seekable': 'yes',
      'network-timeout': '20',
      // FFmpeg HTTP: keep-alive connections (faster seeks out of cache) and
      // automatic reconnection when the IPTV server drops the connection.
      'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
          'reconnect_delay_max=5,multiple_requests=1',
      'demuxer-lavf-o': 'seg_max_retry=5,strict=experimental,allowed_extensions=ALL,'
          'protocol_whitelist=[${_protocols.join(',')}]',
      'hls-bitrate': 'max',
      'tls-verify': 'no',
      'load-unsafe-playlists': 'yes',
      'hwdec': settings.hardwareDecoding ? 'auto-safe' : 'no',
      'vd-lavc-threads': '0',
      'alang': settings.audioLang,
      'slang': settings.subtitleLang,
      // media_kit forces "yes" (always show some subtitle track); keep mpv's
      // standard behaviour: preferred languages, else tracks flagged default.
      'subs-fallback': 'default',
      'audio-normalize-downmix': 'yes',
      'volume-max': '150',
      'sub-font-size': '44',
      'sub-border-size': '2.5',
    };
    for (final e in props.entries) {
      await setProp(e.key, e.value);
    }
    await _applyDeinterlace();
  }

  Future<void> _applyDeinterlace() async {
    final mode = settings.deinterlace;
    if (mode == 'auto') {
      await setProp('deinterlace', 'auto'); // mpv >= 0.38
      _autoDeinterlaceNative = (await prop('deinterlace')) == 'auto';
      if (!_autoDeinterlaceNative) await setProp('deinterlace', 'no');
    } else {
      _autoDeinterlaceNative = false;
      await setProp('deinterlace', mode);
    }
  }

  /// Fallback "auto" deinterlacing for older libmpv builds.
  Future<void> _maybeDeinterlace() async {
    if (settings.deinterlace != 'auto' || _autoDeinterlaceNative) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final interlaced = await prop('video-frame-info/interlaced');
    await setProp('deinterlace', interlaced == 'yes' ? 'yes' : 'no');
  }

  /// Opens [item]. If it is already playing, nothing is reloaded.
  Future<void> play(PlayItem item, {Duration? start, bool force = false}) async {
    await ready;
    if (!force && current.value?.url == item.url && player.state.playlist.medias.isNotEmpty) {
      current.value = item;
      if (!player.state.playing) await player.play();
      return;
    }
    current.value = item;
    status.value = null;
    final ua = item.userAgent;
    await setProp('user-agent', (ua == null || ua.isEmpty) ? 'libmpv' : ua);
    if (item.isLive) {
      // Live: start as soon as possible; data arrives in real time anyway.
      await setProp('cache-secs', '600');
      await setProp('cache-pause-wait', '1');
      await setProp('demuxer-readahead-secs', '2');
    } else {
      // VOD: pre-download far ahead (bounded by the cache size) so seeks are instant.
      await setProp('cache-secs', '36000');
      await setProp('cache-pause-wait', '2');
      await setProp('demuxer-readahead-secs', '60');
    }
    if (!item.isLive) _reconnects = 0;
    await player.open(Media(item.url, start: start), play: true);
  }

  Future<void> stop() async {
    current.value = null;
    status.value = null;
    await player.stop();
  }

  void _onEnded() {
    final item = current.value;
    if (item == null || !item.isLive) return;
    // Live streams should never end: reconnect with a back-off.
    if (_reconnects >= 6) {
      status.value = 'Flux indisponible. Réessaie ou change de chaîne.';
      return;
    }
    _reconnects++;
    _lastReconnect = DateTime.now();
    status.value = 'Reconnexion… ($_reconnects)';
    Timer(Duration(milliseconds: 600 * _reconnects), () {
      if (current.value?.url == item.url) play(item, force: true);
    });
  }

  /// Relative seek handled by mpv (accumulates correctly on key repeat).
  Future<void> seekBy(Duration delta) async {
    final secs = (delta.inMilliseconds / 1000).toStringAsFixed(2);
    final live = current.value?.isLive ?? false;
    await command(['seek', secs, live ? 'relative' : 'relative+exact']);
  }

  /// Returns the cached ranges & cache statistics.
  Future<CacheState> cacheState() async {
    final raw = await prop('demuxer-cache-state');
    if (raw.isEmpty) return const CacheState();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      Duration d(num v) => Duration(milliseconds: (v * 1000).round());
      final ranges = <CachedRange>[
        for (final r in (json['seekable-ranges'] as List? ?? const []))
          if (r is Map && r['start'] is num && r['end'] is num)
            CachedRange(d(r['start'] as num), d(r['end'] as num)),
      ];
      return CacheState(
        ranges: ranges,
        forwardBytes: (json['fw-bytes'] as num?)?.toInt() ?? 0,
        inputRate: (json['raw-input-rate'] as num?)?.toInt() ?? 0,
        cacheEnd: json['cache-end'] is num ? d(json['cache-end'] as num) : null,
      );
    } catch (_) {
      return const CacheState();
    }
  }

  /// Technical information shown in the stats overlay (key "I").
  Future<List<(String, String)>> stats() async {
    Future<String> p(String n) => prop(n);
    final w = await p('video-params/w');
    final h = await p('video-params/h');
    final fps = await p('estimated-vf-fps');
    final cache = await cacheState();
    final cacheDur = double.tryParse(await p('demuxer-cache-duration')) ?? 0;
    final vbr = double.tryParse(await p('video-bitrate')) ?? 0;
    final interlaced = await p('video-frame-info/interlaced');
    return [
      ('Vidéo', (await p('video-codec')).split(' ').first),
      ('Résolution', w.isEmpty ? '—' : '$w×$h${interlaced == 'yes' ? 'i' : 'p'} @ ${double.tryParse(fps)?.toStringAsFixed(2) ?? '?'} i/s'),
      ('Décodage', _hwLabel(await p('hwdec-current'))),
      ('Désentrelacement', await p('deinterlace')),
      ('Audio', await _audioLine(p)),
      ('Conteneur', await p('file-format')),
      ('Débit vidéo', vbr > 0 ? '${(vbr / 1e6).toStringAsFixed(2)} Mb/s' : '—'),
      ('Cache', '${formatDuration(Duration(milliseconds: (cacheDur * 1000).round()))} • ${formatBytes(cache.forwardBytes)}'),
      ('Réseau', cache.inputRate > 0 ? '${formatBytes(cache.inputRate)}/s' : '—'),
      ('Images perdues', '${await p('frame-drop-count')} (décodeur : ${await p('decoder-frame-drop-count')})'),
    ];
  }

  static Future<String> _audioLine(Future<String> Function(String) p) async {
    final codec = await p('audio-codec-name');
    if (codec.isEmpty) return '—';
    final ch = await p('audio-params/channel-count');
    final rate = await p('audio-params/samplerate');
    return [codec, if (ch.isNotEmpty) '$ch canaux', if (rate.isNotEmpty) '$rate Hz'].join(' • ');
  }

  static String _hwLabel(String v) =>
      (v.isEmpty || v == 'no') ? 'Logiciel (CPU)' : 'Matériel ($v)';

  Future<void> dispose() async {
    _watchdog?.cancel();
    settings.removeListener(applyTuning);
    for (final s in _subs) {
      await s.cancel();
    }
    await player.dispose();
  }
}
