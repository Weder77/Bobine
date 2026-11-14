import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/launch.dart';

/// Page of a series on the TV (temporary: the computer page until the TV
/// one is built).
class TvSeriesScreen {
  static Future<void> open(BuildContext context, Series series) => Launch.openSeries(context, series);
}
