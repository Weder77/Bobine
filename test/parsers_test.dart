import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/core/text.dart';
import 'package:bobine/data/import/m3u_parser.dart';
import 'package:bobine/data/import/xmltv_parser.dart';
import 'package:bobine/data/import/xtream_api.dart';

void main() {
  test('the guide named by a playlist is a web address or nothing', () {
    String? guide(String header) {
      final p = M3uParser((_) {})..addLine(header);
      return p.epgUrl;
    }

    expect(
      guide('#EXTM3U url-tvg="http://epg.example/a.xml.gz,http://autre.example/b.xml"'),
      'http://epg.example/a.xml.gz',
    );
    expect(guide('#EXTM3U x-tvg-url="HTTPS://epg.example/a.xml"'), 'HTTPS://epg.example/a.xml');
    // A path chosen by the provider would be opened as a file by the import.
    expect(guide(r'#EXTM3U url-tvg="\\evil.example\share\epg.xml"'), isNull);
    expect(guide('#EXTM3U url-tvg="file:///etc/passwd"'), isNull);
    expect(guide(r'#EXTM3U url-tvg="C:\Users\moi\secret.txt"'), isNull);
    expect(guide('#EXTM3U url-tvg="/dev/zero"'), isNull);
    expect(guide('#EXTM3U'), isNull);
  });

  test('a web page or an error message is not a playlist', () {
    for (final first in ['<!DOCTYPE html>', '<html>', '{"error":"expired"}', '[]', '<?xml version="1.0"?>']) {
      final entries = <M3uEntry>[];
      final p = M3uParser(entries.add)
        ..addLine('')
        ..addLine(first)
        ..addLine('Abonnement expiré')
        ..addLine('http://x/1.ts');
      expect(p.notAPlaylist, isTrue, reason: first);
      expect(entries, isEmpty, reason: first);
    }
    // Plain lists of addresses and files starting with a comment still are.
    final entries = <M3uEntry>[];
    final plain = M3uParser(entries.add)
      ..addLine('\ufeff# ma liste')
      ..addLine('http://x/1.ts');
    expect(plain.notAPlaylist, isFalse);
    expect(entries.single.url, 'http://x/1.ts');
  });

  group('M3U', () {
    List<M3uEntry> parse(String text, {void Function(M3uParser)? inspect}) {
      final out = <M3uEntry>[];
      final p = M3uParser(out.add);
      for (final l in text.split('\n')) {
        p.addLine(l);
      }
      inspect?.call(p);
      return out;
    }

    test('parses attributes, names with commas and header EPG', () {
      String? epg;
      final entries = parse('''
﻿#EXTM3U url-tvg="http://epg.example/guide.xml.gz,http://other"
#EXTINF:-1 tvg-id="TF1.fr" tvg-name="TF1" tvg-logo="http://logo/tf1.png" group-title="France, TNT",TF1 HD, le direct
http://srv/live/u/p/1.ts

#EXTINF:0 tvg-chno=5 group-title='Sport',beIN Sports 1
#EXTVLCOPT:http-user-agent=Foo
http://srv/live/u/p/2.ts
#EXTINF:-1,Sans groupe
#EXTGRP:Divers
http://srv/3.m3u8
http://srv/plain/stream4.ts
''', inspect: (p) => epg = p.epgUrl);
      expect(epg, 'http://epg.example/guide.xml.gz');
      expect(entries, hasLength(4));
      expect(entries[0].name, 'TF1 HD, le direct');
      expect(entries[0].tvgId, 'TF1.fr');
      expect(entries[0].groupTitle, 'France, TNT');
      expect(entries[0].logo, 'http://logo/tf1.png');
      expect(entries[1].attr('tvg-chno'), '5');
      expect(entries[1].groupTitle, 'Sport');
      expect(entries[2].groupTitle, 'Divers');
      expect(entries[3].name, 'stream4.ts');
      expect(entries[3].groupTitle, 'Sans catégorie');
    });

    test('untitled entry with an encoded % in its URL does not crash', () {
      final entries = parse('#EXTM3U\nhttp://host/vod/100%25.ts\n');
      expect(entries.single.name, '100%.ts');
    });

    test('classifies live, movies and episodes', () {
      M3uEntry e(String name, String url) => M3uEntry(name: name, url: url);
      expect(classifyEntry(e('TF1', 'http://s/live/u/p/1.ts')), M3uKind.live);
      expect(classifyEntry(e('TF1', 'http://s/1.m3u8')), M3uKind.live);
      expect(classifyEntry(e('TF1', 'http://s/u/p/1')), M3uKind.live);
      expect(classifyEntry(e('Dune (2021)', 'http://s/movie/u/p/9.mkv')), M3uKind.movie);
      expect(classifyEntry(e('Dune', 'http://s/files/dune.mp4?token=1')), M3uKind.movie);
      expect(classifyEntry(e('The Office S02 E05', 'http://s/series/u/p/77.mkv')), M3uKind.episode);
      expect(classifyEntry(e('Lupin S01E03', 'http://s/x/77.mp4')), M3uKind.episode);
    });

    test('parses episode names', () {
      final i = parseEpisode('FR - Lupin S01E03 - Chapitre 3')!;
      expect(i.seriesName, 'FR - Lupin');
      expect(i.season, 1);
      expect(i.episode, 3);
      expect(parseEpisode('The Office s2 x05')?.episode, 5);
      expect(parseEpisode('Un film normal'), isNull);
    });
  });

  group('XMLTV', () {
    test('an element that never ends is refused instead of being kept whole', () {
      var programmes = 0;
      final p = XmltvParser(onProgramme: (c, s, e, t, d, g) => programmes++, onChannel: (id, names) {})
        ..maxElementChars = 2000;
      p.add('<tv><programme start="20240131200000 +0100" channel="a"><title>Sans fin</title><desc>');
      Object? error;
      var fed = 0;
      try {
        for (; fed < 100; fed++) {
          p.add('x' * 100);
        }
      } catch (e) {
        error = e;
      }
      expect(error, isA<XmltvException>());
      expect('$error', startsWith('Guide TV illisible'));
      // Stopped as soon as the limit was passed, not at the end of the file.
      expect(fed, lessThan(25));
      expect(programmes, 0);
    });

    test('a long guide of ordinary programmes never reaches the element limit', () {
      var programmes = 0;
      final p = XmltvParser(onProgramme: (c, s, e, t, d, g) => programmes++, onChannel: (id, names) {})
        ..maxElementChars = 2000;
      const one =
          '<programme start="20240131200000 +0100" stop="20240131210000 +0100" channel="a">'
          '<title>Journal</title><desc>Un résumé de quelques lignes, comme dans un vrai guide.</desc></programme>\n';
      final xml = '<tv>${one * 500}</tv>';
      // Far more text than the limit in all, in chunks cut anywhere.
      expect(xml.length, greaterThan(50000));
      for (var i = 0; i < xml.length; i += 333) {
        p.add(xml.substring(i, i + 333 > xml.length ? xml.length : i + 333));
      }
      p.close();
      expect(programmes, 500);
    });

    test('parses chunked input, entities, CDATA and timezones', () {
      final progs = <List<Object?>>[];
      final chans = <String, List<String>>{};
      final p = XmltvParser(
        onProgramme: (c, s, e, t, d, g) => progs.add([c, s, e, t, d, g]),
        onChannel: (id, names) => chans[id] = names,
      );
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="x">
  <channel id="TF1.fr"><display-name lang="fr">TF1</display-name><display-name>TF1 HD</display-name><icon src="x"/></channel>
  <programme start="20240131200000 +0100" stop="20240131210000 +0100" channel="TF1.fr">
    <title lang="en">News</title><title lang="fr">Le JT &amp; la météo</title>
    <desc lang="fr"><![CDATA[Résumé <b>du</b> jour]]></desc>
    <category lang="fr">Info</category><category lang="en">info</category><category lang="fr">Journal</category>
  </programme>
  <programme start="20240131210000" stop="20240131223000" channel="TF1.fr"><title>Film &#233;t&#xE9;</title></programme>
  <programme start="20240131223000 +0100" channel="TF1.fr"/>
</tv>''';
      // Feed in tiny chunks to exercise boundary handling.
      for (var i = 0; i < xml.length; i += 7) {
        p.add(xml.substring(i, i + 7 > xml.length ? xml.length : i + 7));
      }
      p.close();
      expect(chans['TF1.fr'], ['TF1', 'TF1 HD']);
      expect(progs, hasLength(2));
      expect(progs[0][0], 'TF1.fr');
      expect(progs[0][1], DateTime.utc(2024, 1, 31, 19).millisecondsSinceEpoch ~/ 1000);
      expect(progs[0][3], 'Le JT & la météo');
      expect(progs[0][4], 'Résumé <b>du</b> jour');
      expect(progs[0][5], 'Info · Journal'); // first two genres, no repeats
      expect(progs[1][5], isNull);
      expect(progs[1][1], DateTime.utc(2024, 1, 31, 21).millisecondsSinceEpoch ~/ 1000);
      expect(progs[1][3], 'Film été');
    });

    test('time parsing variants', () {
      expect(parseXmltvTime('202401312000 -0230'), DateTime.utc(2024, 1, 31, 22, 30).millisecondsSinceEpoch ~/ 1000);
      expect(parseXmltvTime('bad'), isNull);
    });
  });

  group('Xtream', () {
    test('series info with map-of-seasons episodes', () {
      final info = parseSeriesInfo(
        {
          'info': {
            'plot': 'Plot',
            'backdrop_path': ['http://img/b.jpg'],
            'rating': '8.1',
          },
          'episodes': {
            '2': [
              {
                'id': '22',
                'episode_num': '1',
                'title': 'S2E1',
                'container_extension': 'mkv',
                'info': {'duration_secs': 1500, 'movie_image': 'http://img/e.jpg'},
              },
            ],
            '1': [
              {'id': '11', 'episode_num': 2, 'season': 1, 'title': 'S1E2'},
              {'id': '10', 'episode_num': 1, 'season': 1, 'title': 'S1E1', 'info': []},
            ],
          },
        },
        1,
        '500',
      );
      expect(info.episodes.map((e) => e.extId), ['10', '11', '22']);
      expect(info.episodes.last.season, 2);
      expect(info.episodes.last.durationSec, 1500);
      expect(info.backdrop, 'http://img/b.jpg');
      expect(info.rating, 8.1);
    });

    test('the clock of the panel is read from the account answer', () {
      int? offset(Object? info) => XtreamApi.serverUtcOffset(info);
      // 2026-11-07 19:45:10 UTC.
      final stamp = DateTime.utc(2026, 11, 7, 19, 45, 10).millisecondsSinceEpoch ~/ 1000;
      expect(offset({'timezone': 'Europe/Paris', 'timestamp_now': stamp, 'time_now': '2026-11-07 20:45:10'}), 3600);
      expect(offset({'timestamp_now': '$stamp', 'time_now': '2026-11-07 14:45:12'}), -5 * 3600);
      expect(offset({'timestamp_now': stamp, 'time_now': '2026-11-08 01:15:09'}), 5 * 3600 + 1800);
      expect(offset({'timestamp_now': stamp, 'time_now': '2026-11-07 19:45:10'}), 0);
      // Missing, unreadable or absurd: no offset rather than a wrong one.
      expect(offset(null), isNull);
      expect(offset({'url': 'srv'}), isNull);
      expect(offset({'timestamp_now': stamp, 'time_now': 'hier'}), isNull);
      expect(offset({'timestamp_now': 0, 'time_now': '2026-11-07 20:45:10'}), isNull);
      expect(offset({'timestamp_now': stamp, 'time_now': '2031-01-01 00:00:00'}), isNull);
    });

    test('credentials from get.php link', () {
      final c = XtreamCredentials.tryParse(
        'http://line.example.com:8080/get.php?username=bob&password=s3cr3t&type=m3u_plus&output=ts',
      )!;
      expect(c.server, 'http://line.example.com:8080');
      expect(c.username, 'bob');
      expect(c.password, 's3cr3t');
    });

    test('vod technical info gives quality tags', () {
      final d = parseVodInfo({
        'info': {
          'video': {'codec_name': 'hevc', 'width': 3840, 'height': 2160, 'color_transfer': 'smpte2084'},
          'audio': {'codec_name': 'eac3', 'channels': 6},
        },
      });
      expect(d.videoCodec, 'HEVC');
      expect(d.audioCodec, 'E-AC3');
      expect(d.qualityTags, ['4K', 'HDR', '5.1']);
      expect(
        parseVodInfo({
          'info': {'video': [], 'audio': []},
        }).qualityTags,
        isEmpty,
      );
    });

    test('vod duration formats', () {
      expect(parseDurationSec({'duration': '01:52:10'}), 6730);
      expect(parseDurationSec({'duration_secs': '95'}), 95);
    });
  });

  group('text', () {
    test('channel match keys', () {
      expect(channelMatchKey('FR: TF1 HD'), 'tf1');
      expect(channelMatchKey('|FR| France 2 FHD'), 'france2');
      expect(channelMatchKey('France 2'), 'france2');
      expect(channelMatchKey('Canal+ Sport (Backup)'), 'canalsport');
    });

    test('filter words match in any order', () {
      expect(matchesWords(searchKey('FR: TF1 HD'), searchWords('hd tf1')), isTrue);
      expect(matchesWords(searchKey('France 2 FHD'), searchWords('france fhd 2')), isTrue);
      expect(matchesWords(searchKey('France 3'), searchWords('france 2')), isFalse);
    });

    test('credentials are masked in messages', () {
      expect(
        redactCredentials('Adresse invalide : http://h/player_api.php?username=bob&password=s3cr3t&action=x'),
        'Adresse invalide : http://h/player_api.php?username=bob&password=***&action=x',
      );
      expect(
        redactCredentials('Failed to open http://h:8080/live/bob/s3cr3t/123.ts.'),
        'Failed to open http://h:8080/live/bob/***/123.ts.',
      );
      expect(redactCredentials('Connexion impossible'), 'Connexion impossible');
    });

    test('credentials are masked whatever the shape of the address', () {
      // M3U playlists exported by Xtream panels: no "/live/" in the address.
      expect(
        redactCredentials('mpv error: Failed to open http://h:8080/bob/s3cr3t/1234.ts.'),
        'mpv error: Failed to open http://h:8080/bob/***/1234.ts.',
      );
      expect(redactCredentials('http://h:8080/bob/s3cr3t/1234'), 'http://h:8080/bob/***/1234');
      expect(
        redactCredentials('Cast : ← https://h/bob/s3cr3t/77.mkv (relais)'),
        'Cast : ← https://h/bob/***/77.mkv (relais)',
      );
      expect(redactCredentials('http://bob:s3cr3t@h/list.m3u'), 'http://bob:***@h/list.m3u');
      expect(
        redactCredentials('uri = https://api.themoviedb.org/3/search/movie?api_key=abcdef123&query=dune'),
        'uri = https://api.themoviedb.org/3/search/movie?api_key=***&query=dune',
      );
      expect(redactCredentials('http://h/hls/bob/s3cr3t/1.m3u8'), 'http://h/hls/bob/***/1.m3u8');
      expect(redactCredentials('http://h/x?auth=abc&key=def&monkey=1'), 'http://h/x?auth=***&key=***&monkey=1');
      // Values bound to a failed SQL statement.
      expect(
        redactCredentials(
          'DB write failed: SqliteException(5): database is locked\n'
          '  Causing statement: UPDATE sources SET password = ? WHERE id = ?, parameters: s3cr3t, 1',
        ),
        'DB write failed: SqliteException(5): database is locked\n'
        '  Causing statement: UPDATE sources SET password = ? WHERE id = ?, parameters: ***',
      );
      // The shapes that used to come out whole.
      for (final (raw, masked) in [
        ('http://h.tv/playlist/bob/s3cret/m3u_plus', 'http://h.tv/playlist/bob/***/m3u_plus'),
        ('http://h.tv/timeshifts/bob/s3cret/60/5.ts', 'http://h.tv/timeshifts/bob/***/60/5.ts'),
        ('http://h.tv/hlsr/t0k3nAbc/bob/s3cret/5.m3u8', 'http://h.tv/hlsr/***/5.m3u8'),
        ('http://h.tv/hls/TOKENSECRET/123_45.ts', 'http://h.tv/hls/***/123_45.ts'),
        ('http://h.tv/play/AbC123xYz789/ts', 'http://h.tv/play/***/ts'),
        ('http://h.tv/x?play_token=AAAA1111&refresh_token=BBBB2222', 'http://h.tv/x?play_token=***&refresh_token=***'),
        ('http://h.tv/x?sign=CCCC3333&hash=DDDD4444&n=1', 'http://h.tv/x?sign=***&hash=***&n=1'),
        ('http://h.tv/x?wmsAuthSign=EEEE&auth_key=FFFF', 'http://h.tv/x?wmsAuthSign=***&auth_key=***'),
        ('http://h.tv/x?client_secret=GGGG', 'http://h.tv/x?client_secret=***'),
        (
          'http://r/?u=http%3A%2F%2Fh%2Fa%3Fpassword%3Ds3cret%26x%3D1',
          'http://r/?u=http%3A%2F%2Fh%2Fa%3Fpassword%3D***%26x%3D1',
        ),
        ('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.SECRET', 'Authorization: Bearer ***'),
        ('{"username":"bob","password":"s3cret"}', '{"username":"bob","password":"***"}'),
        ('{"refresh_token": "abc\\"def"}', '{"refresh_token": "***"}'),
        ('Failed to open http://h/bob/s3cret/123:', 'Failed to open http://h/bob/***/123:'),
        ('x, parameters: s3cret,\nsuite s3cret', 'x, parameters: ***'),
      ]) {
        expect(redactCredentials(raw), masked, reason: raw);
      }
      // Ordinary addresses and the relay's own are left readable.
      for (final plain in [
        'https://github.com/Weder77/Bobine/releases/tag/v1.6.5',
        'http://192.168.1.78:50311/c/0123456789abcdef0123456789abcdef/m/435092.mkv',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'Relais : télé HEAD → 200 video/x-matroska, 5,35 Go',
      ]) {
        expect(redactCredentials(plain), plain);
      }
    });

    test('search key folds accents', () {
      expect(searchKey('  Les Misérables  ÉTÉ '), 'les miserables ete');
    });

    test('stable hash is deterministic', () {
      expect(stableHash('abc'), stableHash('abc'));
      expect(stableHash('abc'), isNot(stableHash('abd')));
      expect(stableHash('abc').length, 16);
    });
  });
}
