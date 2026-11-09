import 'package:bobine/player/reconnect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  ReconnectBudget budget() => ReconnectBudget(clock: () => now);
  void pass(Duration d) => now = now.add(d);

  setUp(() => now = DateTime(2026, 11, 9, 21));

  test('six attempts in a row, each after a longer wait, then it gives up', () {
    final b = budget();
    final waits = <int>[];
    for (var i = 0; i < 6; i++) {
      final wait = b.next()!;
      waits.add(wait.inMilliseconds);
      pass(wait);
      b.launched();
      pass(const Duration(seconds: 2)); // the stream fails again
    }
    expect(waits, [600, 1200, 1800, 2400, 3000, 3600]);
    expect(b.next(), isNull);
    expect(b.exhausted, isTrue);
  });

  test('several errors of one failure count once', () {
    final b = budget();
    expect(b.next(), isNotNull); // "tcp: connection refused"
    expect(b.next(), isNull); // "Failed to open …" for the same failure
    expect(b.next(), isNull);
    expect(b.attempts, 1);
    expect(b.exhausted, isFalse);
    b.launched();
    pass(const Duration(seconds: 1));
    expect(b.next()!.inMilliseconds, 1200);
  });

  test('a stream that held after an attempt gets all its attempts back', () {
    final b = budget();
    // Five hiccups over an evening, the stream coming back each time.
    for (var i = 0; i < 20; i++) {
      final wait = b.next();
      expect(wait?.inMilliseconds, 600, reason: 'hiccup $i');
      b.launched();
      pass(const Duration(minutes: 10));
    }
    expect(b.exhausted, isFalse);
  });

  test('another channel starts with a fresh count', () {
    final b = budget();
    for (var i = 0; i < 6; i++) {
      b.next();
      b.launched();
    }
    expect(b.next(), isNull);
    expect(b.exhausted, isTrue);
    b.reset(); // the user zaps
    expect(b.exhausted, isFalse);
    expect(b.next()!.inMilliseconds, 600);
  });
}
