import 'dart:io';

import 'package:bobine/data/db.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/player/player_service.dart';

void main() {
  test('only network / loading failures are fatal', () {
    for (final fatal in [
      'Failed to open http://srv/live/u/p/1.ts.',
      'Failed to recognize file format.',
      'tcp: Connection to tcp://srv:80 failed: Connection refused',
      'HTTP error 403 Forbidden',
      'Server returned 404 Not Found',
    ]) {
      expect(PlayerService.isFatalError(fatal), isTrue, reason: fatal);
    }
    for (final benign in [
      'Could not open/initialize audio device -> no sound.',
      'Error while decoding frame!',
      'Invalid audio PTS: 3.2 -> 3.4',
    ]) {
      expect(PlayerService.isFatalError(benign), isFalse, reason: benign);
    }
  });

  test('growing the mini-player back resumes a paused film, not a finished one', () {
    expect(PlayerService.resumesOnReopen(playing: false, completed: false), isTrue);
    // "Play" on a finished film starts it again from zero.
    expect(PlayerService.resumesOnReopen(playing: false, completed: true), isFalse);
    expect(PlayerService.resumesOnReopen(playing: true, completed: false), isFalse);
  });

  test('a screen replaced by another one is told so, whatever both play', () {
    final repo = Repository(openMemoryDatabase());
    final ps = PlayerService(AppSettings(repo), Directory.systemTemp.path);
    // What each playback screen notes when it opens.
    final film = ps.takeovers;
    // A reminder's "Regarder" opens the channel in its place.
    ps.takeOver();
    final channel = ps.takeovers;
    expect(ps.takeovers != film, isTrue, reason: 'the film screen was replaced: it must not stop the engine');
    expect(ps.takeovers != channel, isFalse, reason: 'the new screen owns the engine, and stops it when it closes');
  });

  group('what is shown to the user', () {
    const loading = Duration.zero;
    const film = Duration(minutes: 95);
    bool shown(String message, {required bool live, required bool playing, required Duration duration}) =>
        PlayerService.stopsPlayback(message, live: live, playing: playing, duration: duration);

    test('a film whose link is dead is an error, not an endless loading', () {
      // The engine still says "playing": nothing was paused.
      for (final m in ['Failed to open http://srv/movie/u/p/5.mkv.', 'Failed to recognize file format.']) {
        expect(shown(m, live: false, playing: true, duration: loading), isTrue, reason: m);
      }
    });

    test('a first connection the engine retries by itself is not shown', () {
      const retried = 'tcp: Connection to tcp://[2a01:e0a::1]:80 failed: Network is unreachable';
      expect(PlayerService.isFatalError(retried), isTrue);
      expect(shown(retried, live: false, playing: true, duration: loading), isFalse);
    });

    test('nothing is shown over a film that plays', () {
      expect(shown('tcp: Connection timed out', live: false, playing: true, duration: film), isFalse);
      expect(shown('Failed to open http://srv/sub.srt.', live: false, playing: true, duration: film), isFalse);
    });

    test('a live stream is left to the automatic reconnection', () {
      expect(shown('Failed to open http://srv/live/u/p/1.ts.', live: true, playing: true, duration: loading), isFalse);
    });

    test('whatever stopped playback is shown, as before', () {
      expect(shown('HTTP error 403 Forbidden', live: false, playing: false, duration: film), isTrue);
      expect(shown('Failed to open http://srv/live/u/p/1.ts.', live: true, playing: false, duration: loading), isTrue);
    });

    test('a message that is not fatal is never shown', () {
      for (final m in ['Error while decoding frame!', 'Could not open/initialize audio device -> no sound.']) {
        expect(shown(m, live: false, playing: false, duration: loading), isFalse, reason: m);
        expect(shown(m, live: false, playing: true, duration: loading), isFalse, reason: m);
      }
    });
  });

  test('a film that stops long before its end was cut, not finished', () {
    const film = Duration(minutes: 100);
    expect(PlayerService.endedEarly(position: const Duration(minutes: 40), duration: film), isTrue);
    expect(PlayerService.endedEarly(position: const Duration(minutes: 99, seconds: 50), duration: film), isFalse);
    expect(PlayerService.endedEarly(position: film, duration: film), isFalse);
    // Unknown length: nothing to compare with.
    expect(PlayerService.endedEarly(position: Duration.zero, duration: Duration.zero), isFalse);
    // A short clip: half a minute of margin.
    expect(
      PlayerService.endedEarly(position: const Duration(seconds: 50), duration: const Duration(minutes: 1)),
      isFalse,
    );
  });
}
