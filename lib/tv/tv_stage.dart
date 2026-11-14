import 'package:flutter/material.dart';

/// The 1920 × 1080 stage of the TV screens: they are laid out in the units
/// of the "Bobine TV" design and scaled to whatever the screen is.
class TvStage extends StatelessWidget {
  const TvStage({super.key, required this.child});

  final Widget child;

  static const size = Size(1920, 1080);

  @override
  Widget build(BuildContext context) {
    final outer = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    return ColoredBox(
      color: const Color(0xFF000000),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: outer.copyWith(size: size, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
              child: ClipRect(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
