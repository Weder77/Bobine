import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/format.dart';
import 'package:lumen/player/player_service.dart';

void main() {
  test('codec and channel labels', () {
    expect(codecLabel('eac3'), 'E-AC3');
    expect(codecLabel('subrip'), 'SRT');
    expect(codecLabel('xyz'), 'XYZ');
    expect(channelLayoutLabel(6), '5.1');
    expect(channelLayoutLabel(2), 'Stéréo');
    expect(channelLayoutLabel(3), '3 canaux');
  });

  test('video labels for the decoder badge', () {
    expect(videoCodecLabel('hevc'), 'HEVC');
    expect(videoCodecLabel('h264'), 'H.264');
    expect(videoResolutionLabel(3840, 2160), '4K');
    expect(videoResolutionLabel(3840, 1600), '4K'); // cinemascope
    expect(videoResolutionLabel(1920, 800), '1080p');
    expect(videoResolutionLabel(1280, 720), '720p');
    expect(videoResolutionLabel(720, 576), '576p');
    expect(videoResolutionLabel(0, 0), isNull);
    expect(formatFps(25.0001), '25');
    expect(formatFps(23.976), '23,98');
    expect(formatBytes(2.9 * 1024 * 1024), '2,9 Mo');
  });
}
