import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/core/format.dart';
import 'package:bobine/core/text_decoding.dart';
import 'package:bobine/data/import/xmltv_parser.dart';
import 'package:bobine/ui/widgets/net_image.dart';

Future<String> _decode(List<int> bytes, {int chunk = 7, int sample = 64}) => decodeText(
  Stream.fromIterable([
    for (var i = 0; i < bytes.length; i += chunk) bytes.sublist(i, (i + chunk).clamp(0, bytes.length)),
  ]),
  sample: sample,
).join();

void main() {
  test('a web page or a message is not kept as a picture', () {
    expect(looksLikeImage([0xFF, 0xD8, 0xFF, ...List.filled(20, 0)]), isTrue);
    expect(looksLikeImage([0x89, 0x50, 0x4E, 0x47, ...List.filled(20, 0)]), isTrue);
    expect(looksLikeImage([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits, ...List.filled(8, 0)]), isTrue);
    expect(looksLikeImage(utf8.encode('<html><body>Not found</body></html>')), isFalse);
    expect(looksLikeImage(utf8.encode('{"error":"too many requests"}')), isFalse);
  });

  test('an expiry date out of range is no date', () {
    expect(accountExpiry(1893456000)!.year, 2030);
    expect(accountExpiry('1893456000')!.year, 2030);
    expect(accountExpiry(null), isNull);
    expect(accountExpiry(0), isNull);
    expect(accountExpiry(99999999999999), isNull); // threw before
    expect(accountExpiry('jamais'), isNull);
  });

  test('a guide or a playlist is read in the encoding it is written in', () async {
    final latin = latin1.encode('<?xml version="1.0" encoding="ISO-8859-1"?><tv><title>Météo à Noël</title></tv>');
    expect(await _decode(latin), contains('Météo à Noël'));
    // Windows-1252 without a declaration (not valid UTF-8): read as Latin-1.
    final ansi = latin1.encode('#EXTM3U\n#EXTINF:-1,Télé Matin\nhttp://h/1.ts\n${'x' * 100}');
    expect(await _decode(ansi), contains('Télé Matin'));
    // UTF-8, cut by the chunks in the middle of its characters.
    final text = '#EXTM3U\n#EXTINF:-1,Россия 1 · Télé\nhttp://h/1.ts\n${'é' * 200}';
    expect(await _decode(utf8.encode(text), chunk: 3), text);
    // Shorter than the sample.
    expect(await _decode(utf8.encode('Télé'), sample: 1 << 20), 'Télé');
  });

  test('guide times without seconds keep their zone', () {
    final withSeconds = parseXmltvTime('20240131203000 +0100');
    expect(parseXmltvTime('202401312030 +0100'), withSeconds);
    expect(parseXmltvTime('202401312030+0100'), withSeconds);
    expect(parseXmltvTime('20240131203000+0100'), withSeconds);
  });
}
