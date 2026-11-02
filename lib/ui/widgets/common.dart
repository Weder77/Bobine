import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'net_image.dart';

/// Rebuilds with the hover state of the mouse.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder, this.cursor = SystemMouseCursors.click});
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: widget.builder(context, _hover),
  );
}

/// Thin progress bar (accent on a translucent track).
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.height = 4, this.color = AppColors.accent, this.track});
  final double value;
  final double height;
  final Color color;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: track ?? Colors.white.withValues(alpha: 0.14)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

/// Focus / hover ring used by cards: a white outline and a deep shadow.
BoxDecoration focusRing({required bool on, double radius = 12, Color? halo}) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: on ? AppColors.text : Colors.transparent, width: 2),
  boxShadow: on
      ? [BoxShadow(color: halo ?? const Color(0x99000000), blurRadius: 28, offset: const Offset(0, 12))]
      : null,
);

/// Saturation matrix for the glass effect.
List<double> _saturation(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// "Liquid glass" surface: blurs and saturates what is behind it, with a
/// light rim on the top edge and a soft drop shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    this.height,
    this.strong = false,
    this.shadow = true,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? height;

  /// Brighter glass (selected tab inside a glass bar).
  final bool strong;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? const [BoxShadow(color: Color(0x59000000), blurRadius: 32, offset: Offset(0, 12))] : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ColorFilter.matrix(_saturation(1.8)),
            inner: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          ),
          child: CustomPaint(
            foregroundPainter: _GlassRim(radius: radius, strong: strong),
            child: Container(
              height: height,
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: strong
                      ? const [Color(0x61FFFFFF), Color(0x29FFFFFF)]
                      : const [Color(0x38FFFFFF), Color(0x12FFFFFF)],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassRim extends CustomPainter {
  _GlassRim({required this.radius, required this.strong});
  final double radius;
  final bool strong;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius.clamp(0, size.height / 2)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: strong
            ? const [Color(0xB3FFFFFF), Color(0x33FFFFFF), Color(0x1AFFFFFF)]
            : const [Color(0x99FFFFFF), Color(0x26FFFFFF), Color(0x1FFFFFFF)],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(_GlassRim old) => old.radius != radius || old.strong != strong;
}

/// Round outlined icon action ("Ma liste", "Recommencer").
class RoundAction extends StatelessWidget {
  const RoundAction({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 24,
    style: IconButton.styleFrom(
      fixedSize: const Size(54, 54),
      backgroundColor: const Color(0x66111114),
      side: const BorderSide(color: Color(0x8CFFFFFF), width: 2),
      shape: const CircleBorder(),
    ),
    icon: Icon(icon, color: color ?? AppColors.text),
  );
}

/// Poster (2:3) card for movies and series.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.subtitle,
    this.rating,
    this.progress,
    this.favorite = false,
    this.width = 168,
  });

  final String title;
  final String? image;
  final String? subtitle;
  final double? rating;
  final double? progress;
  final bool favorite;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: HoverBuilder(
        builder: (context, hover) {
          return Semantics(
            button: true,
            label: title,
            child: GestureDetector(
              onTap: onTap,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: focusRing(on: hover, radius: 12),
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NetImage(image, decodeWidth: width, placeholder: _TitlePlaceholder(title)),
                              if (rating != null && rating! > 0)
                                Positioned(top: 8, left: 8, child: RatingBadge(rating!)),
                              if (favorite)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: AppColors.bg.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.favorite_rounded, color: AppColors.cueSeries, size: 15),
                                  ),
                                ),
                              if (progress != null && progress! > 0)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: ProgressLine(progress!, track: const Color(0x40FFFFFF)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TitlePlaceholder extends StatelessWidget {
  const _TitlePlaceholder(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surface3,
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(title, maxLines: 4, overflow: TextOverflow.ellipsis, style: posterStyle(34)),
      ),
    ),
  );
}

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: AppColors.bg.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(7)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1).replaceAll('.', ','),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Wide 16:9 card: the title is written on the image in poster capitals,
/// progress runs along the bottom edge, details go underneath.
class LandscapeCard extends StatelessWidget {
  const LandscapeCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.progress,
    this.width = 300,
    this.onRemove,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final String? image;
  final double? progress;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: HoverBuilder(
        builder: (context, hover) {
          return Semantics(
            button: true,
            label: title,
            child: GestureDetector(
              onTap: onTap,
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: focusRing(on: hover, radius: 12),
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NetImage(
                                image,
                                decodeWidth: width,
                                alignment: const Alignment(0, -0.4),
                                placeholder: const ColoredBox(color: AppColors.surface3),
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0x00000000), Color(0xCC0A0A0C)],
                                    begin: Alignment(0, -0.1),
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 14,
                                right: 14,
                                bottom: 16,
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: posterStyle(
                                    30,
                                    shadows: const [Shadow(color: Color(0x80000000), blurRadius: 12)],
                                  ),
                                ),
                              ),
                              Center(
                                child: AnimatedOpacity(
                                  opacity: hover ? 1 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    decoration: const BoxDecoration(color: AppColors.action, shape: BoxShape.circle),
                                    child: const Icon(Icons.play_arrow_rounded, color: AppColors.onAction, size: 32),
                                  ),
                                ),
                              ),
                              if (onRemove != null && hover)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    iconSize: 16,
                                    tooltip: 'Retirer',
                                    onPressed: onRemove,
                                    style: IconButton.styleFrom(backgroundColor: const Color(0xB30A0A0C)),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                              if (progress != null)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: ProgressLine(progress!, track: const Color(0x40FFFFFF)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (subtitle != null || trailing != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subtitle ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textSoft,
                              ),
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            Text(trailing!, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Square channel logo with initials fallback.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.name, required this.url, this.size = 44});
  final String name;
  final String? url;
  final double size;

