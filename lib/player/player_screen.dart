import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../core/window.dart';
import '../data/models.dart';
import '../services.dart';
import '../ui/widgets/common.dart';
import 'play_items.dart';
import 'player_service.dart';
import 'player_widgets.dart';

class PlayerSession {
  const PlayerSession({
    required this.item,
    this.start,
    this.channels,
    this.channelIndex = 0,
    this.episodes,
    this.series,
    this.keepAlive = false,
  });

  final PlayItem item;

  /// Resume position.
  final Duration? start;

  /// Live: channels of the current list, for zapping.
  final List<Channel>? channels;
  final int channelIndex;

  /// Series: all episodes, for "next episode".
  final List<Episode>? episodes;
  final Series? series;

  /// Keep the stream running when leaving (live preview continues behind).
  final bool keepAlive;
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.session});
  final PlayerSession session;

  static Future<void> open(BuildContext context, PlayerSession session) {
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, _, _) => PlayerScreen(session: session),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _Aspect {
  auto('Automatique'),
  r169('16:9'),
  r43('4:3'),
  r219('21:9'),
  zoom('Zoom (remplir)'),
  stretch('Étirer');

  const _Aspect(this.label);
  final String label;
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final AppServices _s;
  late final PlayerService _ps;
  late PlayItem _item;
  late int _chIndex;
  Source? _source;

  final _focus = FocusNode(debugLabel: 'player');
  final _position = ValueNotifier<Duration>(Duration.zero);
  final _cache = ValueNotifier<CacheState>(const CacheState());
  final List<StreamSubscription> _subs = [];
  final _panelScroll = ScrollController();

  bool _controls = true;
  bool _menuOpen = false;
  bool _overControls = false;
  bool _fullscreen = false;
  bool _showStats = false;
  bool _channelPanel = false;
  List<(String, String)> _stats = const [];
  String? _osd;
  String? _error;
  String _digits = '';
  _Aspect _aspect = _Aspect.auto;
  double _volumeBeforeMute = 100;
  int? _nextCountdown;

  /// Live: true once the user paused or rewound (time-shift in the cache).
  bool _timeshift = false;

  /// Track ids actually selected by mpv (media_kit only knows manual choices).
  String _aid = '';
  String _sid = '';

  Timer? _hideTimer, _osdTimer, _digitTimer, _tick, _saveTimer, _nextTimer;
  int _tickCount = 0;

  bool get _isLive => _item.isLive;
  List<Channel> get _channels => widget.session.channels ?? const [];
  List<Episode> get _episodes => widget.session.episodes ?? const [];

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _ps = _s.player;
    _item = widget.session.item;
    _chIndex = widget.session.channelIndex;
    _source = _s.repo.source(_item.sourceId);
    _volumeBeforeMute = _ps.player.state.volume > 0 ? _ps.player.state.volume : 100;

    unawaited(_ps.play(_item, start: widget.session.start));
    if (_isLive) _s.repo.touchChannel(_item.sourceId, _item.extId);

    _subs.add(_ps.player.stream.completed.listen((done) {
      if (done) _onCompleted();
    }));
    _subs.add(_ps.player.stream.error.listen((e) {
      if (!mounted || !PlayerService.isFatalError(e)) return;
      if (!_ps.player.state.playing) setState(() => _error = redactCredentials(e));
    }));
    _subs.add(_ps.player.stream.tracks.listen((_) => _refreshSelectedTracks()));
    _subs.add(_ps.player.stream.playing.listen((p) {
      if (p && _error != null && mounted) setState(() => _error = null);
    }));

    // Light-weight UI clock: position 4×/s, cache ranges 1×/s, stats 1×/s.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _saveProgress());

    _fullscreen = AppWindow.fullscreen.value;
    if (!_fullscreen && _s.settings.autoFullscreen) _setFullscreen(true);
    _showControls();
  }

  @override
  void dispose() {
    _saveProgress(notify: true);
    for (final t in [_hideTimer, _osdTimer, _digitTimer, _tick, _saveTimer, _nextTimer]) {
      t?.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    // Deferred: these notify listeners, which must not happen while the
    // widget tree is being unmounted.
    final ps = _ps;
    final keepAlive = widget.session.keepAlive;
    final wasFullscreen = _fullscreen;
    scheduleMicrotask(() {
      if (wasFullscreen) AppWindow.setFullscreen(false);
      if (!keepAlive) ps.stop();
    });
    _focus.dispose();
    _position.dispose();
    _cache.dispose();
    _panelScroll.dispose();
    super.dispose();
  }

  Future<void> _onTick() async {
    if (!mounted) return;
    _tickCount++;
    if (_controls || _showStats) _position.value = _ps.player.state.position;
    if (_tickCount % 4 == 0) {
      if (_controls || _showStats) _cache.value = await _ps.cacheState();
      if (_showStats) {
        final st = await _ps.stats();
        if (mounted) setState(() => _stats = st);
      }
    }
  }

  Future<void> _refreshSelectedTracks() async {
    final a = await _ps.prop('current-tracks/audio/id');
    final s = await _ps.prop('current-tracks/sub/id');
    if (!mounted) return;
    setState(() {
      _aid = a;
      _sid = s;
    });
  }

  Future<void> _selectAudio(AudioTrack t) async {
    await _ps.player.setAudioTrack(t);
    await _refreshSelectedTracks();
  }

  Future<void> _selectSubtitle(SubtitleTrack t) async {
    await _ps.player.setSubtitleTrack(t);
    await _refreshSelectedTracks();
  }

  // ------------------------------------------------------------ progress

  void _saveProgress({bool notify = false}) {
    if (_isLive) return;
    final pos = _ps.player.state.position;
    final dur = _ps.player.state.duration;
    if (dur.inSeconds <= 0 || pos.inSeconds < 5) return;
    _s.repo.saveProgress(
      sourceId: _item.sourceId,
      kind: _item.kind,
      extId: _item.extId,
      position: pos,
      duration: dur,
      title: _item.title,
      subtitle: _item.subtitle,
      image: _item.image,
      seriesExt: _item.seriesExt,
    );
    // Called from dispose(): listeners must not rebuild while the tree is
    // being unmounted, so the notification is deferred to the next frame.
    if (notify) {
      final library = _s.library;
      WidgetsBinding.instance.addPostFrameCallback((_) => library.userChanged());
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _onCompleted() {
    if (!mounted || _isLive) return;
    final dur = _ps.player.state.duration;
    if (dur.inSeconds > 0) {
      _s.repo.saveProgress(
        sourceId: _item.sourceId, kind: _item.kind, extId: _item.extId,
        position: dur, duration: dur, title: _item.title, subtitle: _item.subtitle,
        image: _item.image, seriesExt: _item.seriesExt,
      );
    }
    if (_nextEpisode != null && _s.settings.autoNextEpisode) {
      setState(() => _nextCountdown = 8);
      _nextTimer?.cancel();
      _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        if (_nextCountdown == null) return t.cancel();
        if (_nextCountdown! <= 1) {
          t.cancel();
          _playNextEpisode();
        } else {
          setState(() => _nextCountdown = _nextCountdown! - 1);
        }
      });
    } else {
      _showControls(sticky: true);
    }
  }

  // ------------------------------------------------------------ controls

  void _showControls({bool sticky = false}) {
    if (!_controls) setState(() => _controls = true);
    _hideTimer?.cancel();
    if (sticky) return;
    _hideTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted || _menuOpen || _overControls || _channelPanel) return;
      if (!_ps.player.state.playing) return;
      setState(() => _controls = false);
    });
  }

  void _flash(String message) {
    _osdTimer?.cancel();
    setState(() => _osd = message);
    _osdTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _osd = null);
    });
  }

  Future<void> _setFullscreen(bool value) async {
    await AppWindow.setFullscreen(value);
    if (mounted) setState(() => _fullscreen = value);
  }

  void _togglePlay() {
    if (_isLive && _ps.player.state.playing) _timeshift = true;
    _ps.player.playOrPause();
    _showControls();
  }

  void _seekBy(int seconds) {
    if (_isLive && seconds < 0) _timeshift = true;
    _ps.seekBy(Duration(seconds: seconds));
    _flash(seconds > 0 ? '+$seconds s' : '$seconds s');
    _showControls();
  }

  void _changeVolume(double delta) {
    final v = (_ps.player.state.volume + delta).clamp(0.0, 150.0);
    _ps.player.setVolume(v);
    _flash('Volume ${v.round()} %');
  }

  void _toggleMute() {
    final v = _ps.player.state.volume;
    if (v > 0) {
      _volumeBeforeMute = v;
      _ps.player.setVolume(0);
      _flash('Muet');
    } else {
      _ps.player.setVolume(_volumeBeforeMute);
      _flash('Volume ${_volumeBeforeMute.round()} %');
    }
  }

  void _cycleAudio() {
    final tracks = _ps.player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (tracks.length < 2) return _flash('Une seule piste audio');
    final i = tracks.indexWhere((t) => t.id == _aid);
    final next = tracks[(i + 1) % tracks.length];
    _selectAudio(next);
    _flash('Audio : ${audioTrackLabel(next, tracks.indexOf(next))}');
  }

  void _cycleSubtitles() {
    final tracks = [
      SubtitleTrack.no(),
      ..._ps.player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no'),
    ];
    if (tracks.length < 2) return _flash('Aucun sous-titre');
    var i = tracks.indexWhere((t) => t.id == _sid);
    if (i < 0) i = 0; // none selected = "Désactivés"
    final next = tracks[(i + 1) % tracks.length];
    _selectSubtitle(next);
    _flash('Sous-titres : ${subtitleTrackLabel(next, tracks.indexOf(next) - 1)}');
  }

  void _cycleAspect() {
    final next = _Aspect.values[(_aspect.index + 1) % _Aspect.values.length];
    setState(() => _aspect = next);
    _flash('Format : ${next.label}');
  }

  // ---------------------------------------------------------------- live

  Channel? get _currentChannel {
    if (!_isLive) return null;
    if (_channels.isNotEmpty && _chIndex < _channels.length && _channels[_chIndex].extId == _item.extId) {
      return _channels[_chIndex];
    }
    return _s.repo.channelByExt(_item.sourceId, _item.extId);
  }

  void _zap(int delta) {
    if (_channels.isEmpty || _source == null) return;
    _playChannel((_chIndex + delta) % _channels.length);
  }

  void _playChannel(int index) {
    if (_source == null || index < 0 || index >= _channels.length) return;
    final c = _channels[index];
    setState(() {
      _chIndex = index;
      _item = channelItem(_source!, c);
      _error = null;
      _timeshift = false;
    });
    _ps.play(_item);
    _s.repo.touchChannel(c.sourceId, c.extId);
    _flash('${c.number ?? index + 1}  ${c.name}');
    _showControls();
  }

  void _typeDigit(String d) {
    _digitTimer?.cancel();
    setState(() => _digits = (_digits + d).substring(_digits.length >= 4 ? 1 : 0));
    _digitTimer = Timer(const Duration(milliseconds: 1400), () {
      final n = int.tryParse(_digits);
      setState(() => _digits = '');
      if (n == null || _channels.isEmpty) return;
      var idx = _channels.indexWhere((c) => c.number == n);
      if (idx < 0 && n >= 1 && n <= _channels.length) idx = n - 1;
      if (idx >= 0) {
        _playChannel(idx);
      } else {
        _flash('Chaîne $n introuvable');
      }
    });
  }

  void _toggleChannelPanel() {
    if (!_isLive || _channels.isEmpty) return;
    setState(() => _channelPanel = !_channelPanel);
    if (_channelPanel) {
      _showControls(sticky: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_panelScroll.hasClients) {
          _panelScroll.jumpTo((_chIndex * 60.0 - 200)
              .clamp(0.0, _panelScroll.position.maxScrollExtent));
        }
      });
    } else {
      _showControls();
    }
  }

  // -------------------------------------------------------------- series

  int get _episodeIndex => _episodes.indexWhere((e) => e.extId == _item.extId);

  Episode? get _nextEpisode {
    final i = _episodeIndex;
    return (i >= 0 && i + 1 < _episodes.length) ? _episodes[i + 1] : null;
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (next == null || _source == null) return;
    _nextTimer?.cancel();
    _saveProgress();
    final p = _s.repo.progress(_item.sourceId, ContentKind.episode, next.extId);
    setState(() {
      _nextCountdown = null;
      _item = episodeItem(_source!, widget.session.series, next);
    });
    _ps.play(_item, start: (p != null && p.resumable) ? p.position : null, force: true);
    _flash(next.code);
  }

  // ------------------------------------------------------------ keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final step = _s.settings.seekStep * (shift ? 6 : 1);
    final repeat = e is KeyRepeatEvent;

    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      if (!repeat) _togglePlay();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyJ) {
      _seekBy(-step);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyL) {
      _seekBy(step);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _isLive && _channels.isNotEmpty ? (!repeat ? _zap(-1) : null) : _changeVolume(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _isLive && _channels.isNotEmpty ? (!repeat ? _zap(1) : null) : _changeVolume(-5);
    } else if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.channelUp) {
      if (!repeat) _zap(-1);
    } else if (k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.channelDown) {
      if (!repeat) _zap(1);
    } else if (k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd) {
      _changeVolume(5);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      _changeVolume(-5);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      if (!repeat) _setFullscreen(!_fullscreen);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_channelPanel) {
        _toggleChannelPanel();
      } else if (_fullscreen) {
        _setFullscreen(false);
      } else {
        Navigator.of(context).maybePop();
      }
    } else if (k == LogicalKeyboardKey.backspace) {
      Navigator.of(context).maybePop();
    } else if (k == LogicalKeyboardKey.keyM) {
      if (!repeat) _toggleMute();
    } else if (k == LogicalKeyboardKey.keyI) {
      if (!repeat) setState(() => _showStats = !_showStats);
    } else if (k == LogicalKeyboardKey.keyA) {
      if (!repeat) _cycleAudio();
    } else if (k == LogicalKeyboardKey.keyS) {
      if (!repeat) _cycleSubtitles();
    } else if (k == LogicalKeyboardKey.keyR) {
      if (!repeat) _cycleAspect();
    } else if (k == LogicalKeyboardKey.keyC) {
      if (!repeat) _toggleChannelPanel();
    } else if (k == LogicalKeyboardKey.keyN) {
      if (!repeat) _playNextEpisode();
    } else if (k == LogicalKeyboardKey.home && !_isLive) {
      _ps.player.seek(Duration.zero);
    } else if (_isLive && _digitOf(k) != null) {
      _typeDigit(_digitOf(k)!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String? _digitOf(LogicalKeyboardKey k) {
    const digits = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    var i = digits.indexOf(k);
    if (i < 0) i = numpad.indexOf(k);
    return i < 0 ? null : '$i';
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final (fit, ratio) = switch (_aspect) {
      _Aspect.auto => (BoxFit.contain, null),
      _Aspect.r169 => (BoxFit.contain, 16 / 9),
      _Aspect.r43 => (BoxFit.contain, 4 / 3),
      _Aspect.r219 => (BoxFit.contain, 2.39),
      _Aspect.zoom => (BoxFit.cover, null),
      _Aspect.stretch => (BoxFit.fill, null),
    };
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && !_channelPanel) {
              _changeVolume(e.scrollDelta.dy < 0 ? 5 : -5);
            }
          },
          child: MouseRegion(
            cursor: _controls ? SystemMouseCursors.basic : SystemMouseCursors.none,
            onHover: (_) => _showControls(),
            child: Stack(fit: StackFit.expand, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _focus.requestFocus();
                  if (_channelPanel) return _toggleChannelPanel();
                  _isLive ? _showControls() : _togglePlay();
                },
                onDoubleTap: () => _setFullscreen(!_fullscreen),
                child: Video(
                  key: ValueKey(_aspect),
                  controller: _ps.video,
                  controls: NoVideoControls,
                  fit: fit,
                  aspectRatio: ratio,
                  fill: Colors.black,
                  filterQuality: FilterQuality.medium,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                ),
              ),
              _buildBuffering(),
              if (_osd != null) _buildOsd(),
              if (_digits.isNotEmpty) _buildDigits(),
              _buildError(),
              if (_showStats) _buildStats(),
              _buildControls(),
              if (_isLive) _buildChannelPanel(),
              if (_nextCountdown != null) _buildNextCard(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildBuffering() {
    return IgnorePointer(
      child: StreamBuilder<bool>(
        stream: _ps.player.stream.buffering,
        initialData: _ps.player.state.buffering,
        builder: (context, snap) {
          if (snap.data != true) return const SizedBox.shrink();
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent),
              ),
              const SizedBox(height: 14),
              StreamBuilder<double>(
                stream: _ps.player.stream.bufferingPercentage,
                builder: (context, p) => Text(
                  p.hasData && p.data! > 0 ? 'Mise en mémoire… ${p.data!.round()} %' : 'Chargement…',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildOsd() => IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.55),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_osd!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _buildDigits() => Positioned(
        top: 40,
        right: 48,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent),
          ),
          child: Text(_digits,
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: AppColors.accent)),
        ),
      );

  Widget _buildError() {
    return ValueListenableBuilder<String?>(
      valueListenable: _ps.status,
      builder: (context, status, _) {
        final message = status ?? _error;
        if (message == null) return const SizedBox.shrink();
        final reconnecting = status != null && status.startsWith('Reconnexion');
        return Align(
          alignment: const Alignment(0, 0.35),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(reconnecting ? Icons.wifi_tethering : Icons.error_outline,
                  color: reconnecting ? AppColors.accent : AppColors.live, size: 30),
              const SizedBox(height: 10),
              Text(reconnecting ? message : 'Lecture impossible',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              if (!reconnecting) ...[
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _error = null);
                    _ps.status.value = null;
                    _ps.play(_item, force: true, start: _isLive ? null : _ps.player.state.position);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _buildStats() => Positioned(
        top: 24,
        left: 24,
        child: IgnorePointer(
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Statistiques (I)',
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
              const SizedBox(height: 8),
              for (final (k, v) in _stats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 130,
                        child: Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                    Expanded(
                        child: Text(v.isEmpty ? '—' : v,
                            style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]))),
                  ]),
                ),
            ]),
          ),
        ),
      );

  Widget _buildControls() {
    return IgnorePointer(
      ignoring: !_controls,
      child: AnimatedOpacity(
        opacity: _controls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Stack(children: [
          // Top bar
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 24, 40),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xCC000000), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(children: [
                OverlayButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Retour (Échap)',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (_item.subtitle != null)
                      Text(_item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
          ),
          // Bottom bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => _overControls = true,
              onExit: (_) {
                _overControls = false;
                _showControls();
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Color(0xE6000000)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: _isLive ? _liveBar() : _vodBar(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _playButton({bool big = false}) => StreamBuilder<bool>(
        stream: _ps.player.stream.playing,
        initialData: _ps.player.state.playing,
        builder: (context, snap) => OverlayButton(
          big: big,
          icon: snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: snap.data == true ? 'Pause (Espace)' : 'Lecture (Espace)',
          onPressed: _togglePlay,
        ),
      );

  Widget _vodBar() {
    final step = _s.settings.seekStep;
    final next = _nextEpisode;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ValueListenableBuilder<Duration>(
        valueListenable: _position,
        builder: (context, pos, _) => ValueListenableBuilder<CacheState>(
          valueListenable: _cache,
          builder: (context, cache, _) {
            final dur = _ps.player.state.duration;
            return Column(children: [
              SeekBar(
                position: pos,
                duration: dur,
                ranges: cache.ranges,
                onInteraction: _showControls,
                onSeek: (d) {
                  _ps.player.seek(d);
                  _position.value = d;
                },
              ),
              Row(children: [
                Text(formatDuration(pos, forceHours: dur.inHours > 0),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 12),
                if (cache.cacheEnd != null && cache.cacheEnd! > pos)
                  Tooltip(
                    message: 'Déjà téléchargé devant la lecture : avancer dans cette zone est instantané',
                    child: Pill('Cache +${formatDuration(cache.cacheEnd! - pos)}',
                        icon: Icons.bolt, color: Colors.white12, textColor: Colors.white70),
                  ),
                const Spacer(),
                Text('-${formatDuration(dur - pos, forceHours: dur.inHours > 0)}  /  ${formatDuration(dur)}',
                    style: const TextStyle(color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ]);
          },
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        _playButton(big: true),
        const SizedBox(width: 8),
        OverlayButton(icon: Icons.replay_10_rounded, tooltip: '-$step s (←)', onPressed: () => _seekBy(-step)),
        OverlayButton(icon: Icons.forward_10_rounded, tooltip: '+$step s (→)', onPressed: () => _seekBy(step)),
        if (next != null)
          OverlayButton(icon: Icons.skip_next_rounded, tooltip: 'Épisode suivant (N)', onPressed: _playNextEpisode),
        const SizedBox(width: 8),
        _volume(),
        const Spacer(),
        ..._trackMenus(withSpeed: true),
      ]),
    ]);
  }

  Widget _liveBar() {
    final ch = _currentChannel;
    final now = ch == null ? null : _s.epg.now(ch);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        ChannelLogo(name: _item.title, url: _item.image, size: 56),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (ch?.number != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text('${ch!.number}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.accent)),
                ),
              Flexible(
                child: Text(_item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              _liveStatus(),
            ]),
            const SizedBox(height: 4),
            if (now != null) ...[
              Text('${formatClock(now.start)} – ${formatClock(now.stop)}  ${now.title}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 6),
              SizedBox(width: 360, child: ProgressLine(now.progressAt(DateTime.now()))),
            ] else
              const Text('Pas de programme disponible', style: TextStyle(color: Colors.white54)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _playButton(big: true),
        const SizedBox(width: 8),
        if (_channels.isNotEmpty) ...[
          OverlayButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: 'Chaîne précédente (↑)', onPressed: () => _zap(-1)),
          OverlayButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Chaîne suivante (↓)', onPressed: () => _zap(1)),
          OverlayButton(icon: Icons.list_rounded, tooltip: 'Liste des chaînes (C)', onPressed: _toggleChannelPanel),
        ],
        const SizedBox(width: 8),
        _volume(),
        const Spacer(),
        ..._trackMenus(withSpeed: false),
      ]),
    ]);
  }

  /// "EN DIRECT" or "Retour au direct" when the user rewound in the cache.
  Widget _liveStatus() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _position,
      builder: (context, pos, _) => ValueListenableBuilder<CacheState>(
        valueListenable: _cache,
        builder: (context, cache, _) {
          final end = cache.cacheEnd;
          final behind = end == null ? Duration.zero : end - pos;
          if (!_timeshift || (behind.inSeconds < 20 && _ps.player.state.playing)) {
            return const LiveBadge();
          }
          return Material(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                if (end != null) _ps.player.seek(end - const Duration(seconds: 2));
                if (!_ps.player.state.playing) _ps.player.play();
                setState(() => _timeshift = false);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  behind.inSeconds >= 20 ? 'Retour au direct (-${formatDuration(behind)})' : 'Retour au direct',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _volume() {
    return StreamBuilder<double>(
      stream: _ps.player.stream.volume,
      initialData: _ps.player.state.volume,
      builder: (context, snap) {
        final v = snap.data ?? 100;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          OverlayButton(
            icon: v == 0 ? Icons.volume_off_rounded : (v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
            tooltip: 'Muet (M)',
            onPressed: _toggleMute,
          ),
          SizedBox(
            width: 110,
            child: Slider(
              value: v.clamp(0, 150),
              max: 150,
              onChanged: (x) {
                _ps.player.setVolume(x);
                _showControls();
              },
            ),
          ),
        ]);
      },
    );
  }

  List<Widget> _trackMenus({required bool withSpeed}) {
    final player = _ps.player;
    void opened() {
      _menuOpen = true;
      _showControls(sticky: true);
    }

    void closed() {
      _menuOpen = false;
      _showControls();
      _focus.requestFocus();
    }

    return [
      ChoiceMenu<AudioTrack>(
        icon: Icons.audiotrack_rounded,
        tooltip: 'Piste audio (A)',
        onOpened: opened,
        onClosed: closed,
        items: () {
          final list = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
          return [
            for (var i = 0; i < list.length; i++)
              (list[i], audioTrackLabel(list[i], i), list[i].id == _aid),
          ];
        },
        onSelected: _selectAudio,
      ),
      ChoiceMenu<SubtitleTrack>(
        icon: Icons.subtitles_rounded,
        tooltip: 'Sous-titres (S)',
        onOpened: opened,
        onClosed: closed,
        items: () {
          final list = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final none = !list.any((t) => t.id == _sid);
          return [
            (SubtitleTrack.no(), 'Désactivés', none),
            for (var i = 0; i < list.length; i++)
              (list[i], subtitleTrackLabel(list[i], i), list[i].id == _sid),
          ];
        },
        onSelected: _selectSubtitle,
      ),
      if (withSpeed)
        ChoiceMenu<double>(
          icon: Icons.speed_rounded,
          tooltip: 'Vitesse',
          onOpened: opened,
          onClosed: closed,
          items: () => [
            for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              (r, r == 1.0 ? 'Normale' : '×$r', (player.state.rate - r).abs() < 0.01),
          ],
          onSelected: player.setRate,
        ),
      ChoiceMenu<_Aspect>(
        icon: Icons.aspect_ratio_rounded,
        tooltip: "Format d'image (R)",
        onOpened: opened,
        onClosed: closed,
        items: () => [for (final a in _Aspect.values) (a, a.label, a == _aspect)],
        onSelected: (a) => setState(() => _aspect = a),
      ),
      OverlayButton(
        icon: Icons.insights_rounded,
        tooltip: 'Statistiques (I)',
        onPressed: () => setState(() => _showStats = !_showStats),
      ),
      OverlayButton(
        icon: _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        tooltip: 'Plein écran (F)',
        onPressed: () => _setFullscreen(!_fullscreen),
      ),
    ];
  }

  Widget _buildChannelPanel() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      top: 0,
      bottom: 0,
      right: _channelPanel ? 0 : -380,
      width: 360,
      child: Material(
        color: const Color(0xF20A0C11),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
            child: Row(children: [
              const Expanded(
                child: Text('Chaînes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: _toggleChannelPanel, icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: _channelPanel
                ? ListView.builder(
                    controller: _panelScroll,
                    itemExtent: 60,
                    itemCount: _channels.length,
                    itemBuilder: (context, i) {
                      final c = _channels[i];
                      final sel = i == _chIndex;
                      final now = _s.epg.now(c);
                      return InkWell(
                        onTap: () => _playChannel(i),
                        child: Container(
                          color: sel ? AppColors.accent.withValues(alpha: 0.15) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(children: [
                            SizedBox(
                              width: 34,
                              child: Text('${c.number ?? i + 1}',
                                  style: TextStyle(
                                      color: sel ? AppColors.accent : AppColors.faint,
                                      fontWeight: FontWeight.w700)),
                            ),
                            ChannelLogo(name: c.name, url: c.logo, size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: sel ? AppColors.accent : AppColors.text)),
                                  if (now != null)
                                    Text(now.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }

  Widget _buildNextCard() {
    final next = _nextEpisode;
    if (next == null) return const SizedBox.shrink();
    return Positioned(
      right: 32,
      bottom: 140,
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Épisode suivant dans $_nextCountdown s',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text('${next.code} · ${next.displayTitle}',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(
              onPressed: _playNextEpisode,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Lancer'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _nextTimer?.cancel();
                setState(() => _nextCountdown = null);
              },
              child: const Text('Annuler'),
            ),
          ]),
        ]),
      ),
    );
  }
}
