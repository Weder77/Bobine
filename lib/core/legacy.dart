import 'dart:io';

import 'package:path/path.dart' as p;

/// Folders where the app kept its data when it was called Lumen, worked out
/// from Bobine's own data folder [support].
List<String> legacyDataDirs(String support) {
  final parent = p.dirname(support);
  return [
    // Windows: %APPDATA%\com.bobine\Bobine  <-  %APPDATA%\com.lumen\Lumen
    p.join(p.dirname(parent), 'com.lumen', 'Lumen'),
    // Linux / macOS: …/com.bobine.bobine  <-  …/com.lumen.lumen
    p.join(parent, 'com.lumen.lumen'),
  ];
}

/// The database to open. The first time Bobine starts after Lumen, Lumen's
/// database (sources, profiles, favourites, progress) and log are moved into
/// Bobine's folder. The database itself moves last, so an interrupted move
/// is finished at the next start. If it cannot be moved, Lumen's file is
/// opened where it is: nothing is ever lost.
Future<String> resolveDatabase(String support, {List<String>? legacyDirs}) async {
  final target = p.join(support, 'bobine.db');
  if (File(target).existsSync()) return target;
  for (final dir in legacyDirs ?? legacyDataDirs(support)) {
    final old = File(p.join(dir, 'lumen.db'));
    if (!old.existsSync()) continue;
    try {
      for (final (from, to) in const [
        ('lumen.db-wal', 'bobine.db-wal'),
        ('lumen.db-shm', 'bobine.db-shm'),
        ('lumen.log', 'bobine.log'),
        ('lumen.db', 'bobine.db'),
      ]) {
        final f = File(p.join(dir, from));
        if (f.existsSync()) await _move(f, p.join(support, to));
      }
      return target;
    } catch (_) {
      return old.path;
    }
  }
  return target;
}

Future<void> _move(File f, String to) async {
  try {
    await f.rename(to);
  } on FileSystemException {
    // Another drive: copy, then remove the original.
    await f.copy(to);
    await f.delete();
  }
}
