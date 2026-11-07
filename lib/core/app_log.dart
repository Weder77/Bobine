import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'text.dart';

/// Keeps the last messages of the app (debugPrint, Flutter and uncaught
/// errors) for the diagnostic page, and in `lumen.log` next to the database.
/// Credentials are masked before anything is kept.
class AppLog {
  static const _max = 400;
  static final _lines = ListQueue<String>();
  static IOSink? _file;

  static List<String> get lines => List.unmodifiable(_lines);

  static void add(String message) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)} ${redactCredentials(message)}';
    _lines.addLast(line);
    while (_lines.length > _max) {
      _lines.removeFirst();
    }
    try {
      _file?.writeln('${t.toIso8601String().substring(0, 10)} $line');
    } catch (_) {}
  }

  /// Routes debugPrint and errors here; [logPath] receives a copy (rotated at 1 MB).
  static void install({String? logPath}) {
    if (logPath != null) {
      try {
        final f = File(logPath);
        if (f.existsSync() && f.lengthSync() > 1 << 20) f.renameSync('$logPath.1');
        _file = f.openWrite(mode: FileMode.append);
      } catch (_) {}
    }
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      original(message, wrapWidth: wrapWidth);
    };
    final flutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      add('Erreur Flutter : ${details.exceptionAsString()}\n${details.stack ?? ''}'.trim());
      flutterHandler?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      add('Erreur : $error\n$stack');
      return false;
    };
  }
}
