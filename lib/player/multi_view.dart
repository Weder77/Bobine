import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BoxFit, Color, Widget;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'play_items.dart';
import 'player_service.dart';
import 'reconnect.dart';

/// How the channels are laid out. Every slot is a 16:9 cell of a 16:9 stage
/// (2 × 2 or 3 × 3 grid), so videos fill their slot without black bars.
enum MultiLayout {
  duo('Côte à côte', 2),
  trio('1 + 2', 3),
  quad('2 × 2', 4),
  focus('1 + 3', 4);

  const MultiLayout(this.label, this.slots);
  final String label;
  final int slots;

  /// Slots on a 1 × 1 stage; the first one is the big one where there is one.
  List<Rect> get rects => switch (this) {
    duo => const [Rect.fromLTWH(0, 0.25, 0.5, 0.5), Rect.fromLTWH(0.5, 0.25, 0.5, 0.5)],
    trio => const [
      Rect.fromLTWH(0, 1 / 6, 2 / 3, 2 / 3),
      Rect.fromLTWH(2 / 3, 1 / 6, 1 / 3, 1 / 3),
      Rect.fromLTWH(2 / 3, 1 / 2, 1 / 3, 1 / 3),
    ],
    quad => const [
      Rect.fromLTWH(0, 0, 0.5, 0.5),
      Rect.fromLTWH(0.5, 0, 0.5, 0.5),
      Rect.fromLTWH(0, 0.5, 0.5, 0.5),
      Rect.fromLTWH(0.5, 0.5, 0.5, 0.5),
    ],
    focus => const [
      Rect.fromLTWH(1 / 6, 0, 2 / 3, 2 / 3),
      Rect.fromLTWH(0, 2 / 3, 1 / 3, 1 / 3),
      Rect.fromLTWH(1 / 3, 2 / 3, 1 / 3, 1 / 3),
      Rect.fromLTWH(2 / 3, 2 / 3, 1 / 3, 1 / 3),
    ],
  };

  /// The smallest layout holding [count] channels.
  static MultiLayout forCount(int count) => count <= 2
      ? duo
      : count == 3
      ? trio
      : quad;

  /// The largest 16:9 area of [size], centred.
  static Rect stage(Size size) {
    final w = size.width / size.height > 16 / 9 ? size.height * 16 / 9 : size.width;
    final h = w * 9 / 16;
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }
}

/// What a slot shows besides the picture.
@immutable
class TileState {
  const TileState({this.loading = true, this.message});
  final bool loading;

  /// "Reconnexion… (2)", "Flux indisponible…", or null.
  final String? message;
}

/// The player of one slot.
abstract class TileEngine {
  ValueListenable<TileState> get state;
  Future<void> open(PlayItem item);

  /// Volume 0 (muted) for every slot but the one heard.
  Future<void> setVolume(double volume);
  Widget view();
  Future<void> dispose();
}

