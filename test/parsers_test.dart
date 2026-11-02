import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/text.dart';
import 'package:lumen/data/import/m3u_parser.dart';
import 'package:lumen/data/import/xmltv_parser.dart';
import 'package:lumen/data/import/xtream_api.dart';

void main() {
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
    test('parses chunked input, entities, CDATA and timezones', () {
      final progs = <List<Object?>>[];
      final chans = <String, List<String>>{};
      final p = XmltvParser(
        onProgramme: (c, s, e, t, d) => progs.add([c, s, e, t, d]),
        onChannel: (id, names) => chans[id] = names,
      );
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="x">
  <channel id="TF1.fr"><display-name lang="fr">TF1</display-name><display-name>TF1 HD</display-name><icon src="x"/></channel>
  <programme start="20240131200000 +0100" stop="20240131210000 +0100" channel="TF1.fr">
    <title lang="en">News</title><title lang="fr">Le JT &amp; la météo</title>
    <desc lang="fr"><![CDATA[Résumé <b>du</b> jour]]></desc>
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
      expect(progs[1][1], DateTime.utc(2024, 1, 31, 21).millisecondsSinceEpoch ~/ 1000);
      expect(progs[1][3], 'Film été');
    });

    test('time parsing variants', () {
      expect(parseXmltvTime('202401312000 -0230'),
          DateTime.utc(2024, 1, 31, 22, 30).millisecondsSinceEpoch ~/ 1000);
      expect(parseXmltvTime('bad'), isNull);
    });
  });

  group('Xtream', () {
    test('series info with map-of-seasons episodes', () {
      final info = parseSeriesInfo({
        'info': {'plot': 'Plot', 'backdrop_path': ['http://img/b.jpg'], 'rating': '8.1'},
        'episodes': {
          '2': [
            {'id': '22', 'episode_num': '1', 'title': 'S2E1', 'container_extension': 'mkv',
             'info': {'duration_secs': 1500, 'movie_image': 'http://img/e.jpg'}},
          ],
          '1': [
            {'id': '11', 'episode_num': 2, 'season': 1, 'title': 'S1E2'},
            {'id': '10', 'episode_num': 1, 'season': 1, 'title': 'S1E1', 'info': []},
          ],
        },
      }, 1, '500');
      expect(info.episodes.map((e) => e.extId), ['10', '11', '22']);
      expect(info.episodes.last.season, 2);
      expect(info.episodes.last.durationSec, 1500);
      expect(info.backdrop, 'http://img/b.jpg');
      expect(info.rating, 8.1);
    });

    test('credentials from get.php link', () {
      final c = XtreamCredentials.tryParse(
          'http://line.example.com:8080/get.php?username=bob&password=s3cr3t&type=m3u_plus&output=ts')!;
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
      expect(parseVodInfo({'info': {'video': [], 'audio': []}}).qualityTags, isEmpty);
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
      expect(redactCredentials('Adresse invalide : http://h/player_api.php?username=bob&password=s3cr3t&action=x'),
          'Adresse invalide : http://h/player_api.php?username=bob&password=***&action=x');
      expect(redactCredentials('Failed to open http://h:8080/live/bob/s3cr3t/123.ts.'),
          'Failed to open http://h:8080/live/bob/***/123.ts.');
      expect(redactCredentials('Connexion impossible'), 'Connexion impossible');
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
