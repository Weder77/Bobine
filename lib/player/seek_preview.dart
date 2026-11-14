import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/device.dart';
import '../core/text.dart';
import '../core/theme.dart';
import 'player_service.dart';

/// Whether [url] is a file of this computer (a recording), not a stream.
bool isLocalMedia(String url) =>
    url.startsWith('file://') || !RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(url);

/// Whether the picture shown while hovering the seek bar may be fetched.
///
/// It comes from a second, paused player, so from a second connection to the
/// provider. With a subscription limited to the connections already [inUse]
/// (the film, the recordings in progress), that connection is refused, or
/// worse: the provider closes the film to make room for it. [mode] is the
/// user's setting: 'auto' follows the subscription, 'always' ignores it,
/// 'never' turns the picture off. A file on disk costs nothing.
bool seekPreviewAllowed({required String mode, required bool local, int? maxConnections, int inUse = 1}) {
  if (mode == 'never' || !Device.seekPreview) return false;
  if (local || mode == 'always') return true;
  return maxConnections == null || maxConnections <= 0 || maxConnections > inUse;
}

/// Moves of the pointer smaller than this show the same picture: the preview
/// jumps from key frame to key frame, a few seconds apart.
Duration seekPreviewStep(Duration length) {
  final ms = (length.inMilliseconds / 400).round().clamp(1000, 10000);
  return Duration(milliseconds: ms);
}

/// Makes the jumps of the preview one at a time, the latest one wanted wins.
///
/// The pointer crosses hundreds of positions in a second and a jump over the
/// network takes a few hundred milliseconds: asking for each of them would
/// queue requests long after the pointer stopped.
class PreviewQueue {
  PreviewQueue(this._jump);

  final Future<void> Function(Duration at) _jump;

  /// See [seekPreviewStep].
  Duration step = const Duration(seconds: 1);

  /// A jump is being made: the picture shown is not the one wanted yet.
  final ValueNotifier<bool> busy = ValueNotifier(false);

  Duration? _wanted;
  Duration? _last;
  bool _running = false;

  /// Where the last jump went (the picture shown, or being fetched).
  Duration? get last => _last;

  void want(Duration at) {
    _wanted = at;
    if (!_running) unawaited(_run());
  }

  /// Another film: what was shown says nothing about the next picture.
  void reset() {
    _wanted = null;
    _last = null;
  }

  Future<void> _run() async {
    _running = true;
    try {
      while (true) {
        final next = _wanted;
        _wanted = null;
        if (next == null) break;
        final last = _last;
        if (last != null && (next - last).abs() < step) continue;
        _last = next;
        busy.value = true;
        try {
          await _jump(next);
        } catch (e) {
          debugPrint('seek preview: ${redactCredentials('$e')}');
        }
      }
    } finally {
      _running = false;
      busy.value = false;
    }
  }
}

/// The picture of the instant hovered on the seek bar.
///
/// A second libmpv instance, paused, without sound, that jumps to the key
/// frame nearest to the pointer. It exists only while the bar is hovered:
/// it is opened at the first hover and given back [idle] after the last one,
/// so that a film watched without touching the bar never costs a second
/// connection.
class SeekPreview extends ChangeNotifier {
  SeekPreview({this.idle = const Duration(seconds: 12)}) {
    _queue.busy.addListener(notifyListeners);
  }

  /// Size of the picture on screen.
  static const double width = 240;
  static const double height = 135;

  final Duration idle;
  late final PreviewQueue _queue = PreviewQueue(_jump);

  Player? _player;
  VideoController? _video;
  StreamSubscription<String>? _errors;
  VoidCallback? _unwatch;
  Timer? _idleTimer;

  /// What the pointer is over, and what the player holds.
  PlayItem? _item;
  String? _opened;

  /// A film whose preview could not be opened is not tried again: every
  /// hover would knock at the provider's door.
  String? _refused;
  bool _ready = false;
  bool _disposed = false;

  /// A picture of the film hovered is on screen.
  bool get ready => _ready;

  /// The picture wanted is being fetched.
  bool get busy => _queue.busy.value;

  /// There is something to show above the bar: a picture, or its loading.
  bool get visible => _ready || busy;

