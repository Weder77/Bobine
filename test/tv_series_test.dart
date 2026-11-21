import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/tv/tv_series.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Repository repo;
  late int src;
  late List<Episode> eps;

  setUp(() {
    repo = Repository(openMemoryDatabase());
    src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    eps = [
      for (final (s, e) in [(1, 1), (1, 2), (2, 1), (2, 2)])
        Episode(
          sourceId: src,
          seriesExt: 'show',
          extId: 's${s}e$e',
          season: s,
          episode: e,
          title: 'T$s$e',
          durationSec: 3000,
        ),
    ];
    repo.replaceEpisodes(src, 'show', eps);
  });

  Future<void> watch(String ext, Duration at) async {
    repo.saveProgress(
      sourceId: src,
      kind: ContentKind.episode,
      extId: ext,
      position: at,
      duration: const Duration(minutes: 50),
      title: 'Show',
      seriesExt: 'show',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  ({Episode episode, String label}) primary() => tvSeriesPrimary(eps, repo.seriesProgress(src, 'show'));

  test('jamais regardée : Lecture du premier épisode', () {
    final p = primary();
    expect(p.episode.extId, 's1e1');
    expect(p.label, 'Lecture S01E01');
  });

  test('un épisode commencé : Reprendre cet épisode', () async {
    await watch('s1e2', const Duration(minutes: 20));
    final p = primary();
    expect(p.episode.extId, 's1e2');
    expect(p.label, 'Reprendre S01E02');
  });

  test('le dernier regardé est fini : l’épisode suivant, même dans la saison d’après', () async {
    await watch('s1e1', const Duration(minutes: 20));
    await watch('s1e2', const Duration(minutes: 50));
    final p = primary();
    expect(p.episode.extId, 's2e1');
    expect(p.label, 'Lecture S02E01');
  });

  test('tout est vu : on recommence au début', () async {
    await watch('s2e2', const Duration(minutes: 50));
    expect(primary().episode.extId, 's1e1');
  });

  test('les saisons dans l’ordre, sans doublon', () {
    expect(tvSeasons(eps), [1, 2]);
  });
}
