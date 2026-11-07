import 'dart:io';

/// Opens [url] (web page or folder) with the system's default app.
Future<bool> openExternal(String url) async {
  try {
    final ProcessResult r;
    if (Platform.isWindows) {
      // "start" treats the first quoted argument as a window title.
      r = await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      r = await Process.run('open', [url]);
    } else {
      r = await Process.run('xdg-open', [url]);
    }
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
