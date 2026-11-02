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

class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.height = 3, this.color = AppColors.accent});
  final double value;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0x33FFFFFF)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ]),
        ),
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
    this.width = 160,
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
      child: HoverBuilder(builder: (context, hover) {
        return GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedScale(
                  scale: hover ? 1.04 : 1,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hover ? AppColors.accent : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: hover
                          ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.25), blurRadius: 18)]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(fit: StackFit.expand, children: [
                        NetImage(image, decodeWidth: width, placeholder: _TitlePlaceholder(title)),
                        if (rating != null && rating! > 0)
                          Positioned(top: 8, left: 8, child: RatingBadge(rating!)),
                        if (favorite)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(Icons.favorite, color: AppColors.accent2, size: 18),
                          ),
                        if (progress != null && progress! > 0)
                          Positioned(
                            left: 8, right: 8, bottom: 8,
                            child: ProgressLine(progress!, height: 4),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: hover ? AppColors.text : const Color(0xFFD9DEE7),
                  )),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
        );
      }),
    );
  }
}

class _TitlePlaceholder extends StatelessWidget {
  const _TitlePlaceholder(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.surface3, AppColors.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 13, color: AppColors.accent),
          const SizedBox(width: 2),
          Text(rating.toStringAsFixed(1),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Wide 16:9 card used for "Continuer à regarder".
class LandscapeCard extends StatelessWidget {
  const LandscapeCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.subtitle,
    this.progress,
    this.width = 300,
    this.onRemove,
  });

  final String title;
  final String? subtitle;
  final String? image;
  final double? progress;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: HoverBuilder(builder: (context, hover) {
        return GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: hover ? AppColors.accent : Colors.transparent, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(fit: StackFit.expand, children: [
                      NetImage(image, decodeWidth: width, alignment: Alignment.topCenter),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Color(0xCC000000)],
                            begin: Alignment.center,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Center(
                        child: AnimatedOpacity(
                          opacity: hover ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                                color: AppColors.accent, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 30),
                          ),
                        ),
                      ),
                      if (onRemove != null && hover)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: IconButton.filledTonal(
                            iconSize: 16,
                            tooltip: 'Retirer',
                            onPressed: onRemove,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      if (progress != null)
                        Positioned(
                          left: 10, right: 10, bottom: 10,
                          child: ProgressLine(progress!, height: 4),
                        ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (subtitle != null)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
        );
      }),
    );
  }
}

/// Square channel logo with initials fallback.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.name, required this.url, this.size = 40});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .replaceAll(RegExp(r'^[A-Z]{2,3}\s*[:|]\s*'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    final placeholder = Center(
      child: Text(initials,
          style: TextStyle(
              fontSize: size * 0.32, fontWeight: FontWeight.w800, color: AppColors.muted)),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: NetImage(url, fit: BoxFit.contain, decodeWidth: size, placeholder: placeholder),
    );
  }
}

/// Section title + horizontally scrolling list with arrow buttons (mouse friendly).
class SectionRow extends StatefulWidget {
  const SectionRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.height,
    this.itemWidth = 160,
    this.trailing,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double itemWidth;
  final Widget? trailing;

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
      (_controller.offset + dir * viewport * 0.85)
          .clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
        child: Row(children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
          const Spacer(),
          ?widget.trailing,
        ]),
      ),
      SizedBox(
        height: widget.height,
        child: HoverBuilder(
          cursor: MouseCursor.defer,
          builder: (context, hover) => Stack(children: [
            ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
              itemCount: widget.itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: widget.itemBuilder,
            ),
            if (hover) ...[
              Positioned(left: 4, top: 0, bottom: 40, child: _Arrow(Icons.chevron_left, () => _page(-1))),
              Positioned(right: 4, top: 0, bottom: 40, child: _Arrow(Icons.chevron_right, () => _page(1))),
            ],
          ]),
        ),
      ),
    ]);
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: Colors.black.withValues(alpha: 0.7),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 26)),
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: AppColors.faint),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(message!,
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

/// Entry of a category sidebar.
class CategoryEntry {
  const CategoryEntry({required this.id, required this.label, this.count, this.icon});
  final String id;
  final String label;
  final int? count;
  final IconData? icon;
}

/// Left category pane used by Live / Films / Séries.
class CategoryPane extends StatefulWidget {
  const CategoryPane({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelect,
    this.width = 250,
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
    return Container(
      width: widget.width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _filter = v),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Filtrer les catégories',
              prefixIcon: Icon(Icons.filter_list, size: 18),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemExtent: 40,
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                final sel = e.id == widget.selected;
                return Material(
                  color: sel ? AppColors.accent.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => widget.onSelect(e.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(children: [
                        if (e.icon != null) ...[
                          Icon(e.icon, size: 17, color: sel ? AppColors.accent : AppColors.muted),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(e.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                color: sel ? AppColors.accent : const Color(0xFFD0D5DE),
                              )),
                        ),
                        if (e.count != null)
                          Text('${e.count}',
                              style: const TextStyle(fontSize: 11, color: AppColors.faint)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: textColor), const SizedBox(width: 4)],
          Text(text,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textColor)),
        ]),
      );
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) => const Pill('EN DIRECT',
      color: AppColors.live, textColor: Colors.white, icon: Icons.circle);
}
