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

/// OK of a remote (or of a gamepad).
bool isOkKey(LogicalKeyboardKey key) => _ok.contains(key);

/// What OK does in the TV player, which has no buttons to pick.
enum TvPlayerOk {
  togglePause,

  /// "Lecture impossible" is shown: try again.
  retry,

  /// "Épisode suivant" is offered at the end of an episode: play it.
  nextEpisode,
}

TvPlayerOk tvPlayerOk({required bool error, required bool nextShown}) {
  if (error) return TvPlayerOk.retry;
  if (nextShown) return TvPlayerOk.nextEpisode;
  return TvPlayerOk.togglePause;
}

/// Whether [key] opens the multi-view: V on a live channel, not cast, and
/// only on a computer. The TV has none (its screen is made for a mouse, not
/// the remote), but a keyboard plugged into the box still sends V.
bool opensMultiView(LogicalKeyboardKey key, {required bool live, required bool casting, required bool tv}) =>
    key == LogicalKeyboardKey.keyV && live && !casting && !tv;

/// What an arrow does in the TV player.
enum TvPlayerArrow { seekBack, seekForward, zapPrevious, zapNext, channels, options }

/// Live: Up / Down change channel, Left opens the list of channels, Right
/// the options (favourite, audio, subtitles). Film or episode: Left / Right
/// go back / forward, Up / Down open audio and subtitles.
TvPlayerArrow? tvPlayerArrow(LogicalKeyboardKey key, {required bool live}) {
  if (key == LogicalKeyboardKey.arrowUp) return live ? TvPlayerArrow.zapPrevious : TvPlayerArrow.options;
  if (key == LogicalKeyboardKey.arrowDown) return live ? TvPlayerArrow.zapNext : TvPlayerArrow.options;
  if (key == LogicalKeyboardKey.arrowLeft) return live ? TvPlayerArrow.channels : TvPlayerArrow.seekBack;
  if (key == LogicalKeyboardKey.arrowRight) return live ? TvPlayerArrow.options : TvPlayerArrow.seekForward;
  return null;
}
