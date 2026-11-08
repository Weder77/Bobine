import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/version.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AppLog.add('Bobine $kAppVersion démarre');
  try {
    final services = await AppServices.create();
    runApp(BobineApp(services: services));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      services.refreshStaleSources();
      services.sync.start();
      // A little later: the update check must not slow the first screens.
      Future.delayed(const Duration(seconds: 8), services.updates.checkInBackground);
    });
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(error: e.toString()));
  }
}
