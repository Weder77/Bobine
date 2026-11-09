import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bobine/cast/cast_device.dart';
import 'package:bobine/cast/cast_media.dart';
import 'package:bobine/cast/cast_service.dart';
import 'package:bobine/cast/cast_session.dart';
import 'package:bobine/cast/relay.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/player/player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A device that does what it is told, instantly.
class FakeSession implements CastSession {
  FakeSession(this.device);

  @override
  final CastDevice device;
  final loaded = <(CastMedia, Duration?)>[];
  final actions = <String>[];
  final _updates = StreamController<RemoteStatus>.broadcast();
  RemoteStatus next = RemoteStatus(state: RemoteState.playing);
  Object? failLoad;
  bool closed = false;

  @override
  InternetAddress? get localAddress => InternetAddress.loopbackIPv4;

  @override
  Stream<RemoteStatus> get updates => _updates.stream;

  void push(RemoteStatus s) => _updates.add(next = s);

  @override
  Future<void> connect() async => actions.add('connect');

  @override
  List<String> contentTypesFor(String url, {required bool live}) =>
      types ?? [castContentType(url, live: live, protocol: device.protocol)];

  /// Types to offer instead of Bobine's guess, and those the TV refuses (714).
  List<String>? types;
  Set<String> refused = {};

  @override
  Future<void> load(CastMedia media, {Duration? start}) async {
    if (failLoad != null) throw failLoad!;
    if (refused.contains(media.contentType)) {
      loaded.add((media, start));
      throw CastException('La télé ne lit pas ce type de flux.', code: 714, detail: 'Illegal MIME-type');
    }
    loaded.add((media, start));
  }

  @override
  Future<void> play() async => actions.add('play');

  @override
  Future<void> pause() async => actions.add('pause');

  @override
  Future<void> seek(Duration position) async => actions.add('seek ${position.inSeconds}');

  @override
  Future<void> setVolume(double level) async => actions.add('volume $level');

  @override
  Future<void> stop() async => actions.add('stop');

  @override
  Future<RemoteStatus> poll() async => next;

  @override
  Future<void> close() async {
    closed = true;
    actions.add('close');
  }
}

const _tv = CastDevice(id: 'tv', name: 'Salon', protocol: CastProtocol.chromecast, host: '127.0.0.1', port: 8009);
const _dlna = CastDevice(id: 'lg', name: 'Chambre', protocol: CastProtocol.dlna, host: '127.0.0.1', port: 1400);

PlayItem _movie({String url = 'http://host:8080/movie/u/p/9.mkv'}) => PlayItem(
  kind: ContentKind.movie,
  sourceId: 1,
  extId: '9',
  url: url,
  title: 'Le film',
  subtitle: '2024',
  image: 'http://img/p.jpg',
  userAgent: 'VLC/3.0',
);

PlayItem _channel() => const PlayItem(
  kind: ContentKind.live,
  sourceId: 1,
  extId: '7',
  url: 'http://host:8080/live/u/p/7.ts',
  title: '|FR| TF1 FHD',
);

Future<(int, Map<String, String>, List<int>)> _get(String url, {Map<String, String> headers = const {}}) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    final h = <String, String>{};
    res.headers.forEach((k, v) => h[k] = v.join(','));
    return (res.statusCode, h, body);
  } finally {
    c.close(force: true);
  }
}

