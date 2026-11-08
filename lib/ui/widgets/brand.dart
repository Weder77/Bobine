import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The Bobine logo: a reel of thread whose vermilion thread becomes the
/// handwritten word "bobine" (168 × 60 at scale 1).
class BobineLogo extends StatelessWidget {
  const BobineLogo({super.key, this.height = 60});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * 168 / 60,
    height: height,
    child: CustomPaint(painter: _LogoPainter()),
  );
}

/// The reel alone, as in the hero kicker or the source card (12 × 16).
class BobineReel extends StatelessWidget {
  const BobineReel({super.key, this.height = 16});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * 12 / 16,
    height: height,
    child: CustomPaint(painter: _ReelPainter(stripes: height >= 28)),
  );
}

void _paintReel(Canvas canvas, {required bool stripes}) {
  final cream = Paint()..color = AppColors.cream;
  final core = Paint()..color = AppColors.accent;
  canvas.drawRRect(RRect.fromLTRBR(1, 9, 25, 14, const Radius.circular(1.6)), cream);
  canvas.drawRRect(RRect.fromLTRBR(1, 43, 25, 48, const Radius.circular(1.6)), cream);
  canvas.drawRect(const Rect.fromLTWH(4.5, 14, 17, 29), core);
  if (!stripes) return;
  final stripe = Paint()
    ..color = AppColors.reelShadow.withValues(alpha: 0.75)
    ..strokeWidth = 0.9
    ..style = PaintingStyle.stroke;
  for (var y = 17.2; y < 38; y += 3.4) {
    canvas.drawLine(Offset(4.5, y), Offset(21.5, y + 1.2), stripe);
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.height / 60);
    _paintReel(canvas, stripes: true);
    // The thread leaving the reel…
    final thread = Path()
      ..moveTo(21.5, 39.5)
      ..cubicTo(25.5, 40.1, 27.7, 42.1, 30.1, 42.9)
      ..cubicTo(33.3, 43.9, 35.9, 42.5, 38.5, 40.3);
    canvas.drawPath(
      thread,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round,
    );
    // …becomes the word, filled and lightly stroked so it reads as one line.
    for (final style in [
      const TextStyle(fontFamily: AppFonts.script, fontSize: 50, color: AppColors.accent),
      TextStyle(
        fontFamily: AppFonts.script,
        fontSize: 50,
        foreground: Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      ),
    ]) {
      final tp = TextPainter(
        text: TextSpan(text: 'bobine', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(35, 42 - baseline));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}

class _ReelPainter extends CustomPainter {
  _ReelPainter({required this.stripes});
  final bool stripes;

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 1 9 24 39, scaled to fit and centred.
    final scale = (size.width / 24) < (size.height / 39) ? size.width / 24 : size.height / 39;
    canvas.save();
    canvas.translate((size.width - 24 * scale) / 2, (size.height - 39 * scale) / 2);
    canvas.scale(scale);
    canvas.translate(-1, -9);
    _paintReel(canvas, stripes: stripes);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ReelPainter oldDelegate) => oldDelegate.stripes != stripes;
}
