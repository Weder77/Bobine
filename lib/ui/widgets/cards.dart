import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';
import 'net_image.dart';

/// Stable hue (0-360) for the tinted backdrop of a title without image.
double hueOf(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return (h % 360).toDouble();
}

/// Image or, when missing, the tinted gradient of the design with the title.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    required this.label,
    this.decodeWidth,
    this.alignment = Alignment.center,
  });
  final String? url;
  final String label;
  final double? decodeWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.placeholderGradient(hueOf(label))),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.placeholder),
          ),
        ),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return NetImage(url, decodeWidth: decodeWidth, alignment: alignment, placeholder: placeholder);
  }
}

/// Poster of a grid (search, catalogue): 2:3 image that grows a little on
/// hover, title and "2026 · ★ 8,0" below.
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.year,
    this.rating,
    this.progress,
    this.onContextMenu,
    this.hoverScale = 1.04,
  });
  final String title;
  final String? image;
  final int? year;
  final double? rating;
  final double? progress;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;
  final double hoverScale;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (year != null) '$year',
      if (rating != null && rating! > 0) '★ ${rating!.toStringAsFixed(1).replaceAll('.', ',')}',
    ].join(' · ');
    return HoverBuilder(
      onActivate: onTap,
      onContextMenu: onContextMenu,
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
        onLongPressStart: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: AnimatedScale(
                scale: hover ? hoverScale : 1,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: hover ? Border.all(color: AppColors.text.withValues(alpha: 0.85), width: 1.5) : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Artwork(url: image, label: title, decodeWidth: 240),
                      if (progress != null && progress! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ProgressLine(progress!, height: 3, track: AppColors.ink.withAlpha(0x59)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
            ),
            if (meta.isNotEmpty) ...[const SizedBox(height: 6), Text(meta, style: monoStyle(12))],
          ],
        ),
      ),
    );
  }
}

/// Responsive grid of fixed-min-width cells (CSS auto-fill/minmax).
class AutoGrid extends StatelessWidget {
  const AutoGrid({super.key, required this.minWidth, required this.children, this.spacing = 14, this.runSpacing = 26});
  final double minWidth;
  final double spacing;
  final double runSpacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = ((box.maxWidth + spacing) / (minWidth + spacing)).floor().clamp(1, 99);
      final w = (box.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [for (final c in children) SizedBox(width: w, child: c)],
      );
    },
  );
}
