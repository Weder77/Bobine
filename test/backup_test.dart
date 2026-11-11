import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/backup.dart';

(Repository, AppSettings, BackupService) _install() {
  final repo = Repository(openMemoryDatabase());
  final settings = AppSettings(repo);
  return (repo, settings, BackupService(repo, settings));
}

int _xtream(Repository r, {String name = 'Mon IPTV'}) => r.insertSource(
  name: name,
  type: SourceType.xtream,
  url: 'http://tv.example:8080',
  username: 'bob',
  password: 's3cret',
);

void main() {
  test('a backup with credentials rebuilds sources, profiles and user data elsewhere', () {
    final (a, aSettings, aBackup) = _install();
    final src = _xtream(a);
    final lea = a.createProfile(name: 'Léa', color: 0xFF7FA6FF, kids: true);
    a.toggleFavorite(src, ContentKind.movie, '503');
    a.profileId = lea;
    a.toggleFavorite(src, ContentKind.series, '900');
    a.saveProgress(
      sourceId: src,
      kind: ContentKind.movie,
      extId: '501',
      position: const Duration(minutes: 20),
      duration: const Duration(minutes: 100),
      title: 'Le Phare',
    );
    a.setCategoryHidden(src, ContentKind.live, 'sport', true);
    aSettings.update((s) {
      s.seekStep = 30;
      s.parentalPin = '1234';
    });

    final json = jsonDecode(jsonEncode(aBackup.build(credentials: true))) as Map<String, Object?>;
    final (b, bSettings, bBackup) = _install();
    b.insertSource(name: 'Autre', type: SourceType.m3u, url: 'http://other/list.m3u'); // shifts ids
    final report = bBackup.restore(json);

    expect(report.sourcesCreated, 1);
    expect(report.profilesCreated, 1);
    final restored = b.sources().firstWhere((s) => s.name == 'Mon IPTV');
    expect(restored.password, 's3cret');
    expect(b.isFavorite(restored.id, ContentKind.movie, '503'), isTrue);
    final bLea = b.profiles().firstWhere((p) => p.name == 'Léa');
    expect(bLea.kids, isTrue);
    b.profileId = bLea.id;
    expect(b.isFavorite(restored.id, ContentKind.series, '900'), isTrue);
    expect(b.progress(restored.id, ContentKind.movie, '501')!.position, const Duration(minutes: 20));
    expect(b.categories(restored.id, ContentKind.live, includeHidden: true), isEmpty); // no content imported yet
    expect(b.db.select('SELECT hidden FROM category_prefs WHERE source_id = ?', [restored.id]).single['hidden'], 1);
    expect(bSettings.seekStep, 30);
    expect(bSettings.parentalPin, '1234');
  });

  test('without credentials nothing secret is written and sources are found again', () {
    final (a, aSettings, aBackup) = _install();
    final src = _xtream(a);
    a.toggleFavorite(src, ContentKind.live, '100');
    aSettings.update((s) {
      s.tmdbKey = 'k';
      s.parentalPin = '1234';
    });
    final text = jsonEncode(aBackup.build(credentials: false));
    expect(text, isNot(contains('s3cret')));
    expect(text, isNot(contains('tv.example')));
    expect(text, isNot(contains('1234')));
    expect(text, isNot(contains('"tmdbKey"')));

    // Same account, another name and id on the other computer.
    final (b, bSettings, bBackup) = _install();
    b.insertSource(name: 'Autre', type: SourceType.m3u, url: 'http://other/list.m3u');
    final id = _xtream(b, name: 'Salon');
    final report = bBackup.restore(jsonDecode(text) as Map<String, Object?>);
    expect(report.sourcesMatched, 1);
    expect(b.isFavorite(id, ContentKind.live, '100'), isTrue);
    expect(bSettings.parentalPin, isNull);

    // Nowhere to attach the data: skipped, not failed.
    final (_, _, cBackup) = _install();
    final r = cBackup.restore(jsonDecode(text) as Map<String, Object?>);
    expect(r.skippedSources, ['Mon IPTV']);
    expect(r.favorites, 0);
  });

  test('newer progress wins on restore, foreign files are refused', () {
    final (a, _, aBackup) = _install();
    final src = _xtream(a);
    a.saveProgress(
      sourceId: src,
      kind: ContentKind.movie,
      extId: '1',
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 100),
      title: 'X',
    );
    final json = jsonDecode(jsonEncode(aBackup.build(credentials: false))) as Map<String, Object?>;
    a.db.execute('UPDATE progress SET position_ms = ?, updated_at = updated_at + 100', [50 * 60000]);
    aBackup.restore(json);
    expect(a.progress(src, ContentKind.movie, '1')!.position, const Duration(minutes: 50));
    expect(() => aBackup.restore({'format': 'other'}), throwsA(isA<BackupException>()));
    // Saved by Lumen (the former name): still accepted.
    final legacy = {...json, 'format': 'lumen-backup'};
    expect(() => aBackup.restore(legacy), returnsNormally);
  });

  test('a damaged file leaves its bad rows out instead of breaking the app', () {
    final (a, _, aBackup) = _install();
    final src = _xtream(a);
    a.toggleFavorite(src, ContentKind.movie, '7');
    a.saveProgress(
      sourceId: src,
      kind: ContentKind.movie,
      extId: '1',
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 100),
      title: 'X',
    );
    final json = jsonDecode(jsonEncode(aBackup.build(credentials: true))) as Map<String, Object?>;
    final progress = (json['progress'] as List).cast<Map<String, Object?>>();
    progress.add({...progress.single, 'ext_id': '2', 'position_ms': 'abc'});
    (json['favorites'] as List).add({'kind': 'nope', 'ext_id': '8', 'source_id': 1, 'added_at': 1});
    (json['favorites'] as List).add('not a row');
    json['reminders'] = 'not a list';

    final (b, _, bBackup) = _install();
    final report = bBackup.restore(json);
    final restored = b.sources().single;
    expect(b.isFavorite(restored.id, ContentKind.movie, '7'), isTrue);
    expect(b.progress(restored.id, ContentKind.movie, '1'), isNotNull);
    expect(b.progress(restored.id, ContentKind.movie, '2'), isNull);
    expect(report.damaged, 2);
    expect('$report', contains('2 ligne(s) illisible(s)'));

    expect(() => bBackup.restore({...json, 'version': '1'}), throwsA(isA<BackupException>()));
  });
}
