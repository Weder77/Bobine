import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../cast/cast_device.dart';
import '../cast/cast_service.dart';
import '../cast/cast_session.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../core/window.dart';
import '../data/models.dart';
import '../features/tmdb.dart';
import '../services.dart';
import '../ui/multi_view_screen.dart';
import '../ui/widgets/common.dart';
import 'cast_view.dart';
import 'play_items.dart';
import 'player_chrome.dart';
import 'player_session.dart';
import 'player_service.dart';
import 'player_widgets.dart';
import 'seek_preview.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.session});
  final PlayerSession session;

  /// Name of the routes that play something (this screen and the
  /// multi-view): at most one of them is on screen.
  static const playbackRoute = 'playback';

  /// Opens the player. With [replacing], it takes the place of a player or
  /// multi-view already open (a reminder's "Regarder" over a film): stacked,
  /// they would share one video engine, and leaving the top one would stop
  /// it under the other.
  /// Players opened so far: a launch that waited for the network can tell
  /// whether another one started meanwhile.
  static int opened = 0;

  static Future<void> open(BuildContext context, PlayerSession session, {bool replacing = false}) {
    opened++;
    final nav = Navigator.of(context);
    if (!replacing) return nav.push(route(session));
    // Told before the new screen is built: it must not count itself replaced.
    AppScope.of(context).player.takeOver();
    return nav.pushAndRemoveUntil(route(session), (r) => r.settings.name != playbackRoute);
  }

  static Route<void> route(PlayerSession session) => PageRouteBuilder(
    settings: const RouteSettings(name: playbackRoute),
    opaque: true,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) => PlayerScreen(session: session),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _Aspect {
  auto('Automatique', 'Auto'),
  r169('16:9', '16:9'),
  r43('4:3', '4:3'),
  r219('21:9', '21:9'),
  zoom('Zoom (remplir)', 'Remplir'),
  stretch('Étirer', 'Étirer');

  const _Aspect(this.label, this.short);
  final String label;
  final String short;
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final AppServices _s;
  late final PlayerService _ps;
  late final CastService _cast;
  late PlayItem _item;
  late int _chIndex;
  Source? _source;

  final _focus = FocusNode(debugLabel: 'player');
  final _position = ValueNotifier<Duration>(Duration.zero);
  final _cache = ValueNotifier<CacheState>(const CacheState());
  final _decoder = ValueNotifier<String?>(null);
  final List<StreamSubscription> _subs = [];
  final _panelScroll = ScrollController();

  bool _controls = true;
  bool _playing = true;

  /// Panel open over the video.
  _Panel _panel = _Panel.none;
  bool _overControls = false;
  bool _fullscreen = false;
  bool _showStats = false;

  /// Episode whose "Épisode suivant" card was dismissed.
  String? _nextDismissed;

  /// Season shown in the "Épisodes" panel.
  int? _panelSeason;

  /// Streams of the live channel in other qualities (lazy).
  List<Channel>? _variants;
  List<(String, String)> _stats = const [];
  String? _osd;
  String? _error;

  /// The picture shown while hovering the seek bar (a second, paused player
  /// that only exists while the bar is hovered).
  final SeekPreview _preview = SeekPreview();

  /// Where playback was when [_error] was raised.
  Duration _errorAt = Duration.zero;

  /// [PlayerService.takeovers] when this screen opened.
  int _takeovers = 0;
  String _digits = '';
  _Aspect _aspect = _Aspect.auto;
  double _volumeBeforeMute = 100;

  /// Live: true once the user paused or rewound (time-shift in the cache).
  bool _timeshift = false;

  /// Track ids actually selected by mpv (media_kit only knows manual choices).
  String _aid = '';
  String _sid = '';

  Timer? _hideTimer, _osdTimer, _digitTimer, _tick;

  /// Shrunk into the mini-player / floating window: playback goes on.
  bool _minimized = false;
  int _tickCount = 0;

  /// Ends on the TV already handled ([CastService.endedCount]).
  int _castEnded = 0;

  bool get _isLive => _item.isLive;

  /// The TV plays the stream; the controls drive it.
  bool get _casting => _cast.active;

  /// Position and length of what plays, here or on the TV.
  Duration get _pos => _casting ? _cast.position : _ps.player.state.position;
  Duration get _dur => _casting ? (_cast.duration ?? Duration.zero) : _ps.player.state.duration;
  List<Channel> get _channels => widget.session.channels ?? const [];
  List<Episode> get _episodes => widget.session.episodes ?? const [];

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _ps = _s.player;
    _takeovers = _ps.takeovers;
    _cast = _s.cast;
    _castEnded = _cast.endedCount;
    _item = widget.session.item;
    _chIndex = widget.session.channelIndex;
    _source = _s.repo.source(_item.sourceId);
    _volumeBeforeMute = _ps.player.state.volume > 0 ? _ps.player.state.volume : 100;

    // This screen now shows the video: no mini-player at the same time.
    // Deferred: the mini-player listens to this and is being built too.
    if (_s.pip.active) scheduleMicrotask(_s.pip.release);
    if (_casting) {
      // Something else chosen while casting goes to the TV too.
      // Deferred: the mini-player listens to the cast and is being built too.
      if (_cast.item.value?.url != _item.url) scheduleMicrotask(() => _cast.load(_item, start: widget.session.start));
    } else {
      unawaited(_ps.play(_item, start: widget.session.start));
    }
    if (_isLive) _s.repo.touchChannel(_item.sourceId, _item.extId);
    _cast.addListener(_onCast);
    _subs.add(
      _cast.messages.listen((m) {
        if (mounted) _flash(m);
      }),
    );

    _subs.add(
      _ps.player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
    );
    _subs.add(
      _ps.player.stream.error.listen((e) {
        if (!mounted) return;
        final state = _ps.player.state;
        if (!PlayerService.stopsPlayback(e, live: _isLive, playing: state.playing, duration: state.duration)) return;
        setState(() {
          _error = redactCredentials(e);
          _errorAt = state.position;
        });
      }),
    );
    _subs.add(_ps.player.stream.tracks.listen((_) => _refreshSelectedTracks()));
    _subs.add(
      _ps.player.stream.playing.listen((p) {
        if (!mounted) return;
        // The error stays until pictures really come (see _onTick): play /
        // pause on a dead link took the error card and "Réessayer" away,
        // leaving a black screen.
        setState(() => _playing = p);
      }),
    );
    // Playback is starting: no pause screen while it loads. Unless this is
    // the mini-player growing back on a film that ended in it: it stays on
    // its last picture, controls shown, as when it ends here.
    final ended = !_casting && !_isLive && _ps.current.value?.url == _item.url && _ps.player.state.completed;
    _playing = !ended;
    unawaited(_ps.setProp('sub-scale', '${_s.settings.subtitleScale}'));

    // Light-weight UI clock: position 4×/s, cache ranges 1×/s, stats 1×/s.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());

    _fullscreen = AppWindow.fullscreen.value;
    if (!_fullscreen && _s.settings.autoFullscreen) _setFullscreen(true);
    _showControls(sticky: ended);
  }

  @override
  void dispose() {
    _cast.removeListener(_onCast);
    _s.tracker.flush();
    for (final t in [_hideTimer, _osdTimer, _digitTimer, _tick, _zapTimer]) {
      t?.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    // Deferred: these notify listeners, which must not happen while the
    // widget tree is being unmounted.
    final ps = _ps;
    final keepAlive = widget.session.keepAlive || _minimized || _casting;
    final wasFullscreen = _fullscreen;
    // Another player took this one's place: the engine and the window are
    // its own now, whatever it plays (the same channel, for a reminder
    // about the channel being watched).
    final replaced = ps.takeovers != _takeovers;
    final generation = ps.generation;
    scheduleMicrotask(() {
      if (wasFullscreen && !replaced) AppWindow.setFullscreen(false);
      // Something opened meanwhile (the screen that follows): its stream is
      // not cut by this one's late stop.
      if (!keepAlive && !replaced && ps.generation == generation) ps.stop();
    });
    _preview.dispose();
    _focus.dispose();
    _position.dispose();
    _cache.dispose();
    _decoder.dispose();
    _panelScroll.dispose();
    super.dispose();
  }

  /// Whether the instant hovered on the bar can be shown as a picture. Not a
  /// replay: those streams are made on demand and cannot jump.
  bool get _canPreview {
    if (_isLive || _item.isReplay || _casting || _item.url.isEmpty) return false;
    return seekPreviewAllowed(
      mode: _s.settings.seekPreview,
      local: isLocalMedia(_item.url),
      maxConnections: int.tryParse('${_source?.accountInfo?['max_connections'] ?? ''}'),
      inUse: 1 + _s.recordings.activeCount.value,
    );
  }

  void _onSeekPoint(Duration? at) {
    if (at == null || !_canPreview || _dur <= Duration.zero) return _preview.leave();
    _preview.hover(_item, at, _dur);
  }

  Future<void> _onTick() async {
    if (!mounted) return;
    _tickCount++;
    // It plays after all (the engine got through on a later attempt): an
    // error that stayed on top of a running film would be a lie.
    final engine = _ps.player.state;
    if (_error != null &&
        !_casting &&
        engine.playing &&
        !engine.buffering &&
        engine.position > _errorAt + const Duration(seconds: 1)) {
      setState(() => _error = null);
    }
    if (_controls || _showStats || _casting || _item.kind == ContentKind.episode) _position.value = _pos;
    if (_tickCount % 4 == 0 && !_casting) {
      if (_controls || _showStats) _cache.value = await _ps.cacheState();
      if (_controls && (_decoder.value == null || _tickCount % 40 == 0)) {
        final d = await _ps.decoderSummary();
        if (mounted) _decoder.value = d;
      }
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

  /// Keeps playing in the mini-player ([floating]: in a small window above
  /// the other apps, Windows only) and goes back to browsing.
  Future<void> _minimize({bool floating = false}) async {
    if (_minimized) return;
    final session = widget.session.copyWith(item: _item, channelIndex: _chIndex, clearStart: true);
    _minimized = true;
    _s.tracker.flush();
    if (floating) {
      await _s.pip.float(session);
    } else {
      _s.pip.show(session);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  // ----------------------------------------------------------------- cast

  void _onCast() {
    if (!mounted) return;
    if (_cast.endedCount != _castEnded) {
      _castEnded = _cast.endedCount;
      if (_casting) _onCompleted();
    }
    setState(() {});
  }

  /// Sends what plays to [d]; the local player stops (one connection).
  Future<void> _castTo(CastDevice d) async {
    setState(() => _panel = _Panel.none);
    if (_casting && _cast.device == d) return;
    Duration? from;
    if (!_isLive) {
      final here = _casting ? _cast.position : _ps.player.state.position;
      // The session's start is that of the title it opened with, not of the
      // next episode played since.
      final resume = _item.url == widget.session.item.url ? widget.session.start : null;
      from = here > Duration.zero ? here : resume;
    }
    _s.tracker.flush();
    // The TV takes the connection: the preview gives its own back.
    _preview.close();
    setState(() {
      _error = null;
      _timeshift = false;
      _showStats = false;
    });
    // The TV first, so that "Reprendre" follows the same item.
    unawaited(_cast.start(d, _item, start: from));
    await _ps.stop();
    _showControls(sticky: true);
  }

  /// Stops casting and plays here again, where the TV was.
  Future<void> _stopCasting() async {
    if (_panel == _Panel.cast) setState(() => _panel = _Panel.none);
    final at = await _cast.stop();
    if (!mounted) return;
    setState(() => _error = null);
    _focus.requestFocus();
    await _ps.play(_item, start: _isLive ? null : at, force: true);
    _showControls();
  }

  /// Opens [item] where playback happens (here or on the TV).
  void _open(PlayItem item, {Duration? start, bool force = false}) {
    if (_casting) {
      unawaited(_cast.load(item, start: start));
    } else {
      unawaited(_ps.play(item, start: start, force: force));
    }
  }

  /// Back: leaving while casting keeps the TV playing (mini-player).
  void _leave() {
    if (_casting) {
      _minimize();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _onCompleted() {
    if (!mounted || _isLive) return;
    // Cut by the network: the service opens it again where it stopped.
    if (!_casting && _ps.cutShort) return;
    _s.tracker.markFinished(_item);
    if (_nextEpisode != null && _s.settings.autoNextEpisode && _nextDismissed != _item.extId) {
      _playNextEpisode();
    } else {
      _showControls(sticky: true);
    }
  }

  // ------------------------------------------------------------ controls

  void _showControls({bool sticky = false}) {
    if (!_controls) setState(() => _controls = true);
    _hideTimer?.cancel();
    if (sticky) return;
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || _overControls || _panel != _Panel.none) return;
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
    if (_casting) {
      _cast.togglePlay();
      return _showControls();
    }
    if (_isLive && _ps.player.state.playing) _timeshift = true;
    _ps.player.playOrPause();
    _showControls();
  }

  void _seekBy(int seconds) {
    if (_casting) {
      if (_isLive) return _flash('Pas de retour en arrière sur le direct à la télé');
      _cast.seekBy(Duration(seconds: seconds));
      _flash(seconds > 0 ? '+$seconds s' : '$seconds s');
      return _showControls();
    }
    if (_isLive && seconds < 0) _timeshift = true;
    final st = _ps.player.state;
    if (!_isLive && st.completed) {
      // At the end of a film a relative seek left it "ended": Espace then
      // started it over from 0:00. A seek to a place does not.
      final to = st.position + Duration(seconds: seconds);
      _ps.player.seek(to < Duration.zero ? Duration.zero : (to > st.duration ? st.duration : to));
    } else {
      _ps.seekBy(Duration(seconds: seconds));
    }
    _flash(seconds > 0 ? '+$seconds s' : '$seconds s');
    _showControls();
  }

  /// Scroll not yet turned into volume (a touchpad sends many small ones).
  double _wheel = 0;

  /// The wheel changes the volume by 5 % a notch. A touchpad's small
  /// moves add up to a notch (each one was 5 %), and a sideways scroll does
  /// nothing (it lowered the volume).
  void _onWheel(Offset delta) {
    if (delta.dx.abs() > delta.dy.abs() || delta.dy == 0) return;
    if (delta.dy.abs() >= 50) {
      _wheel = 0;
      return _changeVolume(delta.dy < 0 ? 5 : -5);
    }
    if (_wheel != 0 && _wheel.sign != delta.dy.sign) _wheel = 0;
    _wheel += delta.dy;
    if (_wheel.abs() >= 50) {
      _changeVolume(_wheel < 0 ? 5 : -5);
      _wheel = 0;
    }
  }

  void _changeVolume(double delta) {
    if (_casting) {
      final v = (_cast.volume * 100 + delta).clamp(0.0, 100.0);
      _cast.setVolume(v / 100);
      return _flash('Volume de la télé ${v.round()} %');
    }
    final v = (_ps.player.state.volume + delta).clamp(0.0, 150.0);
    _ps.player.setVolume(v);
    _flash('Volume ${v.round()} %');
  }

  double _castVolumeBeforeMute = 0.5;

  void _toggleMute() {
    if (_casting) {
      final v = _cast.volume;
      if (v > 0) {
        _castVolumeBeforeMute = v;
        _cast.setVolume(0);
        _flash('Télé en muet');
      } else {
        _cast.setVolume(_castVolumeBeforeMute);
        _flash('Volume de la télé ${(_castVolumeBeforeMute * 100).round()} %');
      }
      return;
    }
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
    if (_casting) return _flash('Les pistes se choisissent sur la télé');
    final tracks = _ps.player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (tracks.length < 2) return _flash('Une seule piste audio');
    final i = tracks.indexWhere((t) => t.id == _aid);
    final next = tracks[(i + 1) % tracks.length];
    _selectAudio(next);
    _flash('Audio : ${audioTrackLabel(next, tracks.indexOf(next))}');
  }

  void _cycleSubtitles() {
    if (_casting) return _flash('Les sous-titres se choisissent sur la télé');
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

  bool _channelLocked(Channel c) => _s.repo.isLocked(c.sourceId, ContentKind.live, c.extId);

  /// Next or previous channel, over those locked since the list was made
  /// (the code typed, then locked again while the mini-player kept it).
  void _zap(int delta) {
    if (_channels.isEmpty || _source == null) return;
    for (var step = 1; step <= _channels.length; step++) {
      final i = (_chIndex + delta * step) % _channels.length;
      if (!_channelLocked(_channels[i])) return _playChannel(i, settle: true);
    }
  }

  /// Opening of the stream chosen by zapping, put off a moment.
  Timer? _zapTimer;

  /// [settle]: a gamepad held on a direction sends a full press every
  /// 90 ms. The channel shown changes at once, its stream is opened once
  /// the zapping stops (300 ms): eleven streams a second were asked of the
  /// provider, and "Récentes" filled with channels passed by.
  void _playChannel(int index, {bool settle = false}) {
    if (_source == null || index < 0 || index >= _channels.length) return;
    final c = _channels[index];
    if (_channelLocked(c)) {
      _flash('Chaîne protégée par le contrôle parental');
      return;
    }
    setState(() {
      _chIndex = index;
      _item = channelItem(_source!, c);
      _error = null;
      _timeshift = false;
      _variants = null;
    });
    _zapTimer?.cancel();
    void open() {
      _open(_item);
      _s.repo.touchChannel(c.sourceId, c.extId);
    }

    if (settle) {
      final item = _item;
      _zapTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && identical(_item, item)) open();
      });
    } else {
      open();
    }
    _flash('${c.number ?? index + 1}  ${_s.channelName(c)}');
    _showControls();
  }

  void _typeDigit(String d) {
    _digitTimer?.cancel();
    // Up to 6 digits: providers number channels beyond 9999.
    setState(() => _digits = (_digits + d).substring(_digits.length >= 6 ? 1 : 0));
    _digitTimer = Timer(const Duration(milliseconds: 1400), () {
      final n = int.tryParse(_digits);
      setState(() => _digits = '');
      if (n == null || _channels.isEmpty) return;
      // The number shown for each channel (its own, else its place in the
      // list), as in the lists: the place alone could pick a channel that
      // shows another number.
      var idx = -1;
      for (var i = 0; i < _channels.length; i++) {
        if ((_channels[i].number ?? i + 1) == n) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) {
        _playChannel(idx);
      } else {
        _flash('Chaîne $n introuvable');
      }
    });
  }

  void _setPanel(_Panel p) {
    final next = _panel == p ? _Panel.none : p;
    if (next == _Panel.channels && (!_isLive || _channels.isEmpty)) return;
    if (next == _Panel.guide && !_isLive) return;
    if (next == _Panel.episodes && _episodes.isEmpty) return;
    if (next == _Panel.audio && _casting) return;
    setState(() => _panel = next);
    if (next == _Panel.audio) _refreshSelectedTracks();
    if (next == _Panel.episodes) _panelSeason = _episodes.where((e) => e.extId == _item.extId).firstOrNull?.season;
    if (next == _Panel.channels) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_panelScroll.hasClients) {
          _panelScroll.jumpTo(
            (_chIndex * ChannelListPanel.rowExtent - 200).clamp(0.0, _panelScroll.position.maxScrollExtent),
          );
        }
      });
    }
    if (next == _Panel.none) {
      _showControls();
      _focus.requestFocus();
    } else {
      _showControls(sticky: true);
    }
  }

  /// Next quality of the live channel ("TF1 FHD" → "TF1 HD" → …).
  void _cycleQuality() {
    final ch = _currentChannel;
    if (ch == null || _source == null) return;
    final variants = _variants ??= _s.repo.channelVariants(ch);
    if (variants.length < 2) return _flash('Une seule qualité pour cette chaîne');
    final i = variants.indexWhere((c) => c.extId == ch.extId);
    final next = variants[(i + 1) % variants.length];
    setState(() {
      _item = channelItem(_source!, next);
      _error = null;
      _timeshift = false;
    });
    _open(_item);
    _flash(channelQuality(next.name) ?? next.name);
  }

  // -------------------------------------------------------------- series

  int get _episodeIndex => _episodes.indexWhere((e) => e.extId == _item.extId);

  Episode? get _nextEpisode {
    final i = _episodeIndex;
    return (i >= 0 && i + 1 < _episodes.length) ? _episodes[i + 1] : null;
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (next != null) _playEpisode(next);
  }

  void _playEpisode(Episode e) {
    if (_source == null) return;
    if (_s.repo.isLocked(_item.sourceId, ContentKind.episode, e.extId, seriesExt: e.seriesExt)) {
      _flash('Série protégée par le contrôle parental');
      return;
    }
    _s.tracker.flush();
    final p = _s.repo.progress(_item.sourceId, ContentKind.episode, e.extId);
    // Another episode: the preview of the previous one is given back.
    _preview.close();
    setState(() {
      _item = episodeItem(_source!, widget.session.series, e);
      _panel = _Panel.none;
    });
    _open(_item, start: (p != null && p.resumable) ? p.position : null, force: true);
    _flash(e.code);
    _showControls();
  }

  // ------------------------------------------------------------ keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final step = _s.settings.seekStep * (shift ? 6 : 1);
    final repeat = e is KeyRepeatEvent;

    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK || k == LogicalKeyboardKey.mediaPlayPause) {
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
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11 || k == LogicalKeyboardKey.contextMenu) {
      if (!repeat) _setFullscreen(!_fullscreen);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_panel != _Panel.none) {
        _setPanel(_panel);
      } else if (_showStats) {
        setState(() => _showStats = false);
      } else if (_fullscreen) {
        _setFullscreen(false);
      } else {
        _leave();
      }
    } else if (k == LogicalKeyboardKey.backspace) {
      _leave();
    } else if (k == LogicalKeyboardKey.keyM) {
      if (!repeat) _toggleMute();
    } else if (k == LogicalKeyboardKey.keyP) {
      if (!repeat) _minimize();
    } else if (k == LogicalKeyboardKey.keyO && AppWindow.canFloat && !_casting) {
      if (!repeat) _minimize(floating: true);
    } else if (k == LogicalKeyboardKey.keyV && _isLive && !_casting) {
      if (!repeat) _openMultiView();
    } else if (k == LogicalKeyboardKey.keyT) {
      if (!repeat) _setPanel(_Panel.cast);
    } else if (k == LogicalKeyboardKey.keyI && !_casting) {
      if (!repeat) setState(() => _showStats = !_showStats);
    } else if (k == LogicalKeyboardKey.keyA) {
      if (!repeat) _cycleAudio();
    } else if (k == LogicalKeyboardKey.keyS) {
      if (!repeat) _cycleSubtitles();
    } else if (k == LogicalKeyboardKey.keyR) {
      if (!repeat) _cycleAspect();
    } else if (k == LogicalKeyboardKey.keyC) {
      if (!repeat) _setPanel(_Panel.channels);
    } else if (k == LogicalKeyboardKey.keyG) {
      if (!repeat) _setPanel(_Panel.guide);
    } else if (k == LogicalKeyboardKey.keyE) {
      if (!repeat) _setPanel(_Panel.episodes);
    } else if (k == LogicalKeyboardKey.keyN) {
      if (!repeat) _playNextEpisode();
    } else if (k == LogicalKeyboardKey.home && !_isLive) {
      _casting ? _cast.seekTo(Duration.zero) : _ps.player.seek(Duration.zero);
    } else if (_isLive && _digitOf(k) != null) {
      _typeDigit(_digitOf(k)!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String? _digitOf(LogicalKeyboardKey k) {
    const digits = [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    var i = digits.indexOf(k);
    if (i < 0) i = numpad.indexOf(k);
    return i < 0 ? null : '$i';
  }

  // --------------------------------------------------------------- build

  bool get _visible => _controls || !_playing || _panel != _Panel.none || _casting;

  // The player is always dark, whatever the app's theme.
  @override
  Widget build(BuildContext context) => Theme(
    data: darkTheme,
    child: Builder(builder: _buildPlayer),
  );

  Widget _buildPlayer(BuildContext context) {
    final (fit, ratio) = switch (_aspect) {
      _Aspect.auto => (BoxFit.contain, null),
      _Aspect.r169 => (BoxFit.contain, 16 / 9),
      _Aspect.r43 => (BoxFit.contain, 4 / 3),
      _Aspect.r219 => (BoxFit.contain, 2.39),
      _Aspect.zoom => (BoxFit.cover, null),
      _Aspect.stretch => (BoxFit.fill, null),
    };
    final vis = _visible;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && _panel == _Panel.none) _onWheel(e.scrollDelta);
          },
          child: MouseRegion(
            cursor: vis ? SystemMouseCursors.basic : SystemMouseCursors.none,
            onHover: (_) => _showControls(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _focus.requestFocus();
                    if (_panel != _Panel.none) return _setPanel(_panel);
                    _togglePlay();
                  },
                  onDoubleTap: () => _setFullscreen(!_fullscreen),
                  child: _casting
                      ? CastRemoteView(
                          cast: _cast,
                          image: _castImage(),
                          onRetry: ({bool? viaRelay}) => _cast.retry(viaRelay: viaRelay),
                          onStop: _stopCasting,
                        )
                      : Video(
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
                // Shade at the top and bottom behind the bars.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: vis ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xBF000000), Color(0x00000000), Color(0x00000000), Color(0xE6000000)],
                          stops: [0, 0.22, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_playing && _panel == _Panel.none && _error == null && !_casting)
                  _isLive ? const LivePausedBadge() : _pauseInfo(),
                if (!_casting && _error == null) _buildBuffering(),
                if (_osd != null) _buildOsd(),
                if (_digits.isNotEmpty) _buildDigits(),
                if (!_casting) _buildError(),
                if (_isLive && _panel == _Panel.guide) MiniGuide(programs: _miniGuide()),
                _topBar(vis),
                _bottomBar(vis),
                ..._floating(vis),
                if (_showStats && !_casting)
                  StatsCard(stats: _stats, onClose: () => setState(() => _showStats = false)),
                ..._panels(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- overlays

  Widget _buildBuffering() {
    return IgnorePointer(
      child: StreamBuilder<bool>(
        stream: _ps.player.stream.buffering,
        initialData: _ps.player.state.buffering,
        builder: (context, snap) {
          if (snap.data != true) return const SizedBox.shrink();
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 54,
                  height: 54,
                  child: CircularProgressIndicator(strokeWidth: 3, color: DarkColors.accent),
                ),
                const SizedBox(height: 14),
                StreamBuilder<double>(
                  stream: _ps.player.stream.bufferingPercentage,
                  builder: (context, p) => Text(
                    p.hasData && p.data! > 0 ? 'Mise en mémoire… ${p.data!.round()} %' : 'Chargement…',
                    style: darkMono(13, color: DarkColors.textSoft),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOsd() => IgnorePointer(
    child: Align(
      alignment: const Alignment(0, -0.55),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xD60D0C0B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Text(_osd!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ),
    ),
  );

  Widget _buildDigits() => Positioned(
    top: 100,
    right: 48,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xD60D0C0B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DarkColors.accent, width: 1.5),
      ),
      child: Text(
        _digits,
        style: darkMono(44, weight: FontWeight.w600, color: DarkColors.accent, height: 1.1),
      ),
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
          alignment: const Alignment(0, 0.1),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xEB0D0C0B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  reconnecting ? Icons.wifi_tethering_rounded : Icons.error_outline_rounded,
                  color: DarkColors.accent,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  (reconnecting ? message : 'Lecture impossible').toUpperCase(),
                  textAlign: TextAlign.center,
                  style: darkPoster(30, height: 1),
                ),
                if (!reconnecting) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DarkColors.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() => _error = null);
                      _ps.status.value = null;
                      // Nothing was read: back to where this film was to
                      // resume, not to its beginning.
                      final here = _ps.player.state.position;
                      final resume = _item.url == widget.session.item.url ? widget.session.start : null;
                      _ps.play(_item, force: true, start: _isLive ? null : (here > Duration.zero ? here : resume));
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Réessayer'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// What a paused film or episode is (TMDB / provider details).
  Widget _pauseInfo() {
    final episode = _item.kind == ContentKind.episode;
    final series = widget.session.series;
    final movie = episode ? null : _s.repo.movieByExt(_item.sourceId, _item.extId);
    final tm = movie != null ? _s.tmdb.cachedMovie(movie) : (series != null ? _s.tmdb.cachedSeries(series) : null);
    final ep = episode ? _episodes.where((e) => e.extId == _item.extId).firstOrNull : null;
    final rating = movie?.rating ?? series?.rating ?? tm?.rating;
    final year = movie?.year ?? series?.year ?? tm?.year;
    final genre = (tm?.genres.isNotEmpty ?? false) ? tm!.genres.take(2).join(', ') : series?.genre;
    final meta = [
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1).replaceAll('.', ',')}',
      if (episode && ep != null) ep.code,
      if (year != null) '$year',
      if (genre != null && genre.isNotEmpty) genre,
    ].join('  ·  ');
    final synopsis = episode ? (ep?.plot ?? series?.plot ?? tm?.overview) : tm?.overview;
    final people = tm == null
        ? const <CastMember>[]
        : (tm.people.isNotEmpty ? tm.people : [for (final n in tm.cast) CastMember(n)]);
    return PauseInfo(
      kicker: episode ? (ep?.code ?? 'Épisode') : 'Film',
      title: displayTitle(episode ? (series?.name ?? _item.title) : (movie?.name ?? _item.title)),
      meta: meta,
      synopsis: synopsis,
      people: people,
    );
  }

  List<Program> _miniGuide() {
    final ch = _currentChannel;
    if (ch == null) return const [];
    final now = DateTime.now();
    return _s.epg.programs(ch, now, now.add(const Duration(hours: 12))).take(4).toList();
  }

  // ------------------------------------------------------------- top bar

  Widget _topBar(bool vis) {
    final ch = _currentChannel;
    final episode = _item.kind == ContentKind.episode;
    final ep = episode ? _episodes.where((e) => e.extId == _item.extId).firstOrNull : null;
    Widget title;
    if (_isLive) {
      final name = ch == null ? _item.title : _s.channelName(ch);
      title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChannelLogo(name: name, url: ch?.logo ?? _item.image, size: 44),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1),
                ),
                const SizedBox(height: 6),
                Text(
                  'Chaîne ${ch?.number ?? _chIndex + 1}',
                  style: darkMono(13, color: DarkColors.textSoft, height: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          ValueListenableBuilder<Duration>(
            valueListenable: _position,
            builder: (context, pos, _) => ValueListenableBuilder<CacheState>(
              valueListenable: _cache,
              builder: (context, cache, _) => LiveTag(delay: _delay(pos, cache)),
            ),
          ),
        ],
      );
    } else if (_playing || _casting || _panel != _Panel.none) {
      final series = widget.session.series;
      final sub = ep != null
          ? '${ep.code} · ${ep.displayTitle}'
          : [if (_item.subtitle != null) _item.subtitle!].join(' · ');
      title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayTitle(episode ? (series?.name ?? _item.title) : _item.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: darkMono(13, color: DarkColors.textSoft, height: 1),
            ),
          ],
        ],
      );
    } else {
      title = const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !vis,
        child: AnimatedOpacity(
          opacity: vis ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
            child: Row(
              children: [
                RoundGlassButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: _casting ? 'Retour (la télé continue)' : 'Retour (Échap)',
                  onTap: _leave,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                CastButton(cast: _cast, onTap: () => _setPanel(_Panel.cast)),
                const SizedBox(width: 6),
                if (_isLive && ch != null && !_casting) ...[
                  PlayerIconButton(
                    icon: Icons.grid_view_rounded,
                    tooltip: 'Multi-écran : cette chaîne et d’autres en même temps (V)',
                    onTap: _openMultiView,
                  ),
                  const SizedBox(width: 6),
                ],
                if (!_casting) ...[
                  PlayerIconButton(
                    icon: Icons.monitor_heart_outlined,
                    tooltip: 'Statistiques du flux (I)',
                    onTap: () => setState(() => _showStats = !_showStats),
                  ),
                  const SizedBox(width: 6),
                ],
                PlayerIconButton(
                  icon: Icons.picture_in_picture_alt_rounded,
                  tooltip: _casting ? 'Mini-lecteur : piloter la télé en naviguant (P)' : "Image dans l'image (P)",
                  onTap: _minimize,
                ),
                if (AppWindow.canFloat && !_casting) ...[
                  const SizedBox(width: 6),
                  PlayerIconButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Fenêtre flottante par-dessus tes autres apps (O)',
                    onTap: () => _minimize(floating: true),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Replaces the player by the multi-view, with this channel in it.
  void _openMultiView() {
    final ch = _currentChannel;
    if (ch == null || _s.activeSource?.id != ch.sourceId) return;
    Navigator.of(context).pushReplacement(MultiViewScreen.route(add: ch));
  }

  /// How far behind the live edge playback is, or null when at the edge.
  Duration? _delay(Duration pos, CacheState cache) {
    if (!_timeshift || _casting) return null;
    final end = cache.cacheEnd;
    final behind = end == null ? Duration.zero : end - pos;
    if (behind.inSeconds < 20 && _playing) return null;
    return behind.isNegative ? Duration.zero : behind;
  }

  void _backToLive() {
    final end = _cache.value.cacheEnd;
    if (end != null) _ps.player.seek(end - const Duration(seconds: 2));
    if (!_ps.player.state.playing) _ps.player.play();
    setState(() => _timeshift = false);
  }

  // ---------------------------------------------------------- bottom bar

  Widget _bottomBar(bool vis) {
    final step = _s.settings.seekStep;
    final ch = _currentChannel;
    final next = _nextEpisode;
    final hasEpisodes = _episodes.isNotEmpty;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !vis,
        child: AnimatedOpacity(
          opacity: vis ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: MouseRegion(
            onEnter: (_) => _overControls = true,
            onExit: (_) {
              _overControls = false;
              _showControls();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 48, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLive)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: LiveProgramInfo(
                        now: ch == null ? null : _s.epg.now(ch),
                        next: ch == null ? null : _s.epg.next(ch),
                        fallbackTitle: ch == null ? _item.title : _s.channelName(ch),
                      ),
                    )
                  else
                    ValueListenableBuilder<Duration>(
                      valueListenable: _position,
                      builder: (context, pos, _) => ValueListenableBuilder<CacheState>(
                        valueListenable: _cache,
                        builder: (context, cache, _) => ListenableBuilder(
                          listenable: _preview,
                          builder: (context, _) => VodSeekRow(
                            position: pos,
                            duration: _dur,
                            ranges: _casting ? const [] : cache.ranges,
                            onInteraction: _showControls,
                            onPoint: _onSeekPoint,
                            preview: _preview.visible ? _preview.view() : null,
                            previewWidth: SeekPreview.width,
                            onSeek: (d) {
                              _casting ? _cast.seekTo(d) : _ps.player.seek(d);
                              _position.value = d;
                            },
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      PlayPauseButton(
                        player: _ps.player,
                        onTap: _togglePlay,
                        playing: _casting ? (_cast.playing || _cast.status.state == RemoteState.buffering) : null,
                      ),
                      const SizedBox(width: 12),
                      if (!_isLive) ...[
                        PlayerIconButton(
                          icon: Icons.replay_10_rounded,
                          size: 24,
                          tooltip: 'Reculer de $step s (←)',
                          onTap: () => _seekBy(-step),
                        ),
                        const SizedBox(width: 6),
                        PlayerIconButton(
                          icon: Icons.forward_10_rounded,
                          size: 24,
                          tooltip: 'Avancer de $step s (→)',
                          onTap: () => _seekBy(step),
                        ),
                        const SizedBox(width: 6),
                      ],
                      VolumeControl(
                        service: _ps,
                        onMute: _toggleMute,
                        remote: _casting ? _cast.volume * 100 : null,
                        onChanged: (v) {
                          _casting ? _cast.setVolume(v / 100) : _ps.player.setVolume(v);
                          _showControls();
                        },
                      ),
                      if (_isLive)
                        ValueListenableBuilder<Duration>(
                          valueListenable: _position,
                          builder: (context, pos, _) => ValueListenableBuilder<CacheState>(
                            valueListenable: _cache,
                            builder: (context, cache, _) => _delay(pos, cache) == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: FilledButton.icon(
                                      onPressed: _backToLive,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: DarkColors.accent,
                                        foregroundColor: DarkColors.onAccent,
                                        minimumSize: const Size(0, 40),
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        textStyle: const TextStyle(
                                          fontFamily: AppFonts.body,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      icon: const Icon(Icons.circle, size: 8),
                                      label: const Text('Revenir au direct'),
                                    ),
                                  ),
                          ),
                        ),
                      const Spacer(),
                      if (_isLive && _channels.isNotEmpty)
                        PlayerTextButton(
                          icon: Icons.format_list_bulleted_rounded,
                          label: 'Chaînes',
                          tooltip: 'Chaînes (C)',
                          active: _panel == _Panel.channels,
                          onTap: () => _setPanel(_Panel.channels),
                        ),
                      if (_isLive)
                        PlayerTextButton(
                          icon: Icons.table_chart_outlined,
                          label: 'Mini-guide',
                          tooltip: 'Mini-guide (G)',
                          active: _panel == _Panel.guide,
                          onTap: () => _setPanel(_Panel.guide),
                        ),
                      if (next != null)
                        PlayerIconButton(
                          icon: Icons.skip_next_rounded,
                          tooltip: 'Épisode suivant (N)',
                          onTap: _playNextEpisode,
                        ),
                      if (hasEpisodes)
                        PlayerTextButton(
                          icon: Icons.video_library_outlined,
                          label: 'Épisodes',
                          tooltip: 'Épisodes (E)',
                          active: _panel == _Panel.episodes,
                          onTap: () => _setPanel(_Panel.episodes),
                        ),
                      if (!_casting)
                        PlayerTextButton(
                          icon: Icons.subtitles_outlined,
                          label: 'Audio et sous-titres',
                          tooltip: 'Audio et sous-titres (A / S)',
                          active: _panel == _Panel.audio,
                          onTap: () => _setPanel(_Panel.audio),
                        ),
                      if (_isLive)
                        QualityButton(
                          label:
                              channelQuality(_item.title) ?? (ch == null ? 'Auto' : channelQuality(ch.name) ?? 'Auto'),
                          tooltip: 'Qualité du flux : change de qualité si la chaîne en a plusieurs',
                          onTap: _cycleQuality,
                        )
                      else if (!_casting)
                        StreamBuilder<int?>(
                          stream: _ps.player.stream.height,
                          initialData: _ps.player.state.height,
                          builder: (context, h) =>
                              QualityButton(label: resolutionLabel(h.data), tooltip: 'Qualité de la vidéo'),
                        ),
                      PlayerIconButton(
                        icon: _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                        size: 24,
                        tooltip: 'Plein écran (F)',
                        onTap: () => _setFullscreen(!_fullscreen),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ floating

  List<Widget> _floating(bool vis) {
    if (_item.kind != ContentKind.episode || _panel != _Panel.none) return const [];
    final bottom = vis ? 150.0 : 48.0;
    return [
      ValueListenableBuilder<Duration>(
        valueListenable: _position,
        builder: (context, pos, _) {
          final dur = _dur;
          final next = _nextEpisode;
          final left = (dur - pos).inSeconds;
          Widget? child;
          if (next != null && dur.inSeconds > 60 && left <= 20 && _nextDismissed != _item.extId) {
            child = NextEpisodePrompt(
              episode: next,
              secondsLeft: left,
              auto: _s.settings.autoNextEpisode,
              onPlay: _playNextEpisode,
              onCancel: () => setState(() => _nextDismissed = _item.extId),
            );
          }
          return AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            right: 48,
            bottom: bottom,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    ];
  }

  // -------------------------------------------------------------- panels

  List<Widget> _panels() {
    switch (_panel) {
      case _Panel.channels:
        return [
          // A click beside the panel closes it.
          Positioned.fill(child: GestureDetector(onTap: () => _setPanel(_panel))),
          ChannelListPanel(
            channels: _channels,
            names: _s.channelName,
            selected: _chIndex,
            epg: _s.epg,
            scroll: _panelScroll,
            onPick: _playChannel,
            onClose: () => _setPanel(_panel),
          ),
        ];
      case _Panel.audio:
        return [
          Positioned.fill(child: GestureDetector(onTap: () => _setPanel(_panel))),
          TracksSidePanel(
            tracks: _ps.player.state.tracks,
            audioId: _aid,
            subtitleId: _sid,
            onAudio: _selectAudio,
            onSubtitle: _selectSubtitle,
            subtitleScale: _s.settings.subtitleScale,
            onSubtitleScale: (v) {
              _s.settings.update((s) => s.subtitleScale = v);
              _ps.setProp('sub-scale', '$v');
              setState(() {});
            },
            onClose: () => _setPanel(_panel),
            extra: [
              if (!_isLive)
                panelSegmentsSection<double>(
                  'Vitesse de lecture',
                  [
                    0.5,
                    0.75,
                    1.0,
                    1.25,
                    1.5,
                    2.0,
                  ].reduce((a, b) => (a - _ps.player.state.rate).abs() < (b - _ps.player.state.rate).abs() ? a : b),
                  const [(0.75, '×0,75'), (1.0, 'Normale'), (1.25, '×1,25'), (1.5, '×1,5'), (2.0, '×2')],
                  (r) async {
                    await _ps.player.setRate(r);
                    if (mounted) setState(() {});
                  },
                ),
              panelSegmentsSection<_Aspect>("Format d'image", _aspect, [
                for (final a in _Aspect.values) (a, a.short),
              ], (a) => setState(() => _aspect = a)),
            ],
          ),
        ];
      case _Panel.episodes:
        final seasons = _episodes.map((e) => e.season).toSet().toList()..sort();
        return [
          Positioned.fill(child: GestureDetector(onTap: () => _setPanel(_panel))),
          EpisodesPanel(
            seriesTitle: displayTitle(widget.session.series?.name ?? _item.title),
            episodes: _episodes,
            current: _item.extId,
            season: _panelSeason ?? seasons.firstOrNull ?? 1,
            seasons: seasons,
            onSeason: (n) => setState(() => _panelSeason = n),
            progressOf: (e) {
              if (e.extId == _item.extId) {
                final d = _dur.inMilliseconds;
                return d <= 0 ? 0 : _pos.inMilliseconds / d;
              }
              final p = _s.repo.progress(_item.sourceId, ContentKind.episode, e.extId);
              return p == null ? 0 : (p.finished ? 1 : p.fraction);
            },
            onPick: (e) => e.extId == _item.extId ? _setPanel(_panel) : _playEpisode(e),
            onClose: () => _setPanel(_panel),
          ),
        ];
      case _Panel.cast:
        return [
          Positioned.fill(child: GestureDetector(onTap: () => _setPanel(_panel))),
          CastPanel(cast: _cast, onPick: _castTo, onStop: _stopCasting, onClose: () => _setPanel(_panel)),
        ];
      case _Panel.guide:
      case _Panel.none:
        return const [];
    }
  }

  /// Artwork behind "En diffusion sur…" (films and episodes; channel logos
  /// are too small to fill the screen).
  String? _castImage() => _isLive ? null : _item.image;
}

enum _Panel { none, channels, guide, audio, episodes, cast }
