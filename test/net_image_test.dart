import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/text.dart';
import 'package:lumen/ui/widgets/net_image.dart';

/// A valid 1x1 PNG.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  testWidgets('DiskCachedImage resolves through ResizeImage', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lumen_img2');
    ImageFetcher.init(dir.path);
    const url = 'http://example.invalid/a.png';
    File('${dir.path}/${stableHash(url)}').writeAsBytesSync(_png);
    final info = await tester.runAsync(() async {
      final provider = ResizeImage.resizeIfNeeded(50, null, const DiskCachedImage(url));
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ImageInfo>();
      stream.addListener(ImageStreamListener((i, _) => completer.complete(i),
          onError: (e, _) => completer.completeError(e)));
      return completer.future.timeout(const Duration(seconds: 5));
    });
    expect(info!.image.width, 1);
  });

  testWidgets('NetImage shows a disk-cached image', (tester) async {
    final dir = Directory.systemTemp.createTempSync('lumen_img');
    ImageFetcher.init(dir.path);
    const url = 'http://example.invalid/poster.png';
    File('${dir.path}/${stableHash(url)}').writeAsBytesSync(_png);

    await tester.pumpWidget(const MaterialApp(
      home: Center(child: SizedBox(width: 100, height: 150, child: NetImage(url, decodeWidth: 100))),
    ));
    // Let the async file read + decode complete.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final image = tester.widget<RawImage>(find.byType(RawImage));
    expect(image.image, isNotNull, reason: 'decoded image should be painted');
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1);
  });
}
