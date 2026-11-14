import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pixels of the screen per point of a stage of [stage] size shown whole:
/// the ratio pictures are decoded at. The screen's own ratio would be far
/// too much (a 1080p box reports 2, and the stage is drawn at half size).
double stagePixelRatio(BuildContext context, Size stage, double fallback) {
  final phys = View.maybeOf(context)?.physicalSize ?? Size.zero;
  if (phys.isEmpty) return fallback;
  return math.min(phys.width / stage.width, phys.height / stage.height);
}

/// The 1920 × 1080 stage of the TV screens: they are laid out in the units
/// of the "Bobine TV" design and scaled to whatever the screen is.
class TvStage extends StatelessWidget {
  const TvStage({super.key, required this.child, this.background = const Color(0xFF000000)});

  final Widget child;

  /// Around the stage when the screen is not 16:9; transparent for a card
  /// over another screen.
  final Color background;

  static const size = Size(1920, 1080);

  @override
  Widget build(BuildContext context) {
    final outer = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    return ColoredBox(
      color: background,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: outer.copyWith(
                size: size,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                devicePixelRatio: stagePixelRatio(context, size, outer.devicePixelRatio),
                // The on-screen keyboard, in stage points.
                viewInsets: outer.size.isEmpty
                    ? EdgeInsets.zero
                    : outer.viewInsets / math.min(outer.size.width / size.width, outer.size.height / size.height),
              ),
              child: ClipRect(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
