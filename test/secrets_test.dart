import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/secrets.dart';
import 'package:lumen/data/db.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/data/repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('plain values pass through and legacy values stay readable', () {
    expect(Secrets.protect(null), isNull);
    expect(Secrets.protect(''), '');
    expect(Secrets.reveal('plain-value'), 'plain-value');
    if (!Secrets.supported) expect(Secrets.protect('s3cr3t'), 's3cr3t');
  });

  test('DPAPI round trip (Windows)', () {
    final enc = Secrets.protect('mot de passe é€ 123')!;
    expect(enc, startsWith(Secrets.prefix));
    expect(enc, isNot(contains('123')));
    expect(Secrets.reveal(enc), 'mot de passe é€ 123');
    expect(Secrets.protect(enc), enc, reason: 'already protected values are not re-encrypted');
  }, skip: Secrets.supported ? false : 'DPAPI only exists on Windows');

  test('credentials are encrypted in the database (Windows)', () {
    final dir = Directory.systemTemp.createTempSync('lumen_secrets');
    final path = '${dir.path}/s.db';
    // A legacy row written in clear by an older version.
    openAppDatabase(path).close();
    final raw = sqlite3.open(path);
    raw.execute(
      "INSERT INTO sources (name, type, url, username, password, created_at) "
      "VALUES ('old', 'xtream', 'http://srv:8080', 'bob', 'hunter2', 0)",
    );
    raw.close();

    final repo = Repository(openAppDatabase(path)); // migrates legacy secrets
    final id = repo.insertSource(name: 'new', type: SourceType.m3u, url: 'http://srv/get.php?username=a&password=b');
    final stored = repo.db.select('SELECT url, password FROM sources ORDER BY id');
    expect(stored[0]['password'], startsWith(Secrets.prefix));
    expect(stored[1]['url'], startsWith(Secrets.prefix));
    expect(repo.sources().first.password, 'hunter2');
    expect(repo.source(id)!.url, 'http://srv/get.php?username=a&password=b');
    repo.db.close();
  }, skip: Secrets.supported ? false : 'DPAPI only exists on Windows');
}
