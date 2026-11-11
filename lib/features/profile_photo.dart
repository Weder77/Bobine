import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

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

  /// Largest photo kept: with the profile's name, once encrypted and encoded,
  /// it stays well under the 16 KB of an item on the account.
  static const maxBytes = 8000;

  /// Sizes tried, sharpest first (the picker shows avatars at 128 px).
  static const _sizes = [192, 160, 128, 96, 64];
  static const _qualities = [88, 80, 72, 64, 56, 48, 40];

  /// The photo in [bytes] (JPEG, PNG, WebP, GIF, BMP…), cut to its centre
  /// square, as a value for `profiles.avatar`. A transparent picture is laid
  /// on [background] (ARGB). Null when the file is not a picture that can be
  /// read. Runs in another isolate: a large photo takes a moment to decode.
  static Future<String?> fromFile(Uint8List bytes, {int background = 0xFF1A1503}) =>
      Isolate.run(() => encode(bytes, background: background));

  /// [fromFile], on this isolate.
  static String? encode(Uint8List bytes, {int background = 0xFF1A1503}) {
    if (bytes.isEmpty || bytes.length > maxInputBytes) return null;
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes, frame: 0);
    } catch (_) {
      return null;
    }
    if (decoded == null || decoded.width < 1 || decoded.height < 1) return null;
    var src = img.bakeOrientation(decoded);
    if (src.hasPalette || src.format != img.Format.uint8) {
      src = src.convert(format: img.Format.uint8, numChannels: src.hasAlpha ? 4 : 3);
    }
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
