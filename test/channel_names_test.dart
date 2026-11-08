import 'package:bobine/core/text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleanChannelName strips prefixes, qualities and symbols', () {
    expect(cleanChannelName('|FR| TF1 FHD ★'), 'TF1');
    expect(cleanChannelName('FR: FRANCE 2 HD'), 'France 2');
    expect(cleanChannelName('|FR| CANAL+ ᴴᴰ'), 'Canal+');
    expect(cleanChannelName('FR - BFMTV'), 'BFMTV');
    expect(cleanChannelName('[FR] Arte (1080p)'), 'Arte');
    expect(cleanChannelName('France 3 Paris Île-de-France'), 'France 3 Paris Île-de-France');
    expect(cleanChannelName('★★★'), '★★★');
  });

  test('channelQuality and ranks', () {
    expect(channelQuality('|FR| TF1 FHD'), 'FHD');
    expect(channelQuality('TF1 4K'), '4K');
    expect(channelQuality('TF1 HD'), 'HD');
    expect(channelQuality('TF1 SD'), 'SD');
    expect(channelQuality('CANAL+ ᴴᴰ'), 'HD');
    expect(channelQuality('TF1'), isNull);
    expect(qualityRank('FHD') > qualityRank('HD'), isTrue);
    expect(qualityRank(null) > qualityRank('SD'), isTrue);
  });
}
