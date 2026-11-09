import 'dart:async';

import 'package:bobine/player/seek_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Duration s(int seconds) => Duration(seconds: seconds);

void main() {
  group('when the picture may be fetched', () {
    bool allowed(String mode, {bool local = false, int? max, int inUse = 1}) =>
        seekPreviewAllowed(mode: mode, local: local, maxConnections: max, inUse: inUse);

    test('never with a single connection, unless the user insists', () {
      // The second connection could make the provider close the film.
      expect(allowed('auto', max: 1), isFalse);
      expect(allowed('always', max: 1), isTrue);
    });

    test('yes when the subscription has room, or does not say', () {
      expect(allowed('auto', max: 2), isTrue);
      expect(allowed('auto'), isTrue);
      // "0" is how some panels write "no limit".
      expect(allowed('auto', max: 0), isTrue);
    });

    test('a recording in progress takes a connection too', () {
      expect(allowed('auto', max: 2, inUse: 2), isFalse);
      expect(allowed('auto', max: 3, inUse: 2), isTrue);
    });

    test('a file on disk costs no connection', () {
      expect(allowed('auto', local: true, max: 1), isTrue);
    });

    test('off is off', () {
      expect(allowed('never'), isFalse);
      expect(allowed('never', local: true), isFalse);
    });

    test('recordings are local, streams are not', () {
      for (final local in [r'C:\Users\moi\Videos\Bobine\Match.ts', '/home/moi/Vidéos/Match.ts', 'file:///tmp/a.mkv']) {
        expect(isLocalMedia(local), isTrue, reason: local);
      }
      for (final remote in ['http://srv/movie/u/p/5.mkv', 'HTTPS://srv/a.m3u8', 'rtsp://srv/x']) {
        expect(isLocalMedia(remote), isFalse, reason: remote);
      }
    });
  });

  test('the step follows the length of the film', () {
    expect(seekPreviewStep(const Duration(minutes: 3)), s(1));
    expect(seekPreviewStep(const Duration(minutes: 40)), s(6));
    expect(seekPreviewStep(const Duration(hours: 3)), s(10));
    expect(seekPreviewStep(Duration.zero), s(1));
  });

  group('PreviewQueue', () {
    late List<Duration> jumps;
    late List<Completer<void>> pending;
    late PreviewQueue queue;

    setUp(() {
      jumps = [];
      pending = [];
      queue = PreviewQueue((at) {
        jumps.add(at);
        final c = Completer<void>();
        pending.add(c);
        return c.future;
      })..step = s(5);
    });

    Future<void> land() async {
      pending.removeAt(0).complete();
      await pumpEventQueue();
    }

    test('one jump at a time, and only the latest position wanted', () async {
      queue.want(s(100));
      await pumpEventQueue();
      expect(jumps, [s(100)]);
      expect(queue.busy.value, isTrue);

      // The pointer keeps moving while the first picture is fetched.
      for (final at in [200, 300, 400, 500]) {
        queue.want(s(at));
      }
      await pumpEventQueue();
      expect(jumps, [s(100)], reason: 'nothing is asked while a jump is in flight');

      await land();
      expect(jumps, [s(100), s(500)], reason: 'the positions crossed on the way are skipped');
      expect(queue.busy.value, isTrue);

      await land();
      expect(jumps, hasLength(2));
      expect(queue.busy.value, isFalse);
      expect(queue.last, s(500));
    });

    test('a move too small for another picture asks for nothing', () async {
      queue.want(s(100));
      await land();
      queue.want(s(103));
      queue.want(s(97));
      await pumpEventQueue();
      expect(jumps, [s(100)]);
      expect(queue.busy.value, isFalse);

      queue.want(s(105));
      await pumpEventQueue();
      expect(jumps, [s(100), s(105)]);
      await land();
    });

    test('coming back near the picture shown asks for nothing', () async {
      queue.want(s(100));
      await pumpEventQueue();
      queue.want(s(900));
      queue.want(s(102));
      await land();
      // 900 was only crossed: the picture shown is still the one of 100.
      expect(jumps, [s(100)]);
      expect(queue.busy.value, isFalse);
    });

    test('another film starts from nothing', () async {
      queue.want(s(100));
      await land();
      queue.reset();
      queue.want(s(101));
      await pumpEventQueue();
      expect(jumps, [s(100), s(101)]);
      await land();
    });

    test('a jump that fails does not stop the following ones', () async {
      final failing = PreviewQueue((at) async {
        jumps.add(at);
        if (jumps.length == 1) throw StateError('player gone');
      })..step = s(5);
      failing.want(s(10));
      await pumpEventQueue();
      failing.want(s(60));
      await pumpEventQueue();
      expect(jumps, [s(10), s(60)]);
      expect(failing.busy.value, isFalse);
    });
  });
}
