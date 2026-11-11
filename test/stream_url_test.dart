import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/import/importers.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/stream_urls.dart';
import 'package:bobine/player/play_items.dart';
import 'package:bobine/player/player_service.dart';

/// What a provider's playlist may name and the player must never open.
const _refused = [
  r'C:\Users\moi\bobine.db',
  '/home/moi/.ssh/id_rsa',
  'file:///etc/passwd',
  r'\\serveur\partage\x.ts',
  '//serveur/partage/x.ts',
  'edl://%10%/etc/passwd',
  'av://lavfi:testsrc',
  'concat:http://h/a.ts|/etc/passwd',
  'subfile,,start,0,end,10,,:/etc/passwd',
  'memory://texte',
  'tcp://127.0.0.1:22',
  'data:text/plain,hello',
  'asset://../../secret',
  'smb://serveur/partage/x.ts',
  'javascript:alert(1)',
  'http:///sans-hote',
  'relative/x.ts',
  '',
];

void main() {
  test('only network stream addresses are accepted', () {
    for (final ok in [
      'http://tv.example:8080/live/u/p/1.ts',
      'HTTPS://tv.example/hls/index.m3u8',
      'rtmp://live.example/app/stream',
      'rtsp://user:pass@cam.example/stream',
      'udp://@239.0.0.1:1234',
      'rtp://239.0.0.1:5000',
      'srt://h.example:9000',
      'mmsh://h.example/x',
      'http://h.example/x?utc={utc}&lutc={lutc}',
      '  http://h.example/1.ts  ',
    ]) {
      expect(isStreamUrl(ok), isTrue, reason: ok);
    }
    for (final no in _refused) {
      expect(isStreamUrl(no), isFalse, reason: no);
    }
  });

  test('the player opens network streams and the recordings, nothing else', () {
    PlayItem item(String url) => PlayItem(kind: ContentKind.live, sourceId: 1, extId: '1', url: url, title: 'Chaîne');
    expect(item('http://tv.example/live/u/p/1.ts').canOpen, isTrue);
    for (final no in _refused) {
      expect(item(no).canOpen, isFalse, reason: no);
    }
    final rec = recordingItem(
      Recording(
        id: 3,
        sourceId: 1,
        channelExt: '1',
        channelName: 'TF1',
        title: 'Le 20H',
        start: DateTime(2026),
        stop: DateTime(2026),
        path: r'C:\Users\moi\Videos\Bobine\TF1 - Le 20H.ts',
        status: RecordingStatus.done,
      ),
    );
    expect(rec.canOpen, isTrue);
  });

  test('mpv neither follows unsafe playlists nor lets FFmpeg read local files', () {
    expect(PlayerService.networkProps['load-unsafe-playlists'], 'no');
    expect(PlayerService.networkProps['ytdl'], 'no');
    expect(PlayerService.protocols, isNot(contains('file')));
    expect(PlayerService.networkProps['demuxer-lavf-o'], isNot(contains(',file,')));
  });

  group('M3U import', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('bobine_urls'));
    tearDown(() async => tmp.delete(recursive: true));

    test('entries that are not network streams are left out, and said so', () async {
      final list = File('${tmp.path}/liste.m3u')
        ..writeAsStringSync(
          [
            '#EXTM3U',
            '#EXTINF:-1 group-title="Infos",Info 24',
            'http://tv.example/live/u/p/1.ts',
            '#EXTINF:-1 group-title="Infos",Piège réseau',
            r'\\attaquant.example\partage\x.ts',
            '#EXTINF:-1 group-title="Infos",Piège fichier',
            'file:///etc/passwd',
            '#EXTINF:-1 group-title="Infos" catchup="default" catchup-source="file:///etc/{utc}",Replay piégé',
            'http://tv.example/live/u/p/2.ts',
            '#EXTINF:-1 group-title="Infos" catchup="default" catchup-source="http://tv.example/r/{utc}.ts",Replay',
            'http://tv.example/live/u/p/3.ts',
          ].join('\n'),
        );
      final path = '${tmp.path}/db.sqlite';
      final repo = Repository(openAppDatabase(path));
      addTearDown(repo.db.close);
      final id = repo.insertSource(name: 'Liste', type: SourceType.m3u, url: list.path);
      final result = await importM3u(path, id, null);
      expect(result.live, 3);
      final channels = repo.channels(id);
      expect(channels.map((c) => c.name), ['Info 24', 'Replay piégé', 'Replay']);
      expect(channels.every((c) => isStreamUrl(c.url!)), isTrue);
      expect(channels[1].catchupSource, isNull);
      expect(channels[2].catchupSource, 'http://tv.example/r/{utc}.ts');
      expect(repo.source(id)!.lastError, contains('2 entrée(s) ignorée(s)'));
    });

    test('a playlist with no network stream at all is refused, the channels stay', () async {
      final list = File('${tmp.path}/liste.m3u')
        ..writeAsStringSync('#EXTM3U\n#EXTINF:-1,Info\nhttp://tv.example/1.ts\n');
      final path = '${tmp.path}/db.sqlite';
      final repo = Repository(openAppDatabase(path));
      addTearDown(repo.db.close);
      final id = repo.insertSource(name: 'Liste', type: SourceType.m3u, url: list.path);
      await importM3u(path, id, null);
      list.writeAsStringSync('#EXTM3U\n#EXTINF:-1,Piège\n/etc/passwd\n');
      await expectLater(importM3u(path, id, null), throwsA(predicate((e) => '$e'.contains('Aucune adresse'))));
      expect(repo.channels(id).map((c) => c.name), ['Info']);
    });
  });
}
