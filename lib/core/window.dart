import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native window control: fullscreen through media_kit_video's platform
/// channel, floating "picture in picture" through the Windows runner.
class AppWindow {
  static final ValueNotifier<bool> fullscreen = ValueNotifier(false);
  static const _channel = MethodChannel('bobine/window');

  static Future<void> setFullscreen(bool value) async {
    if (value == fullscreen.value) return;
    if (value) {
      await defaultEnterNativeFullscreen();
    } else {
      await defaultExitNativeFullscreen();
    }
    fullscreen.value = value;
  }

  static Future<void> toggle() => setFullscreen(!fullscreen.value);

  /// Whether the floating video window above other apps is available.
  static bool get canFloat => !kIsWeb && Platform.isWindows;

  /// Small borderless window, always on top, in a corner of the screen.
  /// Returns false when the platform cannot do it.
  static Future<bool> setFloating(bool value) async {
    if (!canFloat) return false;
    if (value && fullscreen.value) await setFullscreen(false);
    try {
      return await _channel.invokeMethod<bool>('setFloating', value) ?? false;
    } on PlatformException catch (e) {
      debugPrint('setFloating failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Moves the floating window with the mouse (call on pointer down).
  static Future<void> startDrag() async {
    if (!canFloat) return;
    try {
      await _channel.invokeMethod<void>('startDrag');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}
