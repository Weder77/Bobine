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
}
