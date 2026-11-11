import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/version.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.add('Bobine $kAppVersion démarre');
  try {
    // Inside: without libmpv (a missing or blocked library) the window
    // stayed empty instead of saying so.
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      debugPrint('libmpv: $e');
      runApp(StartupErrorApp(error: 'Le lecteur vidéo (libmpv) ne peut pas être chargé : $e'));
      return;
    }
    final services = await AppServices.create();
    runApp(BobineApp(services: services));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      services.startRefreshing();
      services.sync.start();
      // A little later: the update check must not slow the first screens.
      Future.delayed(const Duration(seconds: 8), services.updates.checkInBackground);
    });
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(error: e.toString()));
  }
}