  /// The pointer is at [at] on the bar of [item], which lasts [length].
  void hover(PlayItem item, Duration at, Duration length) {
    if (_disposed || _refused == item.url || !item.canOpen) return;
    _idleTimer?.cancel();
    if (_item?.url != item.url) {
      _queue.reset();
      _setReady(false);
    }
    _item = item;
    _queue.step = seekPreviewStep(length);
    _queue.want(at);
  }

  /// The pointer left the bar: the connection is given back after [idle].
  void leave() {
    _idleTimer?.cancel();
    if (_disposed || (_player == null && !busy)) return;
    _idleTimer = Timer(idle, () {
      // Still opening (a slow server): wait for it to finish first.
      if (busy) return leave();
      close();
    });
  }

  /// Gives the connection back now (another film, the TV takes over…).
  void close() {
    _idleTimer?.cancel();
    _item = null;
    _queue.reset();
    unawaited(_drop());
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _queue.busy.removeListener(notifyListeners);
    unawaited(_drop());
    super.dispose();
  }

  /// The picture, to put above the seek bar.
  Widget view() => _PreviewFrame(preview: this);

  void _setReady(bool value) {
    if (_ready == value) return;
    _ready = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> _jump(Duration at) async {
    final item = _item;
    if (_disposed || item == null || _refused == item.url) return;
    if (_opened != item.url) {
      await _drop();
      if (_disposed || _item?.url != item.url) return;
      await _open(item, at);
    } else {
      await _seek(at);
    }
  }

  NativePlayer? get _native {
    final p = _player?.platform;
    return p is NativePlayer ? p : null;
  }

  Future<void> _set(String name, String value) async {
    try {
      await _native?.setProperty(name, value);
    } catch (e) {
      debugPrint('seek preview: $name failed: $e');
    }
  }

  /// What makes this player a cheap one: one picture at a time, no sound, no
  /// reading ahead, key frames only, software decoding (a single frame, and
  /// the graphics card keeps its decoder for the film), scaled down by the
  /// engine itself: a 4K film gives a sharp small picture, not a 4K texture
  /// squeezed into a thumbnail.
  static final Map<String, String> _props = {
    ...PlayerService.networkProps,
    'network-timeout': '10',
    'cache': 'no',
    'cache-on-disk': 'no',
    'demuxer-readahead-secs': '0',
    'demuxer-max-bytes': '8MiB',
    'demuxer-max-back-bytes': '0',
    'hr-seek': 'no',
    'aid': 'no',
    'sid': 'no',
    'sub-auto': 'no',
    'audio-file-auto': 'no',
    'hwdec': 'no',
    'vd-lavc-threads': '2',
    'vd-lavc-skiploopfilter': 'all',
    'vd-lavc-fast': 'yes',
    'vf': 'scale=$_renderWidth:-2',
    'deinterlace': 'no',
    'osd-level': '0',
  };

  Future<void> _open(PlayItem item, Duration at) async {
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Bobine',
        logLevel: MPVLogLevel.error,
        bufferSize: 8 * 1024 * 1024,
        protocolWhitelist: PlayerService.protocols,
      ),
    );
    final video = VideoController(
      player,
      configuration: const VideoControllerConfiguration(hwdec: 'no', enableHardwareAcceleration: true),
    );
    _player = player;
    _video = video;
    _opened = item.url;
    // Shown at once, under the loading sign: on Linux the texture only gets
    // its size (below) once it is on screen.
    notifyListeners();
    final failed = Completer<bool>();
    _errors = player.stream.error.listen((e) {
      debugPrint('seek preview: ${redactCredentials(e)}');
      if (PlayerService.isLoadFailure(e) && !failed.isCompleted) failed.complete(false);
    });
    // The texture is 1 × 1 until the first picture gives it its size: that
    // change is the only sign that there is something to look at.
    final picture = Completer<bool?>();
    void onRect() {
      final r = video.rect.value;
      if (r == null || r.width <= 1 || r.height <= 1) return;
      if (!picture.isCompleted) picture.complete(true);
      // The library sizes the texture from what the decoder outputs, before
      // the scaling asked above, and does so a moment after the first
      // picture: a 4K film would hold a 4K texture for a thumbnail.
      if (r.width > _renderWidth) unawaited(_shrink(video, r));
    }

