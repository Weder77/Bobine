import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/core/text.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/features/recording_service.dart';

/// A source with two live categories (one adult-looking), three channels and
/// a small guide.
(Repository, int) _fixture() {
  final repo = Repository(openMemoryDatabase());
  final id = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
  final db = repo.db;
  db.execute(
    "INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (10, ?, 'live', 'fr', 'France', 0)",
    [id],
  );
  db.execute(
    "INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (11, ?, 'live', 'xx', 'Adultes 18+', 1)",
    [id],
  );
  db.execute(
    "INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (12, ?, 'live', 'sp', 'Sport', 2)",
    [id],
  );
  void ch(String ext, int cat, String name, String epg, int pos) => db.execute(
    'INSERT INTO channels (source_id, ext_id, category_id, name, search, epg_id, match_key, position) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [id, ext, cat, name, searchKey(name), epg, channelMatchKey(name), pos],
  );
  ch('a', 10, 'Info 24', 'info24.fr', 0);
  ch('b', 11, 'Late Night', 'late.xx', 1);
  ch('c', 12, 'Sport Max', 'sport.fr', 2);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  void prog(String channel, int start, int stop, String title) => db.execute(
    'INSERT INTO epg_programs (source_id, channel, start, stop, title, search) VALUES (?, ?, ?, ?, ?, ?)',
    [id, channel, start, stop, title, searchKey(title)],
  );
  prog('info24.fr', now - 3600, now - 60, 'Le Journal du matin');
  prog('info24.fr', now + 3600, now + 7200, 'Le Journal du soir');
  prog('sport.fr', now + 600, now + 6000, 'Football : Lyon - Marseille');
  return (repo, id);
}

