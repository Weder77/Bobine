import 'package:flutter/foundation.dart';

import '../cast/cast_service.dart';
import '../core/window.dart';
import 'player_service.dart';
import 'player_session.dart';

/// Picture-in-picture: the video keeps playing in a small window while the
/// user browses ([session] set), or in a floating window above the other
/// apps on Windows ([floating]). While casting, the small window controls
/// the TV.
class PipController {
  PipController(this._player, [this._cast]);
  final PlayerService _player;
  final CastService? _cast;

  /// What to reopen full screen; null when no mini-player is shown.
  final ValueNotifier<PlayerSession?> session = ValueNotifier(null);

  /// The app window itself is the floating player (Windows only).
  final ValueNotifier<bool> floating = ValueNotifier(false);

  bool get active => session.value != null;

  /// Shrinks the player into the mini-player.
  void show(PlayerSession s) => session.value = s;

  /// Turns the app window into a small video window above the other apps.
  Future<void> float(PlayerSession s) async {
    session.value = s;
    if (await AppWindow.setFloating(true)) floating.value = true;
  }

  /// Back to the normal window (the mini-player stays).
  Future<void> unfloat() async {
    if (!floating.value) return;
    floating.value = false;
    await AppWindow.setFloating(false);
  }

  /// Hides the mini-player without stopping playback (it grows back into
  /// the full screen player).
  void release() => session.value = null;

  /// Stops playback (on the TV too) and closes the mini-player / floating window.
  Future<void> close() async {
    await unfloat();
    session.value = null;
    if (_cast?.active ?? false) await _cast!.stop();
    await _player.stop();
  }
}