  static String initials(String name) => name
      .replaceAll(RegExp(r'^[A-Z]{2,3}\s*[:|]\s*'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w.characters.first.toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Text(
        initials(name),
        style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.w800, color: AppColors.textSoft),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(size * 0.24)),
      child: NetImage(url, fit: BoxFit.contain, decodeWidth: size, placeholder: placeholder),
    );
  }
}

/// Section header: heavy Inter title and an optional link.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(title, style: displayStyle(22, weight: FontWeight.w700)),
      ),
      if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  );
}

/// Section title + horizontally scrolling list with arrow buttons (mouse friendly).
class SectionRow extends StatefulWidget {
  const SectionRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.itemWidth = 168,
    this.trailing,
    this.gap = 18,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double itemWidth;
  final Widget? trailing;
  final double gap;

  @override
  State<SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<SectionRow> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int dir) {
    final viewport = _controller.position.viewportDimension;
    _controller.animateTo(
      (_controller.offset + dir * viewport * 0.85).clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 0, 48, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: displayStyle(22, weight: FontWeight.w700)),
              ),
              ?widget.trailing,
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: HoverBuilder(
            cursor: MouseCursor.defer,
            builder: (context, hover) => Stack(
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 6),
                  clipBehavior: Clip.none,
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, _) => SizedBox(width: widget.gap),

                  itemBuilder: widget.itemBuilder,
                ),
                if (hover) ...[
                  Positioned(left: 8, top: 0, bottom: 40, child: _Arrow(Icons.chevron_left_rounded, () => _page(-1))),
                  Positioned(right: 8, top: 0, bottom: 40, child: _Arrow(Icons.chevron_right_rounded, () => _page(1))),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: const Color(0xD90A0A0C),
      shape: const CircleBorder(side: BorderSide(color: Color(0x40FFFFFF))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, size: 26)),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 34, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: displayStyle(22)),
          if (message != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}

/// Entry of a category rail.
class CategoryEntry {
  const CategoryEntry({required this.id, required this.label, this.count, this.icon});
  final String id;
  final String label;
  final int? count;
  final IconData? icon;
}

/// Copy of [entries] with the "fav" entry showing [count] (the counters are
/// otherwise only computed when the screen loads).
List<CategoryEntry> withFavoriteCount(List<CategoryEntry> entries, int count) => [
  for (final e in entries) e.id == 'fav' ? CategoryEntry(id: e.id, label: e.label, count: count, icon: e.icon) : e,
];

/// Left category rail used by Live / Films / Séries.
class CategoryPane extends StatefulWidget {
  const CategoryPane({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelect,
    this.width = 264,
  });
  final List<CategoryEntry> entries;
  final String selected;
  final ValueChanged<String> onSelect;
  final double width;

  @override
  State<CategoryPane> createState() => _CategoryPaneState();
}

class _CategoryPaneState extends State<CategoryPane> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final f = _filter.toLowerCase();
    final list = f.isEmpty
        ? widget.entries
        : widget.entries.where((e) => e.icon != null || e.label.toLowerCase().contains(f)).toList();
    // Built-in entries (with an icon) come first, then a separator.
    final firstCategory = list.indexWhere((e) => e.icon == null);
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Text('CATÉGORIES', style: labelStyle()),
            ),
            TextField(
              onChanged: (v) => setState(() => _filter = v),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Filtrer',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
                contentPadding: EdgeInsets.symmetric(vertical: 11),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.only(right: 6, bottom: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final sel = e.id == widget.selected;
                    final tile = SizedBox(
                      height: 44,
                      child: Material(
                        color: sel ? AppColors.selected : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => widget.onSelect(e.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                if (e.icon != null) ...[
                                  Icon(e.icon, size: 18, color: sel ? AppColors.text : AppColors.muted),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    e.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                                      color: sel ? AppColors.text : AppColors.textSoft,
                                    ),
                                  ),
                                ),
                                if (e.count != null)
                                  Text(
                                    '${e.count}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: sel ? AppColors.text : AppColors.faint,
                                      fontFeatures: tabularFigures,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    if (i == firstCategory && i > 0) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12), child: Divider()),
                          tile,
                        ],
                      );
                    }
                    return tile;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.surface3, this.textColor = AppColors.text, this.icon});
  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: textColor), const SizedBox(width: 5)],
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor),
        ),
      ],
    ),
  );
}

/// Outlined quality tag ("4K", "5.1").
class QualityTag extends StatelessWidget {
  const QualityTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: const Color(0x73FFFFFF)),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.1)),
  );
}

/// Red "DIRECT" badge.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.label = 'DIRECT'});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: AppColors.liveBadge, borderRadius: BorderRadius.circular(5)),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: Colors.white),
    ),
  );
}
