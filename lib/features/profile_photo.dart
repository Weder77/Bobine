import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;

/// A photo chosen for a profile, made small enough to travel with it: it is
/// part of the profile in backups and on the sync account, where a profile
/// must fit in one item (16 KB once encrypted).
class ProfilePhoto {
  ProfilePhoto._();

  /// How a photo is stored in `profiles.avatar`.
  static const prefix = 'data:image/jpeg;base64,';

  /// Largest file accepted, before it is reduced.
  static const maxInputBytes = 40 * 1024 * 1024;

  /// Largest picture decoded at full size (JPEG photos are decoded straight
  /// at a reduced size, whatever theirs): 64 MP already take about 200 MB.
  static const maxInputPixels = 64 * 1000 * 1000;

  /// Largest photo kept: with the profile's name, once encrypted and encoded,
  /// it stays well under the 16 KB of an item on the account.
  static const maxBytes = 8000;

  /// Sizes tried, sharpest first (the picker shows avatars at 128 px).
  static const _sizes = [192, 160, 128, 96, 64];
  static const _qualities = [88, 80, 72, 64, 56, 48, 40];

  /// Short side a picture is brought down to before it is cut: twice the
  /// largest size, so the last reduction still averages several pixels.
  static const _workSide = 384;

  /// The photo in [bytes] (JPEG, PNG, WebP, GIF, BMP…), cut to its centre
  /// square, as a value for `profiles.avatar`. A transparent picture is laid
  /// on [background] (ARGB). Null when the file is not a picture that can be
  /// read. Runs in another isolate: a large photo takes a moment to decode.
  static Future<String?> fromFile(Uint8List bytes, {int background = 0xFF1A1503}) =>
      Isolate.run(() => encode(bytes, background: background));

  /// [fromFile], on this isolate.
  static String? encode(Uint8List bytes, {int background = 0xFF1A1503}) {
    if (bytes.isEmpty || bytes.length > maxInputBytes) return null;
    final img.Image? decoded;
    try {
      decoded = _decode(bytes);
    } catch (_) {
      return null;
    }
    if (decoded == null || decoded.width < 1 || decoded.height < 1) return null;
    var src = decoded;
    // The JPEG decoder has already turned the picture upright.
    final ifd = src.exif.imageIfd;
    if (ifd.hasOrientation && ifd.orientation != 1) src = img.bakeOrientation(src);
    if (src.hasPalette) {
      // Palette pictures (GIF, PNG-8) cannot be averaged: a large one is
      // first brought near the working size (nearest pixel, all a palette
      // allows), then made RGB, so the per-pixel conversion stays small.
      final side = math.min(src.width, src.height);
      if (side > 2 * _workSide) src = _scaled(src, 2 * _workSide / side, img.Interpolation.nearest);
      src = _rgb8(src);
    }
    final short = math.min(src.width, src.height);
    // Reduced before being cut, so that no step copies it at full size.
    if (short > _workSide) src = _scaled(src, _workSide / short, img.Interpolation.average);
    src = _rgb8(src);
    final side = math.min(src.width, src.height);
    final square = img.copyCrop(
      src,
      x: (src.width - side) ~/ 2,
      y: (src.height - side) ~/ 2,
      width: side,
      height: side,
    );
    for (final size in _sizes) {
      final small = img.copyResize(
        square,
        width: size,
        height: size,
        interpolation: side > size ? img.Interpolation.average : img.Interpolation.cubic,
      );
      final flat = _flatten(small, background);
      for (final q in _qualities) {
        final jpg = img.encodeJpg(flat, quality: q);
        if (jpg.length <= maxBytes) return prefix + base64Encode(jpg);
      }
    }
    return null;
  }

  static img.Image _scaled(img.Image image, double factor, img.Interpolation interpolation) => img.copyResize(
    image,
    width: math.max(1, (image.width * factor).round()),
    height: math.max(1, (image.height * factor).round()),
    interpolation: interpolation,
  );

  /// The decoding step alone, to check the size a picture is decoded at.
  @visibleForTesting
  static img.Image? decodeForTest(Uint8List bytes) => _decode(bytes);

  /// First frame of the picture in [bytes]; null when it is not one, or too
  /// large to decode at full size. Its dimensions are read before anything
  /// is decoded.
  static img.Image? _decode(Uint8List bytes) {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (decoder == null || info == null || info.width < 1 || info.height < 1) return null;
    if (decoder is img.JpegDecoder) {
      // Decoded straight at 1/2, 1/4 or 1/8 of its size: fast, and small in memory.
      final short = math.min(info.width, info.height);
      var scale = 8;
      while (scale > 1 && short ~/ scale < _workSide) {
        scale ~/= 2;
      }
      return img.JpegDecoder(scale: scale).decode(bytes);
    }
    if (info.width * info.height > maxInputPixels) return null;
    return decoder.decode(bytes, frame: 0);
  }

  /// [image] as 8-bit RGB, or RGBA when it has transparency. A grey picture
  /// has one channel (two with transparency), and the JPEG encoder reads its
  /// green and blue as 0: it would come out red.
  static img.Image _rgb8(img.Image image) {
    if (image.format == img.Format.uint8 && !image.hasPalette && image.numChannels >= 3) return image;
    final alpha = image.hasAlpha;
    final grey = !image.hasPalette && image.numChannels <= 2;
    final out = img.Image(width: image.width, height: image.height, numChannels: alpha ? 4 : 3);
    int v(num n) => (n * 255).round().clamp(0, 255);
    for (final p in image) {
      final r = v(p.rNormalized);
      final g = grey ? r : v(p.gNormalized);
      final b = grey ? r : v(p.bNormalized);
      if (alpha) {
        out.setPixelRgba(p.x, p.y, r, g, b, v(p.aNormalized));
      } else {
        out.setPixelRgb(p.x, p.y, r, g, b);
      }
    }
    return out;
  }

  /// [image] without transparency, on [background].
  static img.Image _flatten(img.Image image, int background) {
    if (!image.hasAlpha) return image;
    final out = img.Image(width: image.width, height: image.height);
    img.fill(out, color: img.ColorRgb8((background >> 16) & 0xFF, (background >> 8) & 0xFF, background & 0xFF));
    return img.compositeImage(out, image);
  }

  /// Whether [avatar] is a photo.
  static bool isPhoto(String? avatar) => avatar != null && avatar.startsWith(prefix);

  /// The JPEG of a photo avatar; null for anything else or a damaged one.
  static Uint8List? bytesOf(String? avatar) {
    if (!isPhoto(avatar)) return null;
    try {
      final bytes = base64Decode(avatar!.substring(prefix.length));
      return bytes.isEmpty ? null : bytes;
    } on FormatException {
      return null;
    }
  }
}
