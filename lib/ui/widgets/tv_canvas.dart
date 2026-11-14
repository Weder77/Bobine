import 'package:flutter/widgets.dart';

/// Lays the whole app out on a fixed 1280 × 720 stage, scaled to fill the
/// screen (letterboxed when the screen is not 16:9).
///
/// A 1080p TV reports itself to Flutter as 960 × 540 logical points, too
/// small for screens drawn for a computer; on the stage they get the room
/// of a 1280 × 720 window, and text stays sharp (the scaling happens when
/// painting, at the screen's resolution). Taps are scaled back the same way.
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});

  final Widget child;

  static const Size size = Size(1280, 720);

  /// Margin kept clear of the TV's edges (Android TV guidelines: 5 %).
  static const EdgeInsets safe = EdgeInsets.symmetric(horizontal: 64, vertical: 36);

  @override
  Widget build(BuildContext context) {
    final outer = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: outer.copyWith(
                size: size,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
