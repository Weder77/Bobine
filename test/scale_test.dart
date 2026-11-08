import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/epg_cache.dart';
import 'package:bobine/data/import/importers.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';

/// Load test: 100 000 playlist entries and a guide of ~250 000 programmes.
/// Thresholds are deliberately generous (CI machines vary); the printed
/// timings are what matters.
void main() {
  late Directory tmp;
  late String m3uPath;
  late String xmlPath;
  const liveCount = 20000, movieCount = 60000, episodeCount = 20000, epgChannels = 2000;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('bobine_scale');
    m3uPath = '${tmp.path}/big.m3u';
    xmlPath = '${tmp.path}/big.xml';

    final m3u = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < liveCount; i++) {
      m3u.write(
        '#EXTINF:-1 tvg-id="ch$i" tvg-logo="http://img/l$i.png" group-title="Pays ${i % 200}",'
        'FR: Chaîne numéro $i HD\nhttp://srv/live/u/p/$i.ts\n',
      );
    }
    for (var i = 0; i < movieCount; i++) {
      m3u.write(
        '#EXTINF:-1 tvg-logo="http://img/m$i.jpg" group-title="Films ${i % 150}",'
        'Film Épique $i (${1960 + i % 65})\nhttp://srv/movie/u/p/$i.mkv\n',
      );
    }
    for (var i = 0; i < episodeCount; i++) {
      final show = i ~/ 10;
      m3u.write(
        '#EXTINF:-1 group-title="Séries ${show % 80}",Série $show S0${1 + (i % 10) ~/ 5}E${(i % 5) + 1}\n'
        'http://srv/series/u/p/$i.mp4\n',
      );
    }
    File(m3uPath).writeAsStringSync(m3u.toString());

    final now = DateTime.now().toUtc();
    String t(DateTime d) {
      String two(int v) => v.toString().padLeft(2, '0');
      return '${d.year}${two(d.month)}${two(d.day)}${two(d.hour)}${two(d.minute)}00 +0000';
    }

    final xml = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<tv>\n');
    for (var c = 0; c < epgChannels; c++) {
      xml.write('<channel id="ch$c"><display-name>Chaîne numéro $c</display-name></channel>\n');
    }
    final start = now.subtract(const Duration(hours: 12));
    for (var c = 0; c < epgChannels; c++) {
      var d = start;
      var k = 0;
      while (d.isBefore(now.add(const Duration(days: 4)))) {
        final e = d.add(Duration(minutes: 30 + (k % 4) * 15));
        xml.write(
          '<programme start="${t(d)}" stop="${t(e)}" channel="ch$c"><title lang="fr">'
          'Programme $k &amp; co</title><desc lang="fr">Description du programme $k.</desc></programme>\n',
        );
        d = e;
        k++;
      }
    }
    xml.write('</tv>\n');
    File(xmlPath).writeAsStringSync(xml.toString());
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort (Windows may still hold a handle briefly).
    }
  });

  test('100k entries: import, queries and guide stay fast', () async {
    final path = '${tmp.path}/scale.db';
    final repo = Repository(openAppDatabase(path));
    final id = repo.insertSource(name: 'Big', type: SourceType.m3u, url: m3uPath, epgUrl: xmlPath);
    final sw = Stopwatch()..start();
    final timings = <String, int>{};
    void lap(String label) {
      timings[label] = sw.elapsedMilliseconds;
      sw.reset();
    }

    final r = await importM3u(path, id, null);
    lap('Import M3U (100 000 entrées)');
    expect(r.live, liveCount);
    expect(r.movies, movieCount);
    expect(r.series, episodeCount ~/ 10);

    final kept = await importEpg(path, id, 3, null);
    lap('Import XMLTV ($epgChannels chaînes)');
    expect(kept, greaterThan(100000));

    final cats = repo.categories(id, ContentKind.movie);
    lap('Catégories films (comptes)');
    expect(cats, hasLength(150));

    final movies = repo.movies(id);
    lap('Tous les films (60 000)');
    expect(movies, hasLength(movieCount));

    final filtered = movies.where((m) => m.search.contains('epique 4242')).toList();
    lap('Filtre en mémoire (60 000)');
    expect(filtered, isNotEmpty);

    final channels = repo.channels(id, categoryId: repo.categories(id, ContentKind.live).first.id);
    lap('Chaînes d\'une catégorie');
    expect(channels, hasLength(liveCount ~/ 200));

    final res = repo.search(id, 'chaine numero 1234');
    lap('Recherche globale');
    expect(res.channels.first.name, contains('1234'));

    final epg = EpgCache(repo);
    var withNow = 0;
    for (final c in channels) {
      if (epg.now(c) != null) withNow++;
    }
    lap('Programme en cours (${channels.length} chaînes)');
    // Only ch0..ch1999 have guide data: 10 of the 100 channels of "Pays 0".
    expect(withNow, epgChannels ~/ 200);

    final grid = epg.programs(channels.first, DateTime.now(), DateTime.now().add(const Duration(days: 1)));
    lap('Grille 24 h d\'une chaîne');
    expect(grid, isNotEmpty);

    // ignore: avoid_print
    print('\n--- Timings (ms) ---\n${timings.entries.map((e) => '${e.key.padRight(36)} ${e.value}').join('\n')}');

    expect(timings['Import M3U (100 000 entrées)']!, lessThan(60000));
    expect(timings['Tous les films (60 000)']!, lessThan(3000));
    expect(timings['Recherche globale']!, lessThan(2000));
    expect(timings['Programme en cours (${channels.length} chaînes)']!, lessThan(2000));
    repo.db.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