    video.rect.addListener(onRect);
    _unwatch = () => video.rect.removeListener(onRect);
    for (final e in _props.entries) {
      await _set(e.key, e.value);
    }
    final ua = item.userAgent;
    await _set('user-agent', (ua == null || ua.isEmpty) ? 'libmpv' : ua);
    // true: a picture is there. false: this film gives none (refused, or
    // it cannot jump). null: nothing came in time, to be tried again later.
    bool? shown;
    try {
      await player.setVolume(0);
      await player.open(Media(item.url, start: at), play: false);
      onRect();
      shown = await Future.any<bool?>([picture.future, failed.future])
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      // A stream that cannot jump would show its first picture whatever the
      // pointer is over: no picture is better than a wrong one.
      if (shown == true && await _get('seekable') == 'no') shown = false;
    } catch (e) {
      debugPrint('seek preview: ${redactCredentials('$e')}');
    }
    if (_disposed || _player != player) return;
    if (shown != true) {
      if (shown == false) _refused = item.url;
      await _drop();
      return;
    }
    _setReady(true);
  }

  /// Width of the picture produced (twice the one shown, for sharp screens).
  static const int _renderWidth = 480;

  /// Gives the texture the size of the picture produced. A failure only
  /// leaves it as large as the film.
  Future<void> _shrink(VideoController video, Rect r) async {
    final h = (_renderWidth * r.height / r.width).round();
    try {
      await video.setSize(width: _renderWidth, height: h.isEven ? h : h + 1);
    } catch (e) {
      debugPrint('seek preview: size failed: $e');
    }
  }

  Future<String?> _get(String name) async {
    try {
      return await _native?.getProperty(name);
    } catch (_) {
      return null;
    }
  }

  Future<void> _seek(Duration at) async {
    final native = _native;
    if (native == null) return;
    await native.command(['seek', (at.inMilliseconds / 1000).toStringAsFixed(2), 'absolute+keyframes']);
    // The jump is only queued: wait for its picture, so that the next one
    // asked for is where the pointer is by then. Bounded, a slow server must
    // not hold the queue.
    final end = DateTime.now().add(const Duration(seconds: 4));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (_disposed || _native != native) return;
    } while (await _get('seeking') == 'yes' && DateTime.now().isBefore(end));
  }

  Future<void> _drop() async {
    final player = _player;
    final mounted = _video != null;
    _player = null;
    _video = null;
    _opened = null;
    _ready = false;
    if (!_disposed) notifyListeners();
    _unwatch?.call();
    _unwatch = null;
    await _errors?.cancel();
    _errors = null;
    if (player == null) return;
    // The picture leaves the screen before its player is destroyed.
    if (mounted && !_disposed) {
      await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 300), onTimeout: () {});
    }
    try {
      await player.dispose();
    } catch (e) {
      debugPrint('seek preview: dispose failed: $e');
    }
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.preview});
  final SeekPreview preview;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preview,
    builder: (context, _) {
      final video = preview._video;
      final ready = preview.ready && video != null;
      if (!preview.visible) return const SizedBox.shrink();
      return Container(
        width: SeekPreview.width,
        height: SeekPreview.height,
        clipBehavior: Clip.antiAlias,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null)
              Video(
                // A new player (another film, or after a rest) is another texture.
                key: ObjectKey(video),
                controller: video,
                controls: NoVideoControls,
                fit: BoxFit.contain,
                fill: const Color(0xFF000000),
                wakelock: false,
                pauseUponEnteringBackgroundMode: false,
                subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              ),
            // Another picture is being fetched: said only once it takes long
            // enough for the one shown to mislead (a sign at every move of
            // the pointer would flicker).
            if (ready && preview.busy)
              Positioned(
                top: 8,
                right: 8,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInExpo,
                  builder: (context, v, child) => Opacity(opacity: v, child: child),
                  child: const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFFFFF)),
                  ),
                ),
              ),
            if (!ready)
              const ColoredBox(
                color: Color(0xFF000000),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DarkColors.accent),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
