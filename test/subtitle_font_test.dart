import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bobine/player/player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The family names (name ID 1, Windows platform) a TrueType font declares:
/// those libass matches `sub-font` against.
List<String> fontFamilies(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  final tables = d.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final record = 12 + 16 * i;
    if (ascii.decode(bytes.sublist(record, record + 4)) != 'name') continue;
    final table = d.getUint32(record + 8);
    final count = d.getUint16(table + 2);
    final strings = table + d.getUint16(table + 4);
    final names = <String>[];
    for (var j = 0; j < count; j++) {
      final r = table + 6 + 12 * j;
      if (d.getUint16(r) != 3 || d.getUint16(r + 6) != 1) continue;
      final start = strings + d.getUint16(r + 10);
      final units = [for (var k = 0; k < d.getUint16(r + 8); k += 2) d.getUint16(start + k)];
      names.add(String.fromCharCodes(units));
    }
    return names;
  }
  return const [];
}

void main() {
  test('libass on Android gets a bundled font, under the family name it declares', () {
    final font = File(PlayerService.subtitleFont);
    expect(font.existsSync(), isTrue, reason: 'media_kit copies it out of the assets');
    // Declared in pubspec.yaml, or it is not in the app's assets.
    expect(File('pubspec.yaml').readAsStringSync(), contains('- asset: ${PlayerService.subtitleFont}'));
    // A name libass does not find: no subtitles at all, and no error either.
    expect(fontFamilies(font.readAsBytesSync()), contains(PlayerService.subtitleFontName));
  });
}
