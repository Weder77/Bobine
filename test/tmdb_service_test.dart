import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/features/tmdb.dart';

void main() {
  late HttpServer server;
  var searches = 0;

  setUp(() async {
    searches = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final q = req.uri.queryParameters;
      Object body;
      if (q['api_key'] != 'k') {
        req.response.statusCode = 401;
        body = {};
      } else if (req.uri.path == '/configuration') {
        body = {'images': {}};
      } else if (req.uri.path == '/search/movie') {
        searches++;
        body = {
          'results': q['query'] == 'Odyssée'
              ? [
                  {'id': 7, 'title': 'Odyssée'},
                ]
              : [],
        };
      } else if (req.uri.path == '/movie/7') {
        body = {
          'id': 7,
          'title': 'Odyssée',
          'overview': 'Résumé',
          'backdrop_path': '/b.jpg',
          'genres': [
            {'name': 'Drame'},
          ],
          'release_date': '2018-01-01',
          'credits': {
            'cast': [
              {'name': 'A'},
            ],
            'crew': [
              {'job': 'Director', 'name': 'D'},
            ],
          },
          'videos': {
            'results': [
              {'site': 'YouTube', 'type': 'Trailer', 'key': 'abc123xyz'},
            ],
          },
        };
      } else {
        req.response.statusCode = 404;
        body = {};
      }
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
  });

  tearDown(() => server.close(force: true));

  test('a film is looked up once, then served from the cache', () async {
    final repo = Repository(openMemoryDatabase());
    final settings = AppSettings(repo)..tmdbKey = 'k';
    final tmdb = TmdbService(repo, settings, apiBase: 'http://127.0.0.1:${server.port}', imageBase: 'http://img');
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://x');
    const m = Movie(id: 1, sourceId: 1, extId: '503', name: 'FR - Odyssée (2018) [4K]');
    expect(src, 1);

    final info = await tmdb.movie(m).timeout(const Duration(seconds: 5));
    expect(info!.overview, 'Résumé');
    expect(info.backdrop, 'http://img/w1280/b.jpg');
    expect(info.director, 'D');
    expect(info.trailer, 'https://www.youtube.com/watch?v=abc123xyz');
    expect(tmdb.cachedMovie(m)!.genres, ['Drame']);

    await tmdb.movie(m).timeout(const Duration(seconds: 5));
    expect(searches, 1);

    // No match is remembered too (searched with and without the year).
    const other = Movie(id: 2, sourceId: 1, extId: '9', name: 'Inconnu (2001)');
    expect(await tmdb.movie(other).timeout(const Duration(seconds: 5)), isNull);
    expect(await tmdb.movie(other).timeout(const Duration(seconds: 5)), isNull);
    expect(searches, 3);

    expect(await tmdb.testKey('bad'), contains('401'));
    expect(await tmdb.testKey('k'), isNull);
  });
}
