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
}
