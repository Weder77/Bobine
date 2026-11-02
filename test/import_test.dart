import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:lumen/data/db.dart';
import 'package:lumen/data/epg_cache.dart';
import 'package:lumen/data/import/import_service.dart';
import 'package:lumen/data/import/importers.dart';
import 'package:lumen/data/import/xtream_api.dart';
import 'package:lumen/data/models.dart';
import 'package:lumen/data/repository.dart';
import 'package:lumen/data/stream_urls.dart';

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

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('lumen_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final res = req.response;
      final q = req.uri.queryParameters;
      switch (req.uri.path) {
        case '/playlist.m3u':
          res.write('#EXTM3U x-tvg-url="$base/xmltv.php?username=u&password=p"\n');
          for (var i = 0; i < 1500; i++) {
            res.write('#EXTINF:-1 tvg-id="ch$i" tvg-logo="$base/logo$i.png" group-title="Groupe ${i % 5}",Chaîne $i HD\n');
            res.write('$base/live/u/p/$i.ts\n');
          }
          res.write('#EXTINF:-1 group-title="Films",Dune (2021)\n$base/movie/u/p/900.mkv\n');
          res.write('#EXTINF:-1 group-title="Séries",Lupin S01E01\n$base/series/u/p/901.mp4\n');
          res.write('#EXTINF:-1 group-title="Séries",Lupin S01E02\n$base/series/u/p/902.mp4\n');
        case '/player_api.php':
          if (q['password'] != 'p') {
            res.write(jsonEncode({'user_info': {'auth': 0}}));
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
                  {'num': i + 1, 'name': 'FR: Chaîne $i', 'stream_id': 1000 + i, 'stream_icon': '',
                   'epg_channel_id': i == 0 ? 'ch0' : null, 'category_id': i.isEven ? '1' : '2',
                   'tv_archive': i == 1 ? 1 : 0, 'tv_archive_duration': '7'},
              ],
            'get_vod_categories' => [{'category_id': '10', 'category_name': 'Action'}],
            'get_vod_streams' => [
                {'name': 'Mad Max (2015)', 'stream_id': '5', 'rating': '8.1', 'added': '1700000000',
                 'category_id': '10', 'container_extension': 'mkv'},
                {'name': 'Sans catégorie', 'stream_id': 6, 'rating_5based': 3, 'category_id': '99'},
              ],
            'get_series_categories' => {'0': {'category_id': '20', 'category_name': 'Drame'}},
            'get_series' => [
                {'name': 'Dark', 'series_id': 77, 'cover': 'http://img/dark.jpg', 'releaseDate': '2017-12-01',
                 'category_id': '20', 'backdrop_path': ['http://img/dark_b.jpg']},
              ],
            _ => <Object>[],
          };
          res.write(jsonEncode(data));
        case '/xmltv.php':
          final xml = StringBuffer('<?xml version="1.0"?><tv>');
          xml.write('<channel id="CH0"><display-name>Chaîne 0</display-name></channel>');
          xml.write('<channel id="ch1"><display-name>Chaîne 1</display-name></channel>');
          for (final id in ['CH0', 'ch1']) {
            var t = now.subtract(const Duration(hours: 3));
            for (var i = 0; i < 24; i++) {
              final e = t.add(const Duration(minutes: 30));
              xml.write('<programme start="${_xmltvTime(t)}" stop="${_xmltvTime(e)}" channel="$id">'
                  '<title>Émission $i</title><desc>Desc $i</desc></programme>');
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
    final id = repo.insertSource(
        name: 'XT', type: SourceType.xtream, url: '$base/', username: 'u', password: 'p');
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
    repo.saveProgress(sourceId: id, kind: ContentKind.movie, extId: movie.extId,
        position: const Duration(minutes: 40), duration: const Duration(minutes: 120), title: movie.name);
    await importXtream(path, id, null); // refresh replaces content
    expect(repo.favoriteChannels(id).single.extId, ch.extId);
    expect(repo.continueWatching(id).single.title, 'Mad Max (2015)');

    // Wrong password is reported clearly.
    final bad = XtreamApi(baseUrl: base, username: 'u', password: 'x');
    await expectLater(bad.authenticate(), throwsA(predicate((e) => '$e'.contains('incorrect'))));
    bad.close();

    // EPG through the isolate-based service (checks isolate message safety).
    var epgChanged = false;
    final service = ImportService(
        dbPath: path, onContentChanged: (_) {}, onEpgChanged: (_) => epgChanged = true);
    await service.refresh(source, content: true, epg: true);
    expect(epgChanged, isTrue);
    expect(repo.epgProgramCount(id), greaterThan(20));
    // ch0 has epg_channel_id; "FR: Chaîne 1" is matched by display name.
    final epg = EpgCache(repo);
    final list = repo.channels(id);
    expect(epg.now(list[0]), isNotNull);
    expect(epg.now(list[1]), isNotNull);
  });

  test('EPG offset shifts programme times', () async {
    final path = '${tmp.path}/offset.db';
    final repo = track(Repository(openAppDatabase(path)));
    final a = repo.insertSource(
        name: 'A', type: SourceType.m3u, url: '$base/playlist.m3u',
        epgUrl: '$base/xmltv.php');
    final b = repo.insertSource(
        name: 'B', type: SourceType.m3u, url: '$base/playlist.m3u',
        epgUrl: '$base/xmltv.php', epgOffset: 90);
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

  test('migration v1 -> v2 adds epg_offset', () {
    final path = '${tmp.path}/migrate.db';
    openAppDatabase(path).close();
    final raw = sqlite3.open(path);
    raw.execute('ALTER TABLE sources DROP COLUMN epg_offset');
    raw.execute('PRAGMA user_version = 1');
    raw.execute(
        "INSERT INTO sources (name, type, url, created_at) VALUES ('old', 'm3u', 'http://x/list.m3u', 0)");
    raw.close();
    final repo = track(Repository(openAppDatabase(path)));
    expect(repo.db.select('PRAGMA user_version').first.columnAt(0), kSchemaVersion);
    final src = repo.sources().single;
    expect(src.epgOffsetMinutes, 0);
    expect(src.url, 'http://x/list.m3u');
  });

  test('schema opens in memory', () {
    final db = openMemoryDatabase();
    expect(Repository(db).sources(), isEmpty);
  });
}
