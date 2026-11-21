import 'dart:io';

import 'package:flutter/services.dart';

/// Leaving Bobine from its first screen (Retour on Accueil).
///
/// On Android, Bobine goes behind (as with Home) rather than finishing:
/// it comes back at once, and the video player, whose threads outlive a
/// finished screen, is never started a second time in the same process.
class AppExit {
  static const _channel = MethodChannel('bobine/app');

  static Future<void> leave() async {
    if (Platform.isAndroid) {
      try {
        if (await _channel.invokeMethod<bool>('toBackground') ?? false) return;
      } on PlatformException {
        // Finishing, then.
      } on MissingPluginException {
        // Finishing, then.
      }
    }
    await SystemNavigator.pop();
  }
}