/// A slot's own libmpv instance: small cache (live only), reconnection when
/// the stream stops, no subtitles. The main player keeps its large cache for
/// films and is stopped while the multi-view is open.
class MpvTile implements TileEngine {
  MpvTile({required this.hardwareDecoding, this.deinterlace = 'auto'}) {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Bobine',
        logLevel: MPVLogLevel.warn,
        bufferSize: 8 * 1024 * 1024,
        protocolWhitelist: PlayerService.protocols,
      ),
    );
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        hwdec: hardwareDecoding ? 'auto-safe' : 'no',
        enableHardwareAcceleration: true,
      ),
    );
    _ready = _tune();
    _subs
      ..add(
        _player.stream.completed.listen((done) {
          if (done) _retry();
        }),
      )
      ..add(
        _player.stream.error.listen((e) {
          if (PlayerService.isFatalError(e)) _retry();
        }),
      )
      ..add(
        _player.stream.buffering.listen((b) {
          _bufferingSince = b ? (_bufferingSince ?? DateTime.now()) : null;
          if (!b) _reconnect.playing();
          if (_state.value.loading != b && _state.value.message == null) _state.value = TileState(loading: b);
        }),
      )
      ..add(
        _player.stream.playing.listen((p) {
          if (!p) return;
          _state.value = const TileState(loading: false);
        }),
      );
    // A stream stuck loading (the server stopped sending) is reopened.
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      final since = _bufferingSince;
      if (since != null && DateTime.now().difference(since).inSeconds >= 20) {
        _bufferingSince = null;
        _retry();
      }
    });
  }

  final bool hardwareDecoding;
  final String deinterlace;
  late final Player _player;
  late final VideoController _video;
  late final Future<void> _ready;
  final _state = ValueNotifier(const TileState());
  final List<StreamSubscription> _subs = [];
  late final Timer _watchdog;
  PlayItem? _item;
  DateTime? _bufferingSince;
  final _reconnect = ReconnectBudget(step: const Duration(milliseconds: 800));
  Timer? _retryTimer;
  bool _disposed = false;

  @override
  ValueListenable<TileState> get state => _state;

  Future<void> _set(String name, String value) async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    try {
      await p.setProperty(name, value);
    } catch (e) {
      debugPrint('multi-view: $name failed: $e');
    }
  }

  Future<void> _tune() async {
    final props = {
      ...PlayerService.networkProps,
      // Live only: a few seconds of cache in RAM per slot.
      'cache': 'yes',
      'cache-on-disk': 'no',
      'demuxer-max-bytes': '48MiB',
      'demuxer-max-back-bytes': '8MiB',
      'cache-secs': '20',
      'cache-pause-wait': '1',
      'demuxer-readahead-secs': '2',
      'hwdec': hardwareDecoding ? 'auto-safe' : 'no',
      'vd-lavc-threads': '0',
      'sid': 'no',
      'deinterlace': deinterlace,
      'audio-normalize-downmix': 'yes',
    };
    for (final e in props.entries) {
      await _set(e.key, e.value);
    }
  }

  @override
  Future<void> open(PlayItem item) async {
    await _ready;
    if (_disposed) return;
    _item = item;
    _retryTimer?.cancel();
    _reconnect.reset();
    _state.value = const TileState();
    if (!item.canOpen) {
      _state.value = const TileState(loading: false, message: 'Adresse refusée');
      return;
    }
    final ua = item.userAgent;
    await _set('user-agent', (ua == null || ua.isEmpty) ? 'libmpv' : ua);
    await _player.open(Media(item.url), play: true);
  }

  void _retry() {
    final item = _item;
    if (item == null || _disposed) return;
    // One attempt at a time: a failure often arrives as several errors.
    final wait = _reconnect.next();
    if (wait == null) {
      if (_reconnect.exhausted) _state.value = const TileState(loading: false, message: 'Flux indisponible');
      return;
    }
    _state.value = TileState(message: 'Reconnexion… (${_reconnect.attempts})');
    _retryTimer = Timer(wait, () {
      _reconnect.launched();
      if (!_disposed && identical(_item, item)) unawaited(_player.open(Media(item.url), play: true));
    });
  }

  @override
  Future<void> setVolume(double volume) async {
    await _ready;
    if (!_disposed) await _player.setVolume(volume);
  }

  @override
  Widget view() => Video(
    controller: _video,
    controls: NoVideoControls,
    fit: BoxFit.contain,
    fill: const Color(0xFF000000),
    subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _watchdog.cancel();
    _retryTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    // _state is left to the garbage collector: a slot being removed may
    // still be drawn for one frame.
    await _player.dispose();
  }
}

/// A channel playing in a slot.
class MultiSlot {
  MultiSlot(this.channel, this.engine);
  Channel channel;
  final TileEngine engine;
}

/// The channels of the multi-view, which one is heard, and the layout.
///
/// Remembered per source, so the same matches come back next time.
class MultiViewController extends ChangeNotifier {
  MultiViewController({
    required this.repo,
    required this.source,
    required this.engine,
    double volume = 100,
    this.channelName = _plainName,
  }) : volume = volume <= 0 ? 100 : volume;

  static String _plainName(Channel c) => c.name;

  final Repository repo;
  final Source source;

  /// Creates the player of a slot.
  final TileEngine Function() engine;

  /// Name shown for a channel (cleaned or not, as in the rest of the app).
  final String Function(Channel) channelName;

  static const maxSlots = 4;
  final List<MultiSlot?> slots = List.filled(maxSlots, null);
  MultiLayout layout = MultiLayout.duo;

  /// Slot heard (and framed).
  int selected = 0;

  /// Slot shown alone over the whole stage ("Agrandir"), or null.
  int? solo;
  bool muted = false;
  double volume;
  bool _disposed = false;

  String get _key => 'multiview.${source.id}';

  int get count => slots.where((s) => s != null).length;
  bool get isEmpty => count == 0;

  /// Simultaneous streams the provider allows (Xtream), or null if unknown.
  int? get maxConnections {
    final v = int.tryParse('${source.accountInfo?['max_connections'] ?? ''}');
    return v == null || v <= 0 ? null : v;
  }

  /// More streams than the subscription allows: some may be refused.
  bool get overLimit {
    final max = maxConnections;
    return max != null && count > max;
  }

  /// Restores the last multi-view of this source, then adds [add].
  void restore({Channel? add}) {
    final saved = repo.kvGetJson(_key);
    if (saved != null) {
      layout = MultiLayout.values.where((l) => l.name == saved['layout']).firstOrNull ?? MultiLayout.duo;
      final ids = (saved['channels'] as List? ?? const []).take(maxSlots).toList();
      for (var i = 0; i < ids.length; i++) {
        final ext = ids[i];
        // Saved by another profile, or before the code was asked again: a
        // locked channel does not come back by itself.
        final c = ext is String && !repo.isLocked(source.id, ContentKind.live, ext)
            ? repo.channelByExt(source.id, ext)
            : null;
        if (c != null && i < layout.slots) _put(i, c);
      }
      final heard = saved['selected'];
      if (heard is int && heard >= 0 && heard < layout.slots && slots[heard] != null) selected = heard;
    }
    if (add != null) {
      this.add(add);
    } else {
      _applyVolumes();
      notifyListeners();
    }
  }

