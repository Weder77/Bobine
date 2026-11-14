import 'dart:io';

import 'package:flutter/foundation.dart';

/// What this device can do. Bobine runs on Android only as a TV app (the
/// manifest requires `android.software.leanback`), so "Android" means "TV":
/// remote control, no file picker, a small box that decodes two streams at
/// most, updates through the Play Store only.
abstract final class Device {
  /// Forces [isTv] in tests (null: the real platform).
  @visibleForTesting
  static bool? debugTv;

  static bool get isTv => debugTv ?? (!kIsWeb && Platform.isAndroid);

  /// Sending to another TV from the TV makes no sense.
  static bool get canCast => !isTv;

  /// A recording of several hours fills the few gigabytes of a TV box.
  static bool get canRecord => !isTv;

  /// Most TVs have no document picker to open a file with.
  static bool get canPickFiles => !isTv;

  /// The Play Store forbids an app to update itself.
  static bool get canSelfUpdate => !isTv;

  /// The picture above the seek bar needs a second, software decoder.
  static bool get seekPreview => !isTv;

  /// Channels at once in the multi-view (hardware decoders of a box).
  static int get maxMultiSlots => isTv ? 2 : 4;
}
