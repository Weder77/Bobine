import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/core/legacy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('bobine_legacy'));
  tearDown(() => root.deleteSync(recursive: true));

  test('Windows and Linux folders of the former name are found', () {
    final win = legacyDataDirs(p.join('C:', 'Users', 'me', 'AppData', 'Roaming', 'com.bobine', 'Bobine'));
    expect(win.first, p.join('C:', 'Users', 'me', 'AppData', 'Roaming', 'com.lumen', 'Lumen'));
    // Built with the platform's separator, like the real folders.
    final linux = legacyDataDirs(p.join('home', 'me', '.local', 'share', 'com.bobine.bobine'));
    expect(linux.last, p.join('home', 'me', '.local', 'share', 'com.lumen.lumen'));
  });

  test("Lumen's database, WAL and log move into Bobine's folder once", () async {
    final old = Directory(p.join(root.path, 'com.lumen', 'Lumen'))..createSync(recursive: true);
    final neu = Directory(p.join(root.path, 'com.bobine', 'Bobine'))..createSync(recursive: true);
    File(p.join(old.path, 'lumen.db')).writeAsStringSync('db');
    File(p.join(old.path, 'lumen.db-wal')).writeAsStringSync('wal');
    File(p.join(old.path, 'lumen.log')).writeAsStringSync('log');

    final path = await resolveDatabase(neu.path);
    expect(path, p.join(neu.path, 'bobine.db'));
    expect(File(path).readAsStringSync(), 'db');
    expect(File(p.join(neu.path, 'bobine.db-wal')).readAsStringSync(), 'wal');
    expect(File(p.join(neu.path, 'bobine.log')).existsSync(), isTrue);
    expect(File(p.join(old.path, 'lumen.db')).existsSync(), isFalse);

    // Later starts keep Bobine's database, even if a Lumen one shows up again.
    File(p.join(old.path, 'lumen.db')).writeAsStringSync('other');
    expect(await resolveDatabase(neu.path), p.join(neu.path, 'bobine.db'));
    expect(File(p.join(neu.path, 'bobine.db')).readAsStringSync(), 'db');
  });

  test('a fresh install starts with an empty folder', () async {
    final neu = Directory(p.join(root.path, 'com.bobine', 'Bobine'))..createSync(recursive: true);
    expect(await resolveDatabase(neu.path), p.join(neu.path, 'bobine.db'));
  });
}