void main() {
  group('relay', () {
    late HttpServer upstream;
    late CastRelay relay;
    final seenAgents = <String>[];

    setUp(() async {
      seenAgents.clear();
      relay = CastRelay();
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((req) async {
        final res = req.response;
        seenAgents.add(req.headers.value(HttpHeaders.userAgentHeader) ?? '');
        switch (req.uri.path) {
          case '/live.ts':
            if (req.headers.value(HttpHeaders.userAgentHeader) != 'VLC/3.0') {
              res.statusCode = 403;
              return res.close();
            }
            res.headers.contentType = ContentType('application', 'octet-stream');
            res.add(List.filled(188 * 4, 0x47));
            return res.close();
          case '/go.m3u8':
            return res.redirect(Uri.parse('/hls/index.m3u8'));
          case '/hls/index.m3u8':
            res.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
            res.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
              '#EXTINF:4.0,\nseg1.ts\n#EXTINF:4.0,\nhttp://127.0.0.1:${upstream.port}/other/seg2.ts?t=a b\n',
            );
            return res.close();
          case '/hls/seg1.ts':
            res.add(utf8.encode('SEGMENT-1'));
            return res.close();
          case '/nohead.mkv':
            // A provider that refuses HEAD and calls everything "video/mp4".
            if (req.method == 'HEAD') {
              res.statusCode = 405;
              return res.close();
            }
            final data = List.generate(5000, (i) => i % 256);
            final range = parseByteRange(req.headers.value(HttpHeaders.rangeHeader), data.length);
            res.headers.contentType = ContentType('video', 'mp4');
            if (range != null) {
              res.statusCode = 206;
              res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.$1}-${range.$2}/5000');
              res.add(data.sublist(range.$1, range.$2 + 1));
            } else {
              res.add(data);
            }
            return res.close();
          case '/movie.mp4':
            final data = List.generate(1000, (i) => i % 256);
            final range = parseByteRange(req.headers.value(HttpHeaders.rangeHeader), data.length);
            res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            res.headers.contentType = ContentType('video', 'mp4');
            if (range != null) {
              res.statusCode = 206;
              res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.$1}-${range.$2}/1000');
              res.add(data.sublist(range.$1, range.$2 + 1));
            } else {
              res.add(data);
            }
            return res.close();
        }
        res.statusCode = 404;
        await res.close();
      });
    });

    tearDown(() async {
      await relay.close();
      await upstream.close(force: true);
    });

    String up(String path) => 'http://127.0.0.1:${upstream.port}$path';

    test('streams with the source User-Agent, CORS and DLNA headers', () async {
      final link = await relay.publish(up('/live.ts'), host: InternetAddress.loopbackIPv4, userAgent: 'VLC/3.0');
      expect(link, matches(RegExp(r'^http://127\.0\.0\.1:\d+/c/[0-9a-f]{32}/m/live\.ts$')));
      final (status, headers, body) = await _get(link);
      expect(status, 200);
      expect(body.length, 188 * 4);
      expect(headers['access-control-allow-origin'], '*');
      expect(headers['transfermode.dlna.org'], 'Streaming');
      // The upstream type was generic: the relay names it from the extension.
      expect(headers['content-type'], 'video/mp2t');
      // Without the source's User-Agent the provider refuses.
      final plain = await relay.publish(up('/live.ts'), host: InternetAddress.loopbackIPv4);
      expect((await _get(plain)).$1, 403);
      expect(seenAgents.last, 'libmpv');
    });

    test('HLS: redirect followed, every address rewritten and served', () async {
      final link = await relay.publish(up('/go.m3u8'), host: InternetAddress.loopbackIPv4, userAgent: 'VLC/3.0');
      final (status, headers, body) = await _get(link);
      expect(status, 200);
      expect(headers['content-type'], 'application/vnd.apple.mpegurl');
      final lines = utf8.decode(body).split('\n');
      final origin = link.substring(0, link.indexOf('/c/'));
      final segments = lines.where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
      expect(segments, hasLength(2));
      for (final s in segments) {
        expect(s, startsWith('$origin/c/'));
      }
      expect(segments.first, endsWith('/seg1.ts'));
      expect(lines.firstWhere((l) => l.startsWith('#EXT-X-KEY')), contains('URI="$origin/c/'));
      final seg = await _get(segments.first);
      expect(utf8.decode(seg.$3), 'SEGMENT-1');
      expect(seenAgents.where((a) => a == 'VLC/3.0').length, greaterThanOrEqualTo(2));
    });

    test('HEAD refused by the provider; the TV gets the type it was told', () async {
      final link = await relay.publish(
        up('/nohead.mkv'),
        host: InternetAddress.loopbackIPv4,
        contentType: 'video/x-mkv',
      );
      final c = HttpClient();
      final head = await (await c.headUrl(Uri.parse(link))).close();
      await head.drain<void>();
      expect(head.statusCode, 200);
      expect(head.headers.contentLength, 5000);
      expect(head.headers.value('accept-ranges'), 'bytes');
      expect(head.headers.value('content-type'), 'video/x-mkv');
      c.close(force: true);
      final (status, headers, body) = await _get(link, headers: {'Range': 'bytes=0-'});
      expect(status, 206);
      expect(headers['content-type'], 'video/x-mkv');
      expect(headers['content-range'], 'bytes 0-4999/5000');
      expect(body.length, 5000);
    });

    test('byte ranges reach the provider (seeking in films)', () async {
      final link = await relay.publish(up('/movie.mp4'), host: InternetAddress.loopbackIPv4);
      final (status, headers, body) = await _get(link, headers: {'Range': 'bytes=100-199'});
      expect(status, 206);
      expect(headers['content-range'], 'bytes 100-199/1000');
      expect(body, List.generate(100, (i) => (i + 100) % 256));
    });

    test('local files with ranges; unknown addresses are refused', () async {
      final dir = await Directory.systemTemp.createTemp('bobine_relay');
      final file = File('${dir.path}/Enregistrement TF1.ts');
      await file.writeAsBytes(List.generate(500, (i) => i % 256));
      final link = await relay.publish(file.path, host: InternetAddress.loopbackIPv4);
      expect(link, endsWith('/Enregistrement_TF1.ts'));
      final whole = await _get(link);
      expect(whole.$1, 200);
      expect(whole.$3.length, 500);
      expect(whole.$2['content-type'], 'video/mp2t');
      final part = await _get(link, headers: {'Range': 'bytes=-50'});
      expect(part.$1, 206);
      expect(part.$2['content-range'], 'bytes 450-499/500');
      expect(part.$3.length, 50);
      expect((await _get(link, headers: {'Range': 'bytes=900-'})).$1, 416);
      final origin = link.substring(0, link.indexOf('/c/'));
      expect((await _get('$origin/c/0000/m/x.ts')).$1, 404);
      // A file route cannot be used to fetch other addresses.
      final token = Uri.parse(link).pathSegments[1];
      expect((await _get('$origin/c/$token/u/${encodeLink(Uri.parse(up('/live.ts')))}/x')).$1, 404);
      relay.clear();
      expect((await _get(link)).$1, 404);
      await dir.delete(recursive: true);
    });

    test('the provider connection ends when the TV stops reading', () async {
      // A provider sending a live stream forever (raw socket: it sees the hang-up).
      final provider = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final providerClosed = Completer<void>();
      provider.listen((sock) async {
        var closed = false;
        sock.listen(
          (_) {},
          onDone: () {
            closed = true;
            if (!providerClosed.isCompleted) providerClosed.complete();
          },
          onError: (Object _) => closed = true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        sock.write('HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\nConnection: close\r\n\r\n');
        for (var i = 0; i < 4000 && !closed; i++) {
          sock.add(List.filled(188 * 20, 0x47));
          try {
            await sock.flush();
          } catch (_) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        sock.destroy();
      });
      final link = await relay.publish(
        'http://127.0.0.1:${provider.port}/live/u/p/1.ts',
        host: InternetAddress.loopbackIPv4,
      );
      final tv = await Socket.connect(InternetAddress.loopbackIPv4, Uri.parse(link).port);
      tv.write('GET ${Uri.parse(link).path} HTTP/1.1\r\nHost: x\r\n\r\n');
      final head = StringBuffer();
      var got = 0;
      final enough = Completer<void>();
      tv.listen((chunk) {
        if (!head.toString().contains('\r\n\r\n') && head.length < 4000) {
          head.write(latin1.decode(chunk.take(400).toList(), allowInvalid: true));
        }
        got += chunk.length;
        if (got > 60000 && !enough.isCompleted) enough.complete();
      }, onError: (Object _) {});
      await enough.future.timeout(const Duration(seconds: 10));
      expect(head.toString(), startsWith('HTTP/1.1 200'));
      expect(head.toString().toLowerCase(), contains('content-type: video/mp2t'));
      tv.destroy();
      await providerClosed.future.timeout(const Duration(seconds: 10));
      await provider.close();
    });

    test('byte range header', () {
      expect(parseByteRange(null, 100), isNull);
      expect(parseByteRange('bytes=0-', 100), (0, 99));
      expect(parseByteRange('bytes=10-20', 100), (10, 20));
      expect(parseByteRange('bytes=90-500', 100), (90, 99));
      expect(parseByteRange('bytes=-10', 100), (90, 99));
      expect(parseByteRange('bytes=100-', 100), badRange);
      expect(parseByteRange('items=1-2', 100), isNull);
    });

    test('playlist rewriting keeps tags and resolves relative addresses', () {
      final out = rewritePlaylist(
        '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n\n#EXTINF:2,\n../a/1.ts\n',
        Uri.parse('http://h/x/y/index.m3u8'),
        (u) => 'R[$u]',
      );
      expect(out, '#EXTM3U\n#EXT-X-MAP:URI="R[http://h/x/y/init.mp4]"\n\n#EXTINF:2,\nR[http://h/x/a/1.ts]\n');
    });
  });

  group('CastService', () {
    late FakeSession session;
    late CastService cast;

    setUp(() {
      cast = CastService(
        sessionFactory: (d) => session = FakeSession(d),
        describe: (item) => (item.isLive ? 'TF1' : item.title, item.isLive ? 'Le journal' : item.subtitle),
        browsers: [
          (t, add) async {
            add(_dlna);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            add(_tv);
          },
        ],
      );
    });

    test('a TV that never asks the relay for the stream: firewall hint', () async {
      final stuck = CastService(
        loadTimeout: const Duration(milliseconds: 600),
        sessionFactory: (d) => session = FakeSession(d)..next = RemoteStatus(state: RemoteState.loading),
      );
      await stuck.start(_dlna, _movie(url: 'http://127.0.0.1:9/series/u/p/1.mkv'));
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(stuck.error, contains('pare-feu'));
      // Once the TV reached the relay, the failure is about the stream itself.
      await stuck.retry();
      final link = session.loaded.single.$1.url;
      expect((await _get(link)).$1, greaterThanOrEqualTo(400));
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(stuck.error, "La télé n'arrive pas à lire ce flux.");
      await stuck.stop();
    });

    test('a type refused with 714 is offered again under its other spellings', () async {
      final picky = CastService(
        sessionFactory: (d) => session = FakeSession(d)
          ..types = ['video/x-matroska', 'video/x-mkv']
          ..refused = {'video/x-matroska'},
      );
      await picky.start(_dlna, _movie());
      expect(session.loaded.map((l) => l.$1.contentType), ['video/x-matroska', 'video/x-mkv']);
      // Each try gets its own relay address served with its type.
      expect(session.loaded.first.$1.url, isNot(session.loaded.last.$1.url));
      expect(picky.error, isNull);
      await picky.stop();

      final none = CastService(
        sessionFactory: (d) => session = FakeSession(d)
          ..types = ['video/x-matroska', 'video/x-mkv']
          ..refused = {'video/x-matroska', 'video/x-mkv'},
      );
      await none.start(_dlna, _movie());
      expect(none.error, 'La télé ne lit pas ce type de flux.');
      await none.stop();
    });

    test('search lists the devices by name', () async {
      await cast.scan();
      expect(cast.devices.value.map((d) => d.name), ['Chambre', 'Salon']);
      expect(cast.scanning.value, isFalse);
    });

    test('a film goes through the relay, from where it was, with clean titles', () async {
      await cast.start(_tv, _movie(), start: const Duration(minutes: 12));
      expect(cast.active, isTrue);
      expect(session.actions.first, 'connect');
      final (media, start) = session.loaded.single;
      expect(media.url, matches(RegExp(r'^http://127\.0\.0\.1:\d+/c/[0-9a-f]{32}/m/9\.mkv$')));
      expect(media.contentType, 'video/mp4');
      expect(media.live, isFalse);
      expect(media.title, 'Le film');
      expect(start, const Duration(minutes: 12));
      expect(cast.viaRelay, isTrue);
    });

    test('direct mode gives the provider address; Xtream live in HLS for Chromecast', () async {
      cast.preferRelay = false;
      await cast.start(_tv, _channel());
      final (media, start) = session.loaded.single;
      expect(media.url, 'http://host:8080/live/u/p/7.m3u8');
      expect(media.contentType, 'application/x-mpegURL');
      expect(media.live, isTrue);
      expect(media.title, 'TF1');
      expect(media.subtitle, 'Le journal');
      expect(start, isNull);
      // A DLNA TV gets the stream as it is.
      await cast.start(_dlna, _channel());
      expect(session.loaded.single.$1.url, 'http://host:8080/live/u/p/7.ts');
      expect(session.loaded.single.$1.contentType, 'video/mp2t');
    });

    test('recordings always go through the relay', () async {
      cast.preferRelay = false;
      await cast.start(_dlna, _movie(url: r'C:\Videos\Bobine\film.ts'));
      expect(session.loaded.single.$1.url, contains('/c/'));
      expect(cast.viaRelay, isTrue);
    });

    test('controls, position between updates, and stop', () async {
      await cast.start(_tv, _movie());
      session.push(
        RemoteStatus(
          state: RemoteState.playing,
          position: const Duration(seconds: 100),
          duration: const Duration(minutes: 90),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(cast.playing, isTrue);
      expect(cast.position.inMilliseconds, greaterThanOrEqualTo(100000));
      await cast.seekBy(const Duration(seconds: 30));
      expect(session.actions.last, startsWith('seek 13'));
      // The TV still reports the old position just after a seek: ignored.
      session.push(
        RemoteStatus(
          state: RemoteState.playing,
          position: const Duration(seconds: 101),
          duration: const Duration(minutes: 90),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cast.position.inSeconds, greaterThanOrEqualTo(130));
      await cast.pause();
      expect(session.actions.last, 'pause');
      expect(cast.playing, isFalse);
      cast.setVolume(0.3);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(session.actions.last, 'volume 0.3');
      final at = await cast.stop();
      expect(at!.inSeconds, greaterThanOrEqualTo(130));
      expect(cast.active, isFalse);
      expect(cast.item.value, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.actions.sublist(session.actions.length - 2), ['stop', 'close']);
    });

    test('end of a film is counted once; a refused stream shows an error and retries', () async {
      await cast.start(_tv, _movie());
      session.push(RemoteStatus(state: RemoteState.ended, duration: const Duration(minutes: 90)));
      session.push(RemoteStatus(state: RemoteState.ended, duration: const Duration(minutes: 90)));
      await Future<void>.delayed(Duration.zero);
      expect(cast.endedCount, 1);

      final failing = CastService(
        sessionFactory: (d) => session = FakeSession(d)..failLoad = CastException("La télé n'a pas pu lire ce flux."),
      );
      await failing.start(_tv, _movie());
      expect(failing.error, "La télé n'a pas pu lire ce flux.");
      expect(failing.active, isTrue);
      expect(failing.viaRelay, isTrue);
      await failing.retry(viaRelay: false);
      expect(failing.preferRelay, isFalse);
      expect(session.actions.first, 'connect');
    });

    test('stopping before the TV started gives back where the film was, not zero', () async {
      final slow = CastService(
        sessionFactory: (d) => session = FakeSession(d)..next = RemoteStatus(state: RemoteState.loading),
      );
      await slow.start(_tv, _movie(), start: const Duration(minutes: 45));
      // The TV reports position 0 while it loads (or after refusing the stream).
      session.push(RemoteStatus(state: RemoteState.loading));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(slow.position, Duration.zero);
      expect(await slow.stop(), const Duration(minutes: 45));

      // Once it played, the TV's own position counts, even an earlier one.
      await slow.start(_tv, _movie(), start: const Duration(minutes: 45));
      session.push(RemoteStatus(state: RemoteState.paused, position: const Duration(minutes: 45)));
      session.push(RemoteStatus(state: RemoteState.playing, position: const Duration(minutes: 45)));
      session.push(RemoteStatus(state: RemoteState.paused, position: const Duration(minutes: 12)));
      await Future<void>.delayed(Duration.zero);
      expect(await slow.stop(), const Duration(minutes: 12));

      // A film sent from its beginning to a TV that never started: no position.
      await slow.start(_tv, _movie());
      expect(await slow.stop(), isNull);
    });

    test('zapping loads the new channel on the same connection', () async {
      await cast.start(_tv, _channel());
      final first = session;
      await cast.load(_movie());
      expect(identical(first, session), isTrue);
      expect(session.loaded, hasLength(2));
      expect(cast.item.value!.extId, '9');
    });
  });
}