void main() {
  test('hidden categories and channels disappear from lists, counts and search', () {
    final (repo, id) = _fixture();
    expect(repo.channels(id).map((c) => c.extId), ['a', 'b', 'c']);
    repo.setCategoryHidden(id, ContentKind.live, 'sp', true);
    expect(repo.channels(id).map((c) => c.extId), ['a', 'b']);
    expect(repo.categories(id, ContentKind.live).map((c) => c.extId), ['fr', 'xx']);
    expect(repo.categories(id, ContentKind.live, includeHidden: true).map((c) => c.extId), ['fr', 'xx', 'sp']);
    expect(repo.count(id, ContentKind.live), 2);
    repo.setChannelHidden(id, 'a', true);
    expect(repo.channels(id).map((c) => c.extId), ['b']);
    expect(repo.search(id, 'info').channels, isEmpty);
    expect(repo.hiddenChannels(id).single.extId, 'a');
  });

  test('locked categories are left out only when the code is required', () {
    final (repo, id) = _fixture();
    expect(repo.autoLockAdult(id), 1);
    expect(repo.categories(id, ContentKind.live).firstWhere((c) => c.extId == 'xx').locked, isTrue);
    expect(repo.channels(id).length, 3);
    repo.hideLocked = true;
    expect(repo.channels(id).map((c) => c.extId), ['a', 'c']);
    expect(repo.categories(id, ContentKind.live).map((c) => c.extId), ['fr', 'sp']);
    // A decision the user made is kept on the next import.
    repo.setCategoryLocked(id, ContentKind.live, 'xx', false);
    expect(repo.autoLockAdult(id), 0);
    expect(repo.channels(id).length, 3);
  });

  test('locked content stays out of "Reprendre" and is refused by id while the code is required', () {
    final (repo, id) = _fixture();
    final db = repo.db;
    for (final (cid, kind, ext) in [
      (20, 'movie', 'mf'),
      (21, 'movie', 'mx'),
      (30, 'series', 'sf'),
      (31, 'series', 'sx'),
    ]) {
      db.execute('INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (?, ?, ?, ?, ?, 0)', [
        cid,
        id,
        kind,
        ext,
        ext.endsWith('x') ? 'Adultes' : 'Famille',
      ]);
    }
    void movie(String ext, int cat) => db.execute(
      'INSERT INTO movies (source_id, ext_id, category_id, name, search, position) VALUES (?, ?, ?, ?, ?, 0)',
      [id, ext, cat, 'Film $ext', 'film $ext'],
    );
    void series(String ext, int cat) => db.execute(
      'INSERT INTO series (source_id, ext_id, category_id, name, search, position) VALUES (?, ?, ?, ?, ?, 0)',
      [id, ext, cat, 'Série $ext', 'serie $ext'],
    );
    movie('family', 20);
    movie('adult', 21);
    series('show', 30);
    series('xshow', 31);
    db.execute(
      'INSERT INTO episodes (source_id, series_ext, ext_id, season, episode, title) VALUES (?, ?, ?, 1, 1, ?)',
      [id, 'xshow', 'xe1', 'Pilote'],
    );
    void watched(ContentKind kind, String ext, {String? seriesExt}) => repo.saveProgress(
      sourceId: id,
      kind: kind,
      extId: ext,
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 90),
      title: ext,
      seriesExt: seriesExt,
    );
    watched(ContentKind.movie, 'family');
    watched(ContentKind.movie, 'adult');
    watched(ContentKind.episode, 'e1', seriesExt: 'show');
    watched(ContentKind.episode, 'xe1', seriesExt: 'xshow');
    // A film the provider no longer lists: nothing to protect.
    watched(ContentKind.movie, 'gone');
    repo.setCategoryLocked(id, ContentKind.movie, 'mx', true);
    repo.setCategoryLocked(id, ContentKind.series, 'sx', true);
    repo.setCategoryLocked(id, ContentKind.live, 'xx', true);

    // The code was typed: everything is there.
    Set<String> resume() => repo.continueWatching(id).map((p) => p.extId).toSet();
    expect(resume(), {'family', 'adult', 'e1', 'xe1', 'gone'});
    expect(repo.isLocked(id, ContentKind.movie, 'adult'), isFalse);

    repo.hideLocked = true;
    expect(resume(), {'family', 'e1', 'gone'});
    expect(repo.isLocked(id, ContentKind.movie, 'adult'), isTrue);
    expect(repo.isLocked(id, ContentKind.movie, 'family'), isFalse);
    expect(repo.isLocked(id, ContentKind.series, 'xshow'), isTrue);
    expect(repo.isLocked(id, ContentKind.episode, 'xe1', seriesExt: 'xshow'), isTrue);
    // Without its series: found through the episode.
    expect(repo.isLocked(id, ContentKind.episode, 'xe1'), isTrue);
    expect(repo.isLocked(id, ContentKind.episode, 'e1', seriesExt: 'show'), isFalse);
    expect(repo.isLocked(id, ContentKind.live, 'b'), isTrue);
    expect(repo.isLocked(id, ContentKind.live, 'a'), isFalse);
    expect(repo.isLocked(id, ContentKind.movie, 'gone'), isFalse);
    // Hiding a category tidies up, it does not lock.
    repo.setCategoryHidden(id, ContentKind.movie, 'mf', true);
    expect(repo.isLocked(id, ContentKind.movie, 'family'), isFalse);
    expect(resume(), contains('family'));
  });

  test('categories follow the order the user chose', () {
    final (repo, id) = _fixture();
    repo.setCategoryOrder(id, ContentKind.live, ['sp', 'fr', 'xx']);
    expect(repo.categories(id, ContentKind.live).map((c) => c.extId), ['sp', 'fr', 'xx']);
    repo.resetCategoryOrder(id, ContentKind.live);
    expect(repo.categories(id, ContentKind.live).map((c) => c.extId), ['fr', 'xx', 'sp']);
  });

  test('reminders toggle per profile', () {
    final (repo, id) = _fixture();
    final channel = repo.channelByExt(id, 'c')!;
    final now = DateTime.now();
    final p = Program(
      start: now.add(const Duration(minutes: 10)),
      stop: now.add(const Duration(hours: 1)),
      title: 'Match',
    );
    expect(repo.toggleReminder(channel, p), isTrue);
    expect(repo.hasReminder(id, 'c', p.start), isTrue);
    expect(repo.reminders().single.title, 'Match');
    repo.profileId = repo.createProfile(name: 'Léa', color: 1);
    expect(repo.reminders(), isEmpty);
    repo.profileId = 1;
    expect(repo.toggleReminder(channel, p), isFalse);
    expect(repo.reminders(), isEmpty);
  });

  test('recordings are stored and updated', () {
    final (repo, id) = _fixture();
    final now = DateTime.now();
    final rid = repo.addRecording(
      sourceId: id,
      channelExt: 'c',
      channelName: 'Sport Max',
      title: 'Match',
      start: now,
      stop: now.add(const Duration(hours: 2)),
    );
    expect(repo.hasRecording(id, 'c', now), isTrue);
    repo.updateRecording(rid, status: RecordingStatus.done, path: '/tmp/match.mkv', size: 42);
    final r = repo.recording(rid)!;
    expect(r.status, RecordingStatus.done);
    expect(r.path, '/tmp/match.mkv');
    expect(repo.hasRecording(id, 'c', now), isFalse);
  });

  test('a channel being recorded is known whatever started the recording', () {
    final (repo, id) = _fixture();
    final now = DateTime.now();
    expect(repo.isRecordingAt(id, 'c', now), isFalse);
    // "Enregistrer" on a programme on air: the recording starts now.
    final rid = repo.addRecording(
      sourceId: id,
      channelExt: 'c',
      channelName: 'Sport Max',
      title: 'Match',
      start: now.subtract(const Duration(seconds: 5)),
      stop: now.add(const Duration(hours: 1)),
    );
    expect(repo.isRecordingAt(id, 'c', now), isTrue);
    expect(repo.isRecordingAt(id, 'a', now), isFalse);
    expect(repo.isRecordingAt(id, 'c', now.add(const Duration(hours: 2))), isFalse);
    repo.updateRecording(rid, status: RecordingStatus.done);
    expect(repo.isRecordingAt(id, 'c', now), isFalse);
  });

  test('two recordings of the same name do not share a file', () {
    final taken = <String>{};
    String next() {
      final path = freeFilePath('/videos', 'TF1 - Le journal - 2026-11-09 20h00', 'ts', exists: taken.contains);
      taken.add(path);
      return path;
    }

    expect(next(), endsWith('TF1 - Le journal - 2026-11-09 20h00.ts'));
    expect(next(), endsWith('TF1 - Le journal - 2026-11-09 20h00 (2).ts'));
    expect(next(), endsWith('TF1 - Le journal - 2026-11-09 20h00 (3).ts'));
    expect(taken, hasLength(3));
  });

  test('channels on air: every quality of the channel, by tvg-id or by name, hidden ones left out', () {
    final (repo, id) = _fixture();
    final db = repo.db;
    final now = DateTime.now();
    DateTime at(int seconds) => now.add(Duration(seconds: seconds));
    // Nothing matching is on air now; the football starts in 10 minutes.
    expect(repo.channelsOnAir(id, 'journal'), isEmpty);
    expect(repo.channelsOnAir(id, 'marseille', at: at(700)), {'c'});
    expect(repo.channelsOnAir(id, 'journal', at: at(3700)), {'a'});
    // A second quality with the same tvg-id, and a channel matched by its name.
    db.execute(
      'INSERT INTO channels (source_id, ext_id, category_id, name, search, epg_id, match_key, position) '
      "VALUES (?, 'a2', 10, 'Info 24 HD', 'info 24 hd', 'INFO24.fr', 'info24', 3)",
      [id],
    );
    db.execute(
      'INSERT INTO channels (source_id, ext_id, category_id, name, search, epg_id, match_key, position) '
      "VALUES (?, 'd', 10, 'FR: Info 24', 'fr info 24', NULL, 'info24', 4)",
      [id],
    );
    db.execute("INSERT INTO epg_channels (source_id, name_key, epg_id) VALUES (?, 'info24', 'info24.fr')", [id]);
    expect(repo.channelsOnAir(id, 'JOURNAL soir', at: at(3700)), {'a', 'a2', 'd'});
    expect(repo.channelsOnAir(id, 'journal matin', at: at(3700)), isEmpty);
    repo.setChannelHidden(id, 'a2', true);
    expect(repo.channelsOnAir(id, 'journal', at: at(3700)), {'a', 'd'});
    repo.setCategoryHidden(id, ContentKind.live, 'fr', true);
    expect(repo.channelsOnAir(id, 'journal', at: at(3700)), isEmpty);
    expect(repo.channelsOnAir(id, '  '), isEmpty);
  });

  test('the guide search gives the first channel of the list for a programme, and only visible ones', () {
    final (repo, id) = _fixture();
    final db = repo.db;
    // Another quality of Info 24, earlier in the list.
    db.execute(
      'INSERT INTO channels (source_id, ext_id, category_id, name, search, epg_id, match_key, position) '
      "VALUES (?, 'a0', 10, 'Info 24 FHD', 'info 24 fhd', 'info24.fr', 'info24', -1)",
      [id],
    );
    // A guide channel no channel of the playlist uses.
    db.execute('INSERT INTO epg_programs (source_id, channel, start, stop, title, search) VALUES (?, ?, ?, ?, ?, ?)', [
      id,
      'ailleurs.tv',
      0,
      9999999999,
      'Le Journal d ailleurs',
      'le journal d ailleurs',
    ]);
    final hits = repo.searchPrograms(id, 'journal');
    expect(hits.map((h) => h.channel.extId).toSet(), {'a0'});
    expect(hits, hasLength(2));
    repo.setChannelHidden(id, 'a0', true);
    expect(repo.searchPrograms(id, 'journal').map((h) => h.channel.extId).toSet(), {'a'});
    expect(repo.searchPrograms(id, 'journal', limit: 1), hasLength(1));
  });

  test('the guide search finds programmes with their channel, without accents', () {
    final (repo, id) = _fixture();
    final hits = repo.searchPrograms(id, 'journal');
    expect(hits.map((h) => h.program.title), ['Le Journal du soir', 'Le Journal du matin']);
    expect(hits.first.channel.name, 'Info 24');
    expect(repo.searchPrograms(id, 'marseille lyon').single.channel.extId, 'c');
    repo.setCategoryHidden(id, ContentKind.live, 'sp', true);
    expect(repo.searchPrograms(id, 'marseille'), isEmpty);
  });
}
