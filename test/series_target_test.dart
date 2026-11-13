import 'package:bobine/data/models.dart';
import 'package:bobine/ui/quick_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final episodes = [
    for (var n = 1; n <= 3; n++) Episode(sourceId: 1, seriesExt: 's', extId: 'e$n', season: 1, episode: n),
  ];
  ProgressEntry at(String ext, Duration position, {bool finished = false, Duration? duration}) => ProgressEntry(
    sourceId: 1,
    kind: ContentKind.episode,
    extId: ext,
    position: position,
    duration: duration ?? const Duration(minutes: 50),
    finished: finished,
    updatedAt: DateTime(2026, 11, 13),
    title: 'Série',
    seriesExt: 's',
  );
  String? label((Episode, bool)? t) => t == null ? null : '${t.$2 ? 'Reprendre' : 'Lecture'} ${t.$1.code}';

  test('the episode to start with, and whether it resumes', () {
    expect(label(seriesTarget(const [], null)), isNull);
    expect(label(seriesTarget(episodes, null)), 'Lecture S01E01');
    expect(label(seriesTarget(episodes, at('e2', const Duration(minutes: 20)))), 'Reprendre S01E02');
    expect(label(seriesTarget(episodes, at('e2', const Duration(minutes: 50), finished: true))), 'Lecture S01E03');
    // Taken out of "Reprendre" (no length): it starts again.
    expect(label(seriesTarget(episodes, at('e2', Duration.zero, duration: Duration.zero))), 'Lecture S01E02');
    // The last one seen: back to the first.
    expect(label(seriesTarget(episodes, at('e3', const Duration(minutes: 50), finished: true))), 'Lecture S01E01');
  });
}
