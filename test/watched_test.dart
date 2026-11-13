import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';

void main() {
  test('marking as seen leaves "Reprendre", unseen forgets it', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    repo.saveProgress(
      sourceId: src,
      kind: ContentKind.movie,
      extId: '7',
      position: const Duration(minutes: 20),
      duration: const Duration(minutes: 100),
      title: 'Le Phare',
      image: 'poster.png',
    );
    expect(repo.continueWatching(src).map((p) => p.extId), ['7']);

    repo.setWatched(src, ContentKind.movie, '7', seen: true, title: 'ignored');
    final p = repo.progress(src, ContentKind.movie, '7')!;
    expect(p.finished, isTrue);
    expect(p.title, 'Le Phare'); // what was known is kept
    expect(p.image, 'poster.png');
    expect(repo.continueWatching(src), isEmpty);

    // Never started: still marked as seen.
    repo.setWatched(src, ContentKind.movie, '8', seen: true, title: 'Brume');
    expect(repo.progress(src, ContentKind.movie, '8')!.finished, isTrue);

    repo.setWatched(src, ContentKind.movie, '8', seen: false, title: 'Brume');
    expect(repo.progress(src, ContentKind.movie, '8'), isNull);
  });

  test('"Reprendre" offers where a series was left, not an older episode stopped at the credits', () async {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    Future<void> watch(String ext, int minutes, {String series = 'lupin'}) async {
      repo.saveProgress(
        sourceId: src,
        kind: ContentKind.episode,
        extId: ext,
        position: Duration(minutes: minutes),
        duration: const Duration(minutes: 45),
        title: 'Ep $ext',
        seriesExt: series,
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }

    await watch('e1', 38); // left at the credits (84 %): not finished
    await watch('e2', 45);
    await watch('e3', 45);
    expect(repo.continueWatching(src), isEmpty, reason: 'the series was watched up to e3, to its end');

    await watch('e4', 12);
    expect(repo.continueWatching(src).map((p) => p.extId), ['e4']);

    // One entry per series, films alongside, newest first; the limit holds.
    await watch('x1', 20, series: 'dark');
    repo.saveProgress(
      sourceId: src,
      kind: ContentKind.movie,
      extId: 'm1',
      position: const Duration(minutes: 30),
      duration: const Duration(minutes: 100),
      title: 'Film',
    );
    expect(repo.continueWatching(src).map((p) => p.extId), ['m1', 'x1', 'e4']);
    expect(repo.continueWatching(src, limit: 2), hasLength(2));
  });

  group('a series watched to the end of an episode', () {
    late Repository repo;
    late int src;
    setUp(() {
      repo = Repository(openMemoryDatabase());
      src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
      repo.replaceEpisodes(src, 'gent', [
        for (var n = 1; n <= 5; n++)
          Episode(
            sourceId: src,
            seriesExt: 'gent',
            extId: 'g$n',
            season: 2,
            episode: n,
            title: 'Titre $n',
            image: n == 4 ? 'still4.jpg' : null,
            durationSec: 3300,
          ),
      ]);
    });

    Future<void> watch(String ext, Duration at) async {
      repo.saveProgress(
        sourceId: src,
        kind: ContentKind.episode,
        extId: ext,
        position: at,
        duration: const Duration(minutes: 55),
        title: 'Les Gentlemen (2024)',
        subtitle: 'S02E0${ext.substring(1)} · Titre',
        image: 'show.jpg',
        seriesExt: 'gent',
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }

    test('"Reprendre" offers the next episode, from its start', () async {
      await watch('g2', const Duration(minutes: 55));
      await watch('g3', const Duration(minutes: 55));
      final next = repo.continueWatching(src).single;
      expect(next.extId, 'g4');
      expect(next.upNext, isTrue);
      expect(next.finished, isFalse);
      expect(next.position, Duration.zero);
      expect(next.duration, const Duration(seconds: 3300));
      expect(next.title, 'Les Gentlemen (2024)');
      expect(next.subtitle, 'S02E04 · Titre 4');
      expect(next.image, 'still4.jpg');
      expect(next.seriesExt, 'gent');
      expect(next.resumable, isFalse);

      // The next episode barely started (auto-play, then closed): still offered.
      await watch('g4', const Duration(seconds: 10));
      expect(repo.continueWatching(src).single.extId, 'g4');

      // Under way: resumed where it was left.
      await watch('g4', const Duration(minutes: 12));
      final resume = repo.continueWatching(src).single;
      expect(resume.extId, 'g4');
      expect(resume.upNext, isFalse);
      expect(resume.position, const Duration(minutes: 12));

      // Marked as seen: the series moves on.
      repo.setWatched(src, ContentKind.episode, 'g4', seen: true, title: 'x');
      expect(repo.continueWatching(src).single.extId, 'g5');

      // The last episode seen: nothing left to offer.
      await watch('g5', const Duration(minutes: 55));
      expect(repo.continueWatching(src), isEmpty);
    });

    test('taken out of "Reprendre", it stays out until watched again', () async {
      await watch('g3', const Duration(minutes: 55));
      final next = repo.continueWatching(src).single;
      repo.removeFromResume(next);
      expect(repo.continueWatching(src), isEmpty);
      // The episode before is still seen.
      expect(repo.progress(src, ContentKind.episode, 'g3')!.finished, isTrue);
      // Nothing to resume in the series page either: its next episode starts.
      expect(repo.lastEpisodeProgress(src, 'gent')!.resumable, isFalse);

      await watch('g4', const Duration(minutes: 12));
      expect(repo.continueWatching(src).single.extId, 'g4');

      // An episode under way taken out does not bring back the one after the
      // episode before.
      repo.removeFromResume(repo.continueWatching(src).single);
      expect(repo.continueWatching(src), isEmpty);
    });

    test('episodes not known here (Xtream refresh): the series is named to load them', () async {
      final xt = repo.insertSource(name: 'X', type: SourceType.xtream, url: 'http://x', username: 'u', password: 'p');
      repo.db.execute(
        "INSERT INTO series (source_id, ext_id, name, search, position) VALUES (?, 'other', 'Autre', 'autre', 0)",
        [xt],
      );
      void finish(String ext, String series) => repo.saveProgress(
        sourceId: xt,
        kind: ContentKind.episode,
        extId: ext,
        position: const Duration(minutes: 55),
        duration: const Duration(minutes: 55),
        title: series,
        seriesExt: series,
      );
      finish('a3', 'other');
      // Watched, then no longer listed by the provider: nothing to ask.
      finish('z1', 'gone');
      var r = repo.continueWatchingWithPending(xt);
      expect(r.entries, isEmpty);
      expect(r.pendingSeries, ['other']);

      repo.replaceEpisodes(xt, 'other', [
        for (var n = 3; n <= 4; n++) Episode(sourceId: xt, seriesExt: 'other', extId: 'a$n', season: 1, episode: n),
      ]);
      r = repo.continueWatchingWithPending(xt);
      expect(r.entries.single.extId, 'a4');
      expect(r.pendingSeries, isEmpty);

      // An M3U source brings its episodes with the list: nothing to ask.
      await watch('g5', const Duration(minutes: 55));
      repo.replaceEpisodes(src, 'gent', const []);
      expect(repo.continueWatchingWithPending(src).pendingSeries, isEmpty);
    });
  });

  test('the next episode follows the season order', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    Episode ep(String ext, int season, int n) =>
        Episode(sourceId: src, seriesExt: 'z', extId: ext, season: season, episode: n);
    // Stored out of order on purpose.
    repo.replaceEpisodes(src, 'z', [ep('s2e1', 2, 1), ep('s1e2', 1, 2), ep('s1e1', 1, 1), ep('s1e10', 1, 10)]);
    expect(repo.nextEpisode(src, 'z', 's1e1')?.extId, 's1e2');
    expect(repo.nextEpisode(src, 'z', 's1e2')?.extId, 's1e10');
    expect(repo.nextEpisode(src, 'z', 's1e10')?.extId, 's2e1');
    expect(repo.nextEpisode(src, 'z', 's2e1'), isNull);
    expect(repo.nextEpisode(src, 'z', 'unknown'), isNull);
  });
}
