import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Native window fullscreen, through media_kit_video's platform channel
/// (no extra window-management plugin needed).
class AppWindow {
  static final ValueNotifier<bool> fullscreen = ValueNotifier(false);

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
}
