import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bobine/core/net.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers one request by hand: what a real server never does on purpose,
/// and what a provider's server does when it falls over.
Future<ServerSocket> rawServer(void Function(Socket socket) answer) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    // The request is not read further than its first bytes.
    late StreamSubscription<List<int>> sub;
    sub = socket.listen((_) {
      sub.pause();
      answer(socket);
    }, onError: (_) {});
  });
  return server;
}

void main() {
  group('guardBody', () {
    test('passes an ordinary answer through untouched', () async {
      final chunks = [
        [1, 2, 3],
        [4],
        <int>[],
        [5, 6],
      ];
      final out = await guardBody(Stream.fromIterable(chunks), maxBytes: 6).toList();
      expect(out, chunks);
    });

    test('gives up when the server stops sending', () async {
      final source = StreamController<List<int>>();
      addTearDown(source.close);
      source.add([1, 2, 3]);
      final received = <List<int>>[];
      await expectLater(
        guardBody(source.stream, stall: const Duration(milliseconds: 80)).forEach(received.add),
        throwsA(isA<NetException>().having((e) => e.message, 'message', contains('cessé'))),
      );
      // What had arrived was passed on, and the source is let go.
      expect(received, [
        [1, 2, 3],
      ]);
      expect(source.hasListener, isFalse);
    });

    test('a slow but steady answer is not a stalled one', () async {
      Stream<List<int>> slow() async* {
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          yield [i];
        }
      }

      // 200 ms in all, never more than 40 ms of silence.
      final out = await guardBody(slow(), stall: const Duration(milliseconds: 150)).toList();
      expect(out, hasLength(5));
    });

    test('stops an answer that grows beyond the limit', () async {
      Stream<List<int>> endless() async* {
        while (true) {
          yield List<int>.filled(1000, 0x41);
        }
      }

      var seen = 0;
      await expectLater(
        guardBody(endless(), maxBytes: 10000).forEach((c) => seen += c.length),
        throwsA(isA<NetException>().having((e) => e.message, 'message', contains('trop volumineuse'))),
      );
      expect(seen, 10000);
    });

    test('the limit counts what the compression unfolds to', () async {
      // 8 MB of zeros: a few kB once compressed.
      final bomb = gzip.encode(List<int>.filled(8 << 20, 0));
      expect(bomb.length, lessThan(64 << 10));
      await expectLater(
        guardBody(gunzipIfNeeded(Stream.value(bomb)), maxBytes: 1 << 20).drain<void>(),
        throwsA(isA<NetException>()),
      );
    });

    test('damaged compression is reported, not thrown raw', () async {
      final damaged = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3, ...List<int>.filled(64, 0xFF)];
      await expectLater(
        guardBody(gunzipIfNeeded(Stream.value(damaged))).drain<void>(),
        throwsA(isA<NetException>().having((e) => e.message, 'message', contains('illisible'))),
      );
    });
  });

  group('limitLineLength', () {
    test('lets ordinary lines through, whatever the chunking', () async {
      final line = 'x' * 300;
      final chunks = ['$line\n$line', '$line\r\n', line, '\n$line'];
      final out = await limitLineLength(Stream.fromIterable(chunks), max: 700).toList();
      expect(out, chunks);
    });

    test('refuses a file made of one endless line', () async {
      Stream<String> endless() async* {
        while (true) {
          yield 'x' * 400;
        }
      }

      var chunks = 0;
      await expectLater(
        limitLineLength(endless(), max: 1000).forEach((_) => chunks++),
        throwsA(isA<NetException>().having((e) => e.message, 'message', contains('ligne'))),
      );
      expect(chunks, 2);
    });
  });

  group('getText', () {
    late HttpClient client;
    setUp(() => client = createHttpClient());
    tearDown(() => client.close(force: true));

    test('a connection that drops in the middle is a readable error, without the password', () async {
      final server = await rawServer((socket) async {
        socket.write('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 5000\r\n\r\n[{"name":');
        await socket.flush();
        socket.destroy();
      });
      addTearDown(server.close);
      final uri = Uri.parse('http://127.0.0.1:${server.port}/player_api.php?username=jean&password=s3cret');
      await expectLater(
        getText(client, uri),
        throwsA(
          isA<NetException>()
              .having((e) => e.message, 'message', contains('interrompue'))
              .having((e) => e.toString(), 'text', isNot(contains('s3cret'))),
        ),
      );
    });

    test('a whole answer still arrives, compressed or not', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final body = jsonEncode([
        for (var i = 0; i < 2000; i++) {'name': 'Chaîne $i', 'stream_id': i},
      ]);
      server.listen((req) {
        if (req.uri.path == '/raw.gz') {
          // Served as a file, without Content-Encoding.
          req.response.headers.contentType = ContentType.binary;
          req.response.add(gzip.encode(utf8.encode(body)));
        } else {
          req.response.write(body);
        }
        req.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      expect(await getText(client, Uri.parse('$base/plain')), body);
      expect(await getText(client, Uri.parse('$base/raw.gz')), body);
      expect((await getJson(client, Uri.parse('$base/plain')) as List).length, 2000);
    });
  });
}
