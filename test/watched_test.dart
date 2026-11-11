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
}
