import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    final services = await AppServices.create();
    runApp(LumenApp(services: services));
    WidgetsBinding.instance.addPostFrameCallback((_) => services.refreshStaleSources());
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(error: e.toString()));
  }
}
