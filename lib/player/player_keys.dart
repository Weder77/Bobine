import 'package:flutter/services.dart';

/// Who handles a key pressed in the player.
enum PlayerKeyRoute {
  /// The player itself (seek, zap, pause, number…).
  handle,

  /// The focused button of the controls: arrows move between buttons, OK
  /// presses the button (Flutter's own focus navigation).
  toFocusedButton,

  /// OK while no button is selected: show the controls, focus on play / pause.
  revealControls,
}

final _arrows = {
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
};

final _ok = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// With a TV remote the arrows seek and zap while the picture is alone, and
/// move between the buttons once OK has shown the controls.
PlayerKeyRoute playerKeyRoute(LogicalKeyboardKey key, {required bool controlsVisible, required bool buttonFocused}) {
  final arrowOrOk = _arrows.contains(key) || _ok.contains(key);
  if (controlsVisible && buttonFocused && arrowOrOk) return PlayerKeyRoute.toFocusedButton;
  // Also with the controls already there (in pause they stay): OK selects
  // play / pause, from where the arrows reach every button.
  if (!buttonFocused && _ok.contains(key)) return PlayerKeyRoute.revealControls;
  return PlayerKeyRoute.handle;
}
