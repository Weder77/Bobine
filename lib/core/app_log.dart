import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'text.dart';

/// Keeps the last messages of the app (debugPrint, Flutter and uncaught
/// errors) for the diagnostic page, and in `bobine.log` next to the database.
/// Credentials are masked before anything is kept.
class AppLog {
  static const _max = 400;
  static final _lines = ListQueue<String>();
  static IOSink? _file;
  static String? _path;
  static int _written = 0;

  /// The log file is started again past this size (the previous one kept as
  /// `bobine.log.1`), during the session too: it grew without bound.
  static const maxFileBytes = 1 << 20;

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
      final out = '${t.toIso8601String().substring(0, 10)} $line';
      _file?.writeln(out);
      _written += out.length + 1;
      if (_written > maxFileBytes) _rotate();
    } catch (_) {}
  }

  static void _rotate() {
    final path = _path, old = _file;
    if (path == null || old == null) return;
    _file = null;
    _written = 0;
    unawaited(() async {
      try {
        await old.flush();
        await old.close();
        File(path).renameSync('$path.1');
      } catch (_) {}
      try {
        _file = File(path).openWrite(mode: FileMode.append);
      } catch (_) {}
    }());
  }

  /// Writes what is waiting to `bobine.log` (the app is closing).
  static Future<void> flush() async {
    try {
      await _file?.flush();
    } catch (_) {}
  }

  /// Routes debugPrint and errors here; [logPath] receives a copy (rotated at 1 MB).
  static void install({String? logPath}) {
    if (logPath != null) {
      try {
        final f = File(logPath);
        if (f.existsSync() && f.lengthSync() > maxFileBytes) f.renameSync('$logPath.1');
        _path = logPath;
        _written = f.existsSync() ? f.lengthSync() : 0;
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
