import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Colours of the "Bobine TV" design (always dark: a TV in a living room).
abstract final class TvColors {
  static const bg = Color(0xFF0D0C0B);
  static const accent = Color(0xFFFF5A36);
  static const accentInk = Color(0xFF1A0A05);
  static const cream = Color(0xFFF3EEE8);
  static const text = Color(0xFFFFFFFF);
  static const soft = Color(0xFFD9D4CE);
  static const muted = Color(0xFFB5AFA8);
  static const faint = Color(0xFF9A948D);
  static const dim = Color(0xFF7D766F);
  static const surface = Color(0xFF1A1816);
  static const surfaceLive = Color(0xFF2A2522);
  static const surfaceSoon = Color(0xFF1C1A18);
  static const surfacePast = Color(0xFF141311);
  static const border = Color(0xFF3A3530);
  static const line = Color(0xFF2E2A26);
  static const ok = Color(0xFF8FD1C2);
}

/// Big Shoulders, upper case titles of the design.
TextStyle tvTitle(
  double size, {
  FontWeight weight = FontWeight.w800,
  double height = 0.9,
  Color color = TvColors.text,
}) => TextStyle(fontFamily: AppFonts.poster, fontSize: size, fontWeight: weight, height: height, color: color);

/// Geist, the text of the design.
TextStyle tvText(
  double size, {
  FontWeight weight = FontWeight.w500,
  double height = 1.2,
  Color color = TvColors.text,
}) => TextStyle(fontFamily: AppFonts.body, fontSize: size, fontWeight: weight, height: height, color: color);

/// Geist Mono: times, numbers, keys.
TextStyle tvMono(double size, {FontWeight weight = FontWeight.w500, double height = 1, Color color = TvColors.soft}) =>
    TextStyle(fontFamily: AppFonts.mono, fontSize: size, fontWeight: weight, height: height, color: color);

/// Small vermilion upper case line above a title ("FILM · NOUVEAUTÉ").
TextStyle tvKicker([Color color = TvColors.accent]) =>
    tvText(24, weight: FontWeight.w600, height: 1, color: color).copyWith(letterSpacing: 24 * 0.16);

/// Background of an item without picture: a soft glow of a colour derived
/// from [key] (same idea as the design's placeholders).
Gradient tvTint(String key) {
  var h = 7;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) % 360;
  }
  return RadialGradient(
    center: const Alignment(0.48, -0.4),
    radius: 1.1,
    colors: [
      HSLColor.fromAHSL(1, h.toDouble(), 0.48, 0.22).toColor(),
      HSLColor.fromAHSL(1, h.toDouble(), 0.30, 0.10).toColor(),
      TvColors.bg,
    ],
    stops: const [0, 0.45, 0.85],
  );
}

/// Size of a big title so that a long one still fits (design's rule).
double tvTitleSize(String title, double max) {
  final n = title.length;
  return (n <= 14
          ? max
          : n <= 22
          ? max * 0.84
          : n <= 32
          ? max * 0.7
          : max * 0.6)
      .roundToDouble();
}

/// Ring and lift of a selected picture (channel, poster, episode).
List<BoxShadow> tvRing(bool on) => on
    ? const [
        BoxShadow(color: Colors.white, spreadRadius: 4),
        BoxShadow(color: Color(0xB3000000), offset: Offset(0, 26), blurRadius: 60),
      ]
    : const [];

/// Key of the remote drawn as in the design (a rounded outlined box).
class TvKey extends StatelessWidget {
  const TvKey(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    constraints: const BoxConstraints(minWidth: 56),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xBFFFFFFF), width: 2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: tvMono(24, weight: FontWeight.w600, color: TvColors.text),
    ),
  );
}

/// A key of the remote and what it does ("OK  Regarder").
class TvKeyHint extends StatelessWidget {
  const TvKeyHint(this.keyLabel, this.label, {super.key, this.color = TvColors.soft});
  final String keyLabel;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TvKey(keyLabel),
      const SizedBox(width: 12),
      Text(label, style: tvText(26, color: color, height: 1)),
    ],
  );
}