  void _save() {
    if (_disposed) return;
    repo.kvSet(
      _key,
      jsonEncode({
        'layout': layout.name,
        'selected': selected,
        'channels': [for (final s in slots) s?.channel.extId],
      }),
    );
  }

  void _put(int index, Channel c) {
    final slot = slots[index];
    if (slot != null && slot.channel.extId == c.extId) return;
    final e = slot?.engine ?? engine();
    slots[index] = MultiSlot(c, e);
    unawaited(e.open(channelItem(source, c)));
  }

  /// Plays [c] in slot [index] (the layout grows if needed); the slot heard
  /// becomes this one when it was empty before.
  void setChannel(int index, Channel c) {
    if (index < 0 || index >= maxSlots) return;
    final wasEmpty = isEmpty;
    _put(index, c);
    if (index >= layout.slots) layout = MultiLayout.forCount(index + 1);
    if (wasEmpty) selected = index;
    repo.touchChannel(c.sourceId, c.extId);
    _applyVolumes();
    _save();
    notifyListeners();
  }

  /// Adds [c]: selects it if already there, else the first free slot (the
  /// layout grows up to four), else replaces the last slot.
  void add(Channel c) {
    final at = slots.indexWhere((s) => s?.channel.extId == c.extId);
    if (at >= 0 && at < layout.slots) {
      select(at);
      return;
    }
    var free = -1;
    for (var i = 0; i < layout.slots; i++) {
      if (slots[i] == null) {
        free = i;
        break;
      }
    }
    if (free < 0) {
      if (layout.slots < maxSlots) {
        free = layout.slots;
        layout = MultiLayout.forCount(free + 1);
      } else {
        free = maxSlots - 1;
      }
    }
    setChannel(free, c);
    select(free);
  }

  /// Stops and empties slot [index].
  void remove(int index) {
    final slot = slots[index];
    if (slot == null) return;
    slots[index] = null;
    unawaited(slot.engine.dispose());
    if (solo == index) solo = null;
    if (selected == index) {
      final other = slots.indexWhere((s) => s != null);
      selected = other < 0 ? 0 : other;
    }
    _applyVolumes();
    _save();
    notifyListeners();
  }

  /// Slot [index] is heard.
  void select(int index) {
    if (index < 0 || index >= layout.slots) return;
    selected = index;
    _applyVolumes();
    _save();
    notifyListeners();
  }

  /// Next / previous filled slot (keyboard, remote).
  void selectNext(int delta) {
    final filled = [
      for (var i = 0; i < layout.slots; i++)
        if (slots[i] != null) i,
    ];
    if (filled.isEmpty) return;
    final at = filled.indexOf(selected);
    select(filled[((at < 0 ? 0 : at) + delta) % filled.length]);
  }

  /// Changes the layout. Channels keep their order; those that no longer
  /// fit are stopped.
  void setLayout(MultiLayout l) {
    if (l == layout) return;
    final kept = [for (final s in slots) ?s];
    for (final s in kept.skip(l.slots)) {
      unawaited(s.engine.dispose());
    }
    final heard = slots[selected]?.channel.extId;
    for (var i = 0; i < maxSlots; i++) {
      slots[i] = i < kept.length && i < l.slots ? kept[i] : null;
    }
    layout = l;
    solo = null;
    final at = slots.indexWhere((s) => s != null && s.channel.extId == heard);
    selected = at >= 0 ? at : 0;
    _applyVolumes();
    _save();
    notifyListeners();
  }

  /// Shows slot [index] alone, or back to the layout.
  void toggleSolo(int index) {
    if (slots[index] == null) return;
    solo = solo == index ? null : index;
    if (solo != null) selected = index;
    _applyVolumes();
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    _applyVolumes();
    notifyListeners();
  }

  void changeVolume(double delta) {
    volume = (volume + delta).clamp(0, 150).toDouble();
    if (volume > 0) muted = false;
    _applyVolumes();
    notifyListeners();
  }

  void _applyVolumes() {
    for (var i = 0; i < maxSlots; i++) {
      unawaited(slots[i]?.engine.setVolume(i == selected && !muted ? volume : 0));
    }
  }

  /// Channel heard, for the title bar.
  String? get heardName {
    final s = slots[selected];
    return s == null ? null : channelName(s.channel);
  }

  /// The channels shown, in order (to zap through them in the full player).
  List<Channel> get channels => [
    for (var i = 0; i < layout.slots; i++)
      if (slots[i] != null) slots[i]!.channel,
  ];

  /// Stops every stream now (before the full player takes over, so the
  /// provider's connection limit is not exceeded).
  Future<void> stopAll() async {
    for (var i = 0; i < maxSlots; i++) {
      final s = slots[i];
      slots[i] = null;
      if (s != null) await s.engine.dispose();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in slots) {
      if (s != null) unawaited(s.engine.dispose());
    }
    super.dispose();
  }
}
