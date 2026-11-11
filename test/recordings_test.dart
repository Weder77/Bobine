import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/recording_service.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bobine_rec'));
  tearDown(() => tmp.deleteSync(recursive: true));

  (Repository, int) fixture() {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s/list.m3u');
    return (repo, src);
  }

  int add(Repository repo, int src, String title, {String? file, RecordingStatus? status, int bytes = 0}) {
    final now = DateTime.now();
    final id = repo.addRecording(
      sourceId: src,
      channelExt: 'c',
      channelName: 'Chaîne',
      title: title,
      start: now.subtract(const Duration(minutes: 30)),
      stop: now.add(const Duration(hours: 1)),
    );
    String? path;
    if (file != null) {
      path = '${tmp.path}/$file';
      File(path).writeAsBytesSync(List.filled(bytes, 0));
    }
    if (status != null) repo.updateRecording(id, status: status, path: path);
    return id;
  }

  test('a recording cut by closing the app can still be watched', () async {
    final (repo, src) = fixture();
    final long = add(repo, src, 'Long', file: 'long.ts', status: RecordingStatus.recording, bytes: 200 * 1024);
    final empty = add(repo, src, 'Vide', file: 'vide.ts', status: RecordingStatus.recording, bytes: 10);
    final rec = RecordingService(repo, AppSettings(repo), onChanged: () {});
    await rec.dispose();
    expect(repo.recording(long)!.status, RecordingStatus.done);
    expect(repo.recording(long)!.error, contains('Partiel'));
    expect(repo.recording(long)!.size, 200 * 1024);
    expect(repo.recording(empty)!.status, RecordingStatus.failed);
  });

  test('deleting a source keeps the recordings made, not those to come', () {
    final (repo, src) = fixture();
    final made = add(repo, src, 'Fait', file: 'fait.ts', status: RecordingStatus.done, bytes: 10);
    final later = add(repo, src, 'Prévu');
    repo.deleteSource(src);
    expect(repo.recording(made), isNotNull);
    expect(repo.recording(later), isNull);
  });

  test('a change put off by a busy database goes to the profile it was made for', () async {
    final path = '${tmp.path}/busy.db';
    final repo = Repository(openAppDatabase(path));
    addTearDown(repo.db.close);
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s/list.m3u');
    final lea = repo.createProfile(name: 'Léa', color: 1);
    final other = sqlite3.open(path);
    addTearDown(other.close);
    other.execute('BEGIN IMMEDIATE'); // an import writing

    repo.profileId = lea;
    repo.toggleFavorite(src, ContentKind.movie, 'film');
    expect(repo.db.select('SELECT 1 FROM favorites'), isEmpty); // put off
    repo.profileId = 1; // another profile chosen meanwhile
    other.execute('COMMIT');
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(repo.db.select('SELECT profile_id FROM favorites').map((r) => r['profile_id']), [lea]);
    expect(repo.profileId, 1);
  });
}
