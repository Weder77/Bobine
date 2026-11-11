import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/epg_cache.dart';
import 'package:bobine/data/import/import_service.dart';
import 'package:bobine/data/import/importers.dart';
import 'package:bobine/data/import/xtream_api.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/stream_urls.dart';
import 'package:bobine/ui/launch.dart';

String _xmltvTime(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}00 +0000';
}

void main() {
  late HttpServer server;
  late Directory tmp;
  // Databases must be closed before deleting their files (Windows locks them).
  final opened = <Repository>[];
  Repository track(Repository r) {
    opened.add(r);
    return r;
  }

  late String base;
  final now = DateTime.now();
  // Xtream actions answered with an error, and "the playlist is a web page".
  final broken = <String>{};
  // Xtream actions answered 200 with an empty list, and an empty guide.
  final emptied = <String>{};
  var emptyGuide = false;
  var portal = false;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('bobine_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final res = req.response;
      final q = req.uri.queryParameters;
      switch (req.uri.path) {
        case '/flaky.m3u':
          if (portal) {
            res.headers.contentType = ContentType.html;
            res.write('<!DOCTYPE html>\n<html><body>\n<h1>Abonnement expiré</h1>\n<p>Contacte ton revendeur.</p>\n');
            res.write('</body></html>\n');
          } else {
            res.write('#EXTM3U\n#EXTINF:-1 group-title="Infos",Info 24\n$base/live/u/p/1.ts\n');
            res.write('#EXTINF:-1 group-title="Infos",Info 25\n$base/live/u/p/2.ts\n');
          }
        case '/playlist.m3u':
          res.write('#EXTM3U x-tvg-url="$base/xmltv.php?username=u&password=p"\n');
          for (var i = 0; i < 1500; i++) {
            res.write(
              '#EXTINF:-1 tvg-id="ch$i" tvg-logo="$base/logo$i.png" group-title="Groupe ${i % 5}",Chaîne $i HD\n',
            );
            res.write('$base/live/u/p/$i.ts\n');
          }
          res.write('#EXTINF:-1 group-title="Films",Dune (2021)\n$base/movie/u/p/900.mkv\n');
          res.write('#EXTINF:-1 group-title="Séries",Lupin S01E01\n$base/series/u/p/901.mp4\n');
          res.write('#EXTINF:-1 group-title="Séries",Lupin S01E02\n$base/series/u/p/902.mp4\n');
        case '/player_api.php':
          if (q['password'] != 'p') {
            res.write(
              jsonEncode({
                'user_info': {'auth': 0},
              }),
            );
            break;
          }
          if (broken.contains(q['action'])) {
            res.statusCode = 500;
            break;
          }
          if (emptied.contains(q['action'])) {
            res.write('[]');
            break;
          }
          final data = switch (q['action']) {
            null => {
              'user_info': {'auth': 1, 'status': 'Active', 'exp_date': '1893456000', 'max_connections': '2'},
              'server_info': {'url': '127.0.0.1'},
            },
            'get_live_categories' => [
              {'category_id': '1', 'category_name': 'France'},
              {'category_id': 2, 'category_name': 'Sport'},
            ],
            'get_live_streams' => [
              for (var i = 0; i < 300; i++)
                {
                  'num': i + 1,
                  'name': 'FR: Chaîne $i',
                  'stream_id': 1000 + i,
                  'stream_icon': '',
                  'epg_channel_id': i == 0 ? 'ch0' : null,
                  'category_id': i.isEven ? '1' : '2',
                  'tv_archive': i == 1 ? 1 : 0,
                  'tv_archive_duration': '7',
                },
            ],
            'get_vod_categories' => [
              {'category_id': '10', 'category_name': 'Action'},
            ],
            'get_vod_streams' => [
              {
                'name': 'Mad Max (2015)',
                'stream_id': '5',
                'rating': '8.1',
                'added': '1700000000',
                'category_id': '10',
                'container_extension': 'mkv',
              },
              {'name': 'Sans catégorie', 'stream_id': 6, 'rating_5based': 3, 'category_id': '99'},
            ],
            'get_series_categories' => {
              '0': {'category_id': '20', 'category_name': 'Drame'},
            },
            'get_series' => [
              {
                'name': 'Dark',
                'series_id': 77,
                'cover': 'http://img/dark.jpg',
                'releaseDate': '2017-12-01',
                'category_id': '20',
                'backdrop_path': ['http://img/dark_b.jpg'],
              },
            ],
            'get_series_info' => {
              'info': {'name': 'Dark'},
              'episodes': {
                '1': [
                  {'id': '7701', 'episode_num': 1, 'title': 'Secrets', 'container_extension': 'mkv'},
                  {'id': '7702', 'episode_num': 2, 'title': 'Mensonges', 'container_extension': 'mkv'},
                ],
              },
            },
            _ => <Object>[],
          };
          res.write(jsonEncode(data));
        case '/xmltv.php':
          if (emptyGuide) {
            res.write('<?xml version="1.0"?><tv></tv>');
            break;
          }
          final xml = StringBuffer('<?xml version="1.0"?><tv>');
          xml.write('<channel id="CH0"><display-name>Chaîne 0</display-name></channel>');
          xml.write('<channel id="ch1"><display-name>Chaîne 1</display-name></channel>');
          for (final id in ['CH0', 'ch1']) {
            var t = now.subtract(const Duration(hours: 3));
            for (var i = 0; i < 24; i++) {
              final e = t.add(const Duration(minutes: 30));
              xml.write(
                '<programme start="${_xmltvTime(t)}" stop="${_xmltvTime(e)}" channel="$id">'
                '<title>Émission $i</title><desc>Desc $i</desc></programme>',
              );
              t = e;
            }
          }
          xml.write('</tv>');
          // Served as raw gzip without Content-Encoding, like many .xml.gz files.
          res.headers.contentType = ContentType('application', 'gzip');
          res.add(gzip.encode(utf8.encode(xml.toString())));
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    for (final r in opened) {
      r.db.close();
    }
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Best effort: a background isolate may still hold a handle briefly.
    }
  });

  test('M3U import + EPG matching by id and by name', () async {
    final path = '${tmp.path}/m3u.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'Test', type: SourceType.m3u, url: '$base/playlist.m3u');
    final result = await importM3u(path, id, null);
    expect(result.live, 1500);
    expect(result.movies, 1);
    expect(result.series, 1);

    final cats = repo.categories(id, ContentKind.live);
    expect(cats, hasLength(5));
    expect(cats.first.count, 300);
    expect(repo.episodes(id, repo.series(id).single.extId), hasLength(2));
    expect(repo.source(id)!.epgUrl, contains('/xmltv.php'));

    final kept = await importEpg(path, id, 3, null);
    expect(kept, greaterThan(20));

    final epg = EpgCache(repo);
    final channels = repo.channels(id);
    // ch0 matched by tvg-id (case-insensitive), ch1 by tvg-id too.
    expect(epg.now(channels[0])?.title, startsWith('Émission'));
    expect(epg.now(channels[1]), isNotNull);
    expect(epg.now(channels[2]), isNull);

    final res = repo.search(id, 'chaine 14');
    expect(res.channels.first.name, startsWith('Chaîne 14'));
    expect(repo.search(id, 'dune').movies.single.year, 2021);
  });

  test('Xtream import, URLs, favourites and progress survive refresh', () async {
    final path = '${tmp.path}/xt.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'XT', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
    final r = await importXtream(path, id, null);
    expect(r.live, 300);
    expect(r.movies, 2);
    expect(r.series, 1);
    final source = repo.source(id)!;
    expect(source.accountInfo!['max_connections'], 2);

    final ch = repo.channels(id).first;
    expect(StreamUrls.live(source, ch), '$base/live/u/p/1000.ts');
    final movie = repo.movies(id, sort: CatalogSort.rating).first;
    expect(movie.name, 'Mad Max (2015)');
    expect(movie.year, 2015);
    expect(StreamUrls.movie(source, movie), '$base/movie/u/p/5.mkv');
    expect(repo.movies(id).last.rating, 6); // rating_5based * 2
    expect(repo.categories(id, ContentKind.movie).map((c) => c.name), contains('Autres'));
    expect(repo.series(id).single.year, 2017);
    expect(repo.channels(id)[1].catchupDays, 7);

    repo.toggleFavorite(id, ContentKind.live, ch.extId);
    repo.saveProgress(
      sourceId: id,
      kind: ContentKind.movie,
      extId: movie.extId,
      position: const Duration(minutes: 40),
      duration: const Duration(minutes: 120),
      title: movie.name,
    );
    await importXtream(path, id, null); // refresh replaces content
    expect(repo.favoriteChannels(id).single.extId, ch.extId);
    expect(repo.continueWatching(id).single.title, 'Mad Max (2015)');

    // Wrong password is reported clearly.
    final bad = XtreamApi(baseUrl: base, username: 'u', password: 'x');
    await expectLater(bad.authenticate(), throwsA(predicate((e) => '$e'.contains('incorrect'))));
    bad.close();

    // EPG through the isolate-based service (checks isolate message safety).
    var epgChanged = false;
    final service = ImportService(dbPath: path, onContentChanged: (_) {}, onEpgChanged: (_) => epgChanged = true);
    await service.refresh(source, content: true, epg: true);
    expect(epgChanged, isTrue);
    expect(repo.epgProgramCount(id), greaterThan(20));
    // ch0 has epg_channel_id; "FR: Chaîne 1" is matched by display name.
    final epg = EpgCache(repo);
    final list = repo.channels(id);
    expect(epg.now(list[0]), isNotNull);
    expect(epg.now(list[1]), isNotNull);
  });

  test('after an Xtream refresh, the episodes of a series are asked again to resume', () async {
    final path = '${tmp.path}/episodes.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'X', type: SourceType.xtream, url: base, username: 'u', password: 'p');
    await importXtream(path, id, null);
    final dark = repo.seriesByExt(id, '77')!;
    // Opened once: the episodes are kept. A refresh empties them again.
    expect((await loadEpisodes(repo, dark)).map((e) => e.extId), ['7701', '7702']);
    await importXtream(path, id, null);
    expect(repo.episodes(id, '77'), isEmpty);
    final again = await loadEpisodes(repo, dark);
    expect(again.map((e) => e.extId), ['7701', '7702']);
    expect(repo.episodes(id, '77'), hasLength(2));
  });

  test('an empty list in a good answer does not empty the source', () async {
    final path = '${tmp.path}/emptied.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'XT', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
    await importXtream(path, id, null);
    addTearDown(emptied.clear);

    // "[]" for the channels: nothing is touched, and it is said.
    emptied.add('get_live_streams');
    await expectLater(importXtream(path, id, null), throwsA(predicate((e) => '$e'.contains('aucune chaîne'))));
    expect(repo.channels(id), hasLength(300));
    expect(repo.movies(id), hasLength(2));

    // "[]" for the films or the series: they stay, the rest is refreshed.
    emptied
      ..clear()
      ..addAll(['get_vod_streams', 'get_series']);
    final r = await importXtream(path, id, null);
    expect(r.live, 300);
    expect(repo.movies(id), hasLength(2));
    expect(repo.series(id).single.name, 'Dark');
    expect(repo.source(id)!.lastError, allOf(contains('Films'), contains('Séries')));
  });

  test('an empty or unreadable guide keeps the one the source has', () async {
    final path = '${tmp.path}/emptyguide.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(
      name: 'XT',
      type: SourceType.xtream,
      url: '$base/',
      username: 'u',
      password: 'p',
      epgUrl: '$base/xmltv.php',
    );
    final kept = await importEpg(path, id, 3, null);
    expect(kept, greaterThan(0));
    final at = repo.source(id)!.epgUpdatedAt;
    emptyGuide = true;
    addTearDown(() => emptyGuide = false);
    await expectLater(importEpg(path, id, 3, null), throwsA(predicate((e) => '$e'.contains('guide reçu est vide'))));
    expect(repo.db.select('SELECT count(*) AS n FROM epg_programs WHERE source_id = ?', [id]).first['n'], kept);
    expect(repo.source(id)!.epgUpdatedAt, at, reason: 'not marked up to date: asked again next time');
  });

  test('a list that fails to download keeps what the source had, and says so', () async {
    final path = '${tmp.path}/partial.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'XT', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
    await importXtream(path, id, null);
    expect(repo.movies(id), hasLength(2));
    final categories = repo.categories(id, ContentKind.movie).map((c) => c.name).toSet();
    addTearDown(broken.clear);

    // The films list answers an error: the films stay, with their categories.
    broken.add('get_vod_streams');
    final r = await importXtream(path, id, null);
    expect(r.live, 300);
    expect(r.movies, 2);
    expect(repo.movies(id).map((m) => m.name), contains('Mad Max (2015)'));
    expect(repo.categories(id, ContentKind.movie).map((c) => c.name).toSet(), categories);
    expect(repo.movies(id).every((m) => m.categoryId != null), isTrue);
    expect(repo.series(id), hasLength(1));
    expect(repo.channels(id), hasLength(300));
    expect(repo.source(id)!.lastError, allOf(contains('incomplète'), contains('Films')));

    // The series categories fail too: series and their episodes stay.
    broken.add('get_series_categories');
    await importXtream(path, id, null);
    expect(repo.series(id).single.name, 'Dark');
    expect(repo.categories(id, ContentKind.series).single.name, 'Drame');

    // Without the channels, nothing is touched at all.
    broken
      ..clear()
      ..add('get_live_streams');
    await expectLater(importXtream(path, id, null), throwsA(anything));
    expect(repo.channels(id), hasLength(300));
    expect(repo.movies(id), hasLength(2));

    // Back to normal: the warning goes away.
    broken.clear();
    await importXtream(path, id, null);
    expect(repo.source(id)!.lastError, isNull);
    expect(repo.movies(id), hasLength(2));
  });

  test('channels are imported even when the names of their categories cannot be', () async {
    final path = '${tmp.path}/livecats.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'XT', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
    addTearDown(broken.clear);

    // Known from a first import: the names and their order are kept.
    await importXtream(path, id, null);
    final names = repo.categories(id, ContentKind.live).map((c) => c.name).toList();
    expect(names, ['France', 'Sport']);
    repo.setCategoryHidden(id, ContentKind.live, '2', true);
    final visible = repo.channels(id).length;
    expect(visible, lessThan(300));

    broken.add('get_live_categories');
    final r = await importXtream(path, id, null);
    expect(r.live, 300);
    expect(repo.categories(id, ContentKind.live, includeHidden: true).map((c) => c.name).toList(), names);
    expect(repo.channels(id), hasLength(visible), reason: 'the hidden category is still hidden');
    expect(repo.movies(id), hasLength(2));
    expect(repo.source(id)!.lastError, allOf(contains('incomplète'), contains('Catégories TV')));

    // Never imported before: the channels are there, under "Autres".
    final fresh = repo.insertSource(name: 'XT2', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
    expect((await importXtream(path, fresh, null)).live, 300);
    expect(repo.channels(fresh), hasLength(300));
    expect(repo.categories(fresh, ContentKind.live).map((c) => c.name).toSet(), {'Autres'});
    expect(repo.channels(fresh).every((c) => c.categoryId != null), isTrue);
  });

  test('a web page served instead of the playlist does not replace the channels', () async {
    final path = '${tmp.path}/portal.db';
    final repo = track(Repository(openAppDatabase(path)));
    final id = repo.insertSource(name: 'M3U', type: SourceType.m3u, url: '$base/flaky.m3u');
    await importM3u(path, id, null);
    expect(repo.channels(id).map((c) => c.name), ['Info 24', 'Info 25']);
    portal = true;
    addTearDown(() => portal = false);
    await expectLater(importM3u(path, id, null), throwsA(predicate((e) => '$e'.contains('page web'))));
    expect(repo.channels(id).map((c) => c.name), ['Info 24', 'Info 25']);
  });

  test('refreshing a source does not mark it as changed for the synchronisation', () async {
    final path = '${tmp.path}/noted.db';
    final repo = track(Repository(openAppDatabase(path)));
    int noted() => repo.db.select("SELECT count(*) AS n FROM sync_log WHERE tbl = 'sources'").first['n'] as int;
    final xt = repo.insertSource(name: 'XT', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
    final m3u = repo.insertSource(name: 'M3U', type: SourceType.m3u, url: '$base/playlist.m3u');
    // The playlist names its guide: saved once, which is a real change.
    await importM3u(path, m3u, null);
    expect(repo.source(m3u)!.epgUrl, contains('/xmltv.php'));
    repo.db.execute('DELETE FROM sync_log');
    await importXtream(path, xt, null);
    await importM3u(path, m3u, null);
    expect(noted(), 0);
    expect(repo.source(m3u)!.epgUrl, contains('/xmltv.php'));
    // A guide the user typed is not replaced by the playlist's.
    repo.db.execute("UPDATE sources SET epg_url = 'http://moi.example/guide.xml' WHERE id = ?", [m3u]);
    repo.db.execute('DELETE FROM sync_log');
    await importM3u(path, m3u, null);
    expect(repo.source(m3u)!.epgUrl, 'http://moi.example/guide.xml');
    expect(noted(), 0);
  });

  test('EPG offset shifts programme times', () async {
    final path = '${tmp.path}/offset.db';
    final repo = track(Repository(openAppDatabase(path)));
    final a = repo.insertSource(name: 'A', type: SourceType.m3u, url: '$base/playlist.m3u', epgUrl: '$base/xmltv.php');
    final b = repo.insertSource(
      name: 'B',
      type: SourceType.m3u,
      url: '$base/playlist.m3u',
      epgUrl: '$base/xmltv.php',
      epgOffset: 90,
    );
    expect(repo.source(b)!.epgOffsetMinutes, 90);
    await importEpg(path, a, 3, null);
    await importEpg(path, b, 3, null);
    final from = DateTime.now().subtract(const Duration(hours: 12));
    final to = DateTime.now().add(const Duration(days: 2));
    final pa = repo.programs(a, 'ch1', from, to);
    final pb = repo.programs(b, 'ch1', from, to);
    final first = pa.first;
    final shifted = pb.firstWhere((p) => p.title == first.title);
    expect(shifted.start.difference(first.start), const Duration(minutes: 90));
  });

  test('migration v1 -> current keeps sources, favourites and progress (profile 1)', () {
    final path = '${tmp.path}/migrate.db';
    final raw = sqlite3.open(path);
    createSchemaV1(raw);
    raw.execute('PRAGMA user_version = 1');
    raw.execute(
      "INSERT INTO sources (id, name, type, url, created_at) VALUES (1, 'old', 'm3u', 'http://x/list.m3u', 0)",
    );
    raw.execute("INSERT INTO favorites VALUES (1, 'movie', 'm42', 5)");
    raw.execute("INSERT INTO progress VALUES (1, 'movie', 'm42', 60000, 600000, 0, 7, 'Film', NULL, NULL, NULL)");
    raw.close();
    final repo = track(Repository(openAppDatabase(path)));
    expect(repo.db.select('PRAGMA user_version').first.columnAt(0), kSchemaVersion);
    final src = repo.sources().single;
    expect(src.epgOffsetMinutes, 0);
    expect(src.url, 'http://x/list.m3u');
    expect(repo.profiles().single.id, 1);
    // v5: ids shared by all devices, the first profile is the same everywhere.
    expect(repo.db.select('SELECT uid FROM sources').single['uid'], matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(repo.db.select('SELECT uid FROM profiles').single['uid'], kDefaultProfileUid);
    expect(repo.profiles().single.avatar, isNull); // v6: the initial, as before
    expect(repo.favoriteKeys(1, ContentKind.movie), {'m42'});
    expect(repo.progress(1, ContentKind.movie, 'm42')?.position, const Duration(minutes: 1));
    // Another profile starts empty.
    repo.profileId = repo.createProfile(name: 'Léa', color: 0xFF7FA6FF);
    expect(repo.favoriteKeys(1, ContentKind.movie), isEmpty);
    expect(repo.progress(1, ContentKind.movie, 'm42'), isNull);
  });

  test('a programme that started long ago is still listed while running', () {
    final repo = Repository(openMemoryDatabase());
    final id = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 24 h block that started 10 h ago, then a normal programme.
    const insert =
        'INSERT INTO epg_programs (source_id, channel, start, stop, title, description) VALUES (?, ?, ?, ?, ?, ?)';
    repo.db.execute(insert, [id, 'news', now - 10 * 3600, now + 14 * 3600, 'Info en continu', null]);
    repo.db.execute(insert, [id, 'news', now + 14 * 3600, now + 15 * 3600, 'Journal', null]);
    final list = repo.programs(id, 'news', DateTime.now(), DateTime.now().add(const Duration(days: 1)));
    expect(list.map((p) => p.title), ['Info en continu', 'Journal']);
  });

  test('schema opens in memory', () {
    final db = openMemoryDatabase();
    expect(Repository(db).sources(), isEmpty);
  });
}
