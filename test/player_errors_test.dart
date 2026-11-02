import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/player/player_service.dart';

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
}
