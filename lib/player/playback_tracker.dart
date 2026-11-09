import 'dart:async';

import 'package:flutter/widgets.dart';

import '../cast/cast_service.dart';
import '../data/repository.dart';
import 'player_service.dart';

/// Remembers where each film and episode was stopped ("Reprendre"), whether
/// it plays full screen, in the mini-player, in the floating window or on
/// the TV ([cast]).
///
/// Positions are sampled every 2 s and written every 10 s, when the item
/// changes and when [flush] is called (leaving the player).
class PlaybackTracker {
  PlaybackTracker(this._player, this._repo, {required this.onSaved, this.cast}) {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    _player.current.addListener(_onItemChanged);
    cast?.item.addListener(_onItemChanged);
  }

  final PlayerService _player;
  final Repository _repo;

  /// While casting, the TV's position is the one remembered.
  final CastService? cast;

  bool get _casting => cast?.active ?? false;

  /// What plays now, here or on the TV.
  PlayItem? get _now => _casting ? cast!.item.value : _player.current.value;

  /// Position and length of what plays now.
  (Duration, Duration) get _state {
    if (_casting) return (cast!.position, cast!.duration ?? Duration.zero);
    final st = _player.player.state;
    return (st.position, st.duration);
  }

  /// Called after a save that screens should show (home "Reprendre" row).
  final VoidCallback onSaved;

  Timer? _timer;
  PlayItem? _item;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _ticks = 0;

  void _sample() {
    final item = _now;
    if (item == null || !item.tracksProgress) return;
    final (position, duration) = _state;
    if (duration.inSeconds <= 0) return;
    // Ignore the first frames of a new item (state still holds the old one).
    if (!identical(item, _item) && item.url != _item?.url) {
      _item = item;
      return;
    }
    _item = item;
    _position = position;
    _duration = duration;
    if (++_ticks % 5 == 0) _save();
  }

  void _onItemChanged() {
    final next = _now;
    if (_item != null && next?.url != _item!.url) {
      _save(notify: true);
      _item = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    }
  }

  void _save({bool notify = false}) {
    final item = _item;
    if (item == null || _duration.inSeconds <= 0 || _position.inSeconds < 5) return;
    _repo.saveProgress(
      sourceId: item.sourceId,
      kind: item.kind,
      extId: item.extId,
      position: _position,
      duration: _duration,
      title: item.title,
      subtitle: item.subtitle,
      image: item.image,
      seriesExt: item.seriesExt,
    );
    if (notify) _notifyLater();
  }

  /// Saves now with the latest position (leaving the full screen player).
  void flush() {
    final item = _now;
    if (item != null && item.tracksProgress && item.url == _item?.url) {
      final (position, duration) = _state;
      if (duration.inSeconds > 0) {
        _position = position;
        _duration = duration;
      }
    }
    _save(notify: true);
  }

  /// Marks [item] as watched to the end.
  void markFinished(PlayItem item) {
    if (!item.tracksProgress) return;
    final dur = _state.$2;
    if (dur.inSeconds <= 0) return;
    _item = item;
    _position = dur;
    _duration = dur;
    _save(notify: true);
  }

  // Listeners must not rebuild while a widget tree is being unmounted.
  void _notifyLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) => onSaved());
    WidgetsBinding.instance.scheduleFrame();
  }

  void dispose() {
    _timer?.cancel();
    _player.current.removeListener(_onItemChanged);
    cast?.item.removeListener(_onItemChanged);
  }
}
