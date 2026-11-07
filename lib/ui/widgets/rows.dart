import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'cards.dart';
import 'common.dart';

/// Title line of a row: Geist 20 (or Big Shoulders 34 for a Top 10), a
/// grey subtitle and "Tout voir →" on the right.
class RowTitle extends StatelessWidget {
  const RowTitle({super.key, required this.title, this.sub, this.big = false, this.onMore});
  final String title;
  final String? sub;
  final bool big;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 48),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  big ? title.toUpperCase() : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: big
                      ? posterStyle(34, height: 1).copyWith(letterSpacing: 34 * 0.04)
                      : const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1),
                ),
              ),
              if (sub != null && sub!.isNotEmpty) ...[
                const SizedBox(width: 14),
                Padding(
                  padding: EdgeInsets.only(bottom: big ? 3 : 1),
                  child: Text(sub!, style: const TextStyle(fontSize: 14, color: AppColors.faint, height: 1)),
                ),
              ],
            ],
          ),
        ),
        if (onMore != null) ...[const SizedBox(width: 16), MoreLink(label: 'Tout voir →', onTap: onMore!)],
      ],
    ),
  );
}

/// Grey link that turns white on hover ("Tout voir →", "Ouvrir le guide →").
class MoreLink extends StatelessWidget {
  const MoreLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    builder: (context, hover) => GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1, color: hover ? AppColors.text : AppColors.textSoft),
      ),
    ),
  );
}

/// Horizontal rail of same-width items without scrollbar; arrows appear on
/// hover. The [raised] item is painted above its neighbours, so a card
/// growing on hover is never covered by the next one.
class Rail extends StatefulWidget {
  const Rail({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemWidth,
    required this.height,
    this.gap = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 48),
    this.raised,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemWidth;
  final double height;
  final double gap;
  final EdgeInsets padding;
  final int? raised;

  @override
  State<Rail> createState() => _RailState();
}

class _RailState extends State<Rail> {
  final _controller = ScrollController();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int dir) {
    final pos = _controller.position;
    _controller.animateTo(
      (_controller.offset + dir * pos.viewportDimension * 0.85).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.itemCount;
    final step = widget.itemWidth + widget.gap;
    final order = [for (var i = 0; i < n; i++) if (i != widget.raised) i, if (widget.raised != null && widget.raised! < n) widget.raised!];
    final canBack = _controller.hasClients && _controller.offset > 4;
    final canForward = !_controller.hasClients || _controller.offset < _controller.position.maxScrollExtent - 4;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        height: widget.height + widget.padding.vertical,
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: widget.padding,
                child: SizedBox(
                  width: n == 0 ? 0 : n * step - widget.gap,
                  height: widget.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final i in order)
                        Positioned(
                          key: ValueKey(i),
                          left: i * step,
                          top: 0,
                          width: widget.itemWidth,
                          height: widget.height,
                          child: widget.itemBuilder(context, i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_hover && canBack)
              Positioned(
                left: 6,
                top: widget.padding.top,
                height: widget.height,
                child: _RailArrow(Icons.chevron_left_rounded, () => _page(-1)),
              ),
            if (_hover && canForward && _controller.hasClients && _controller.position.maxScrollExtent > 0)
              Positioned(
                right: 6,
                top: widget.padding.top,
                height: widget.height,
                child: _RailArrow(Icons.chevron_right_rounded, () => _page(1)),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailArrow extends StatelessWidget {
  const _RailArrow(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: const Color(0xCC0D0C0B),
      shape: const CircleBorder(side: BorderSide(color: Color(0x40FFFFFF))),
      child: InkWell(
        canRequestFocus: false,
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, size: 26)),
      ),
    ),
  );
}

// ------------------------------------------------------------ poster rail

/// Data of a poster in a rail.
class PosterItem {
  const PosterItem({
    required this.key,
    required this.title,
    required this.poster,
    required this.onPlay,
    this.year,
    this.rating,
    this.genre,
    this.badge,
    this.favorite = false,
    this.onFavorite,
    this.onInfo,
    this.onContextMenu,
  });
  final String key;
  final String title;
  final String? poster;
  final int? year;
  final double? rating;
  final String? genre;
  final String? badge;
  final bool favorite;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;

  /// "Plus d'infos": the detail page.
  final VoidCallback? onInfo;
  final ValueChanged<Offset>? onContextMenu;
}

/// Row of 192 × 288 posters without titles. On hover a poster grows (×1.12),
/// rises above the others and shows play / "+", its title, rating, year
/// and genre. A click plays it.
class PosterRail extends StatefulWidget {
  const PosterRail({super.key, required this.items, this.showTitles = false});
  final List<PosterItem> items;
  final bool showTitles;

  @override
  State<PosterRail> createState() => _PosterRailState();
}

class _PosterRailState extends State<PosterRail> {
  int? _raised;

  @override
  Widget build(BuildContext context) => Rail(
    itemCount: widget.items.length,
    itemWidth: 192,
    height: widget.showTitles ? 288 + 10 + 17 : 288,
    padding: const EdgeInsets.fromLTRB(48, 22, 48, 26),
    raised: _raised,
    itemBuilder: (context, i) => _PosterCard(
      item: widget.items[i],
      first: i == 0,
      showTitle: widget.showTitles,
      onHighlight: (on) => setState(() => _raised = on ? i : (_raised == i ? null : _raised)),
    ),
  );
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item, required this.first, required this.showTitle, required this.onHighlight});
  final PosterItem item;
  final bool first;
  final bool showTitle;
  final ValueChanged<bool> onHighlight;

  @override
  Widget build(BuildContext context) {
    final m = item;
    return HoverBuilder(
      onActivate: m.onPlay,
      onContextMenu: m.onContextMenu,
      onHighlight: onHighlight,
      builder: (context, hover) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: m.onPlay,
            onSecondaryTapUp: m.onContextMenu == null ? null : (d) => m.onContextMenu!(d.globalPosition),
            onLongPressStart: m.onContextMenu == null ? null : (d) => m.onContextMenu!(d.globalPosition),
            child: AnimatedScale(
              scale: hover ? 1.12 : 1,
              alignment: first ? Alignment.centerLeft : Alignment.center,
              duration: const Duration(milliseconds: 250),
              curve: Curves.ease,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 192,
                height: 288,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: hover
                      ? const [BoxShadow(color: Color(0xB3000000), blurRadius: 50, offset: Offset(0, 24))]
                      : const [],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(url: m.poster, label: m.title, decodeWidth: 220),
                    if (m.badge != null)
                      Positioned(
                        left: 0,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                          child: Text(
                            m.badge!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              height: 1,
                              color: AppColors.onAccent,
                            ),
                          ),
                        ),
                      ),
                    if (hover) _PosterHover(item: m),
                  ],
                ),
              ),
            ),
          ),
          if (showTitle) ...[
            const SizedBox(height: 10),
            Text(
              m.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2, color: AppColors.textSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _PosterHover extends StatelessWidget {
  const _PosterHover({required this.item});
  final PosterItem item;

  @override
  Widget build(BuildContext context) {
    final m = item;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 44, 14, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xF70D0C0B), Color(0xF70D0C0B), Color(0x000D0C0B)],
            stops: [0, 0.3, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAction(icon: Icons.play_arrow_rounded, filled: true, onTap: m.onPlay, tooltip: 'Lecture'),
                if (m.onFavorite != null) ...[
                  const SizedBox(width: 8),
                  CircleAction(
                    icon: m.favorite ? Icons.check_rounded : Icons.add_rounded,
                    onTap: m.onFavorite!,
                    tooltip: m.favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
                  ),
                ],
                if (m.onInfo != null) ...[
                  const Spacer(),
                  CircleAction(icon: Icons.info_outline_rounded, onTap: m.onInfo!, tooltip: "Plus d'infos"),
                ],
              ],
            ),
            const SizedBox(height: 9),
            Text(
              m.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
            ),
            const SizedBox(height: 9),
            DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1, color: AppColors.textSoft),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (m.rating != null && m.rating! > 0)
                    Text(
                      '★ ${m.rating!.toStringAsFixed(1).replaceAll('.', ',')}',
                      style: const TextStyle(color: AppColors.accent),
                    ),
                  if (m.year != null) Text('${m.year}'),
                  if (m.genre != null && m.genre!.isNotEmpty) Text(m.genre!, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 34 px round button: white with a dark icon, or outlined.
class CircleAction extends StatelessWidget {
  const CircleAction({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.filled = false,
    this.size = 34,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? AppColors.action : null,
          border: filled ? null : Border.all(color: const Color(0x8CFFFFFF), width: 1.5),
        ),
        child: Icon(icon, size: size * 0.5, color: filled ? AppColors.onAction : AppColors.text),
      ),
    ),
  );
}

// ---------------------------------------------------------------- top 10

/// Data of a Top 10 entry.
class TopItem {
  const TopItem({required this.title, required this.poster, required this.onPlay, this.onContextMenu});
  final String title;
  final String? poster;
  final VoidCallback onPlay;
  final ValueChanged<Offset>? onContextMenu;
}

/// "Top 10": huge outlined rank numbers behind 168 × 252 posters.
class TopTenRail extends StatelessWidget {
  const TopTenRail({super.key, required this.items});
  final List<TopItem> items;

  @override
  Widget build(BuildContext context) => Rail(
    itemCount: items.length,
    itemWidth: 286,
    height: 252,
    gap: 6,
    padding: const EdgeInsets.fromLTRB(48, 18, 48, 8),
    itemBuilder: (context, i) => _TopCard(rank: i + 1, item: items[i]),
  );
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.rank, required this.item});
  final int rank;
  final TopItem item;

  @override
  Widget build(BuildContext context) {
    final digits = TextStyle(
      fontFamily: AppFonts.poster,
      fontWeight: FontWeight.w900,
      fontSize: 268,
      height: 1,
      letterSpacing: 268 * -0.06,
    );
    return HoverBuilder(
      onActivate: item.onPlay,
      onContextMenu: item.onContextMenu,
      builder: (context, hover) => GestureDetector(
        onTap: item.onPlay,
        onSecondaryTapUp: item.onContextMenu == null ? null : (d) => item.onContextMenu!(d.globalPosition),
        onLongPressStart: item.onContextMenu == null ? null : (d) => item.onContextMenu!(d.globalPosition),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              // CSS left: -6px; Flutter puts half the (negative) letter
              // spacing before the first digit.
              left: -6 + 268 * 0.03,
              bottom: -34,
              child: Stack(
                children: [
                  Text('$rank', style: digits.copyWith(color: AppColors.bg)),
                  Text(
                    '$rank',
                    style: digits.copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..color = AppColors.outlineDigit,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              width: 168,
              height: 252,
              child: AnimatedScale(
                scale: hover ? 1.04 : 1,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(-12, 0))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Artwork(url: item.poster, label: item.title, decodeWidth: 200),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ resume row

/// "Reprendre": four 16:9 cards across, a 4 px progress line, the title
/// with "reste 29 min" and the episode underneath.
class ResumeRail extends StatelessWidget {
  const ResumeRail({super.key, required this.entries, required this.onPlay, this.onContextMenu, this.onRemove});
  final List<ProgressEntry> entries;
  final ValueChanged<ProgressEntry> onPlay;
  final void Function(ProgressEntry, Offset)? onContextMenu;
  final ValueChanged<ProgressEntry>? onRemove;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 14.0;
      final w = ((box.maxWidth - 96 - 3 * gap) / 4).clamp(250.0, 420.0);
      final h = w * 9 / 16 + 10 + 18 + 6 + 13;
      return Rail(
        itemCount: entries.length,
        itemWidth: w,
        height: h,
        gap: gap,
        padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
        itemBuilder: (context, i) {
          final p = entries[i];
          return _ResumeCard(
            entry: p,
            onTap: () => onPlay(p),
            onContextMenu: onContextMenu == null ? null : (at) => onContextMenu!(p, at),
            onRemove: onRemove == null ? null : () => onRemove!(p),
          );
        },
      );
    },
  );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.entry, required this.onTap, this.onContextMenu, this.onRemove});
  final ProgressEntry entry;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = entry;
    final left = formatSpan(p.duration - p.position);
    final sub = p.subtitle != null && p.subtitle!.isNotEmpty
        ? p.subtitle!
        : (p.kind == ContentKind.episode ? 'Épisode' : 'Film');
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
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: hover ? const Color(0xD9FFFFFF) : Colors.transparent, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedScale(
                      scale: hover ? 1.04 : 1,
                      duration: const Duration(milliseconds: 300),
                      child: Artwork(url: p.image, label: p.title, decodeWidth: 420),
                    ),
                    if (hover)
                      const Center(child: CircleAction(icon: Icons.play_arrow_rounded, filled: true, onTap: _noop, tooltip: 'Reprendre', size: 48)),
                    if (hover && onRemove != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Tooltip(
                          message: 'Retirer de « Reprendre »',
                          child: GestureDetector(
                            onTap: onRemove,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(color: Color(0xB30D0C0B), shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, size: 16),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Color(0x2EFFFFFF)),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: p.fraction,
                              child: const ColoredBox(color: AppColors.accent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
                const SizedBox(width: 12),
                Text('reste $left', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3, color: AppColors.faint)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1, color: AppColors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}

// ------------------------------------------------------------- live now

/// Data of a "En direct maintenant" card.
class LiveNowItem {
  const LiveNowItem({
    required this.channel,
    required this.program,
    required this.onTap,
    this.onContextMenu,
  });
  final Channel channel;
  final Program? program;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;
}

/// "En direct maintenant": one row of frosted cards over the bottom of the
/// billboard (as many as fit, at least 220 px each).
class LiveNowStrip extends StatelessWidget {
  const LiveNowStrip({super.key, required this.items, required this.onGuide, this.title = 'En direct maintenant'});
  final List<LiveNowItem> items;
  final VoidCallback onGuide;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 48),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const PulseDot(),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1)),
            const Spacer(),
            MoreLink(label: 'Ouvrir le guide →', onTap: onGuide),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 14.0;
            final cols = ((box.maxWidth + gap) / (220 + gap)).floor().clamp(1, 12);
            final shown = items.take(cols).toList();
            final w = (box.maxWidth - gap * (shown.length - 1)) / shown.length;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  SizedBox(width: w, child: _LiveNowCard(item: shown[i])),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _LiveNowCard extends StatelessWidget {
  const _LiveNowCard({required this.item});
  final LiveNowItem item;

  @override
  Widget build(BuildContext context) {
    final c = item.channel;
    final p = item.program;
    final now = DateTime.now();
    final pct = p == null
        ? 0.0
        : (now.difference(p.start).inSeconds / p.stop.difference(p.start).inSeconds.clamp(1, 1 << 30)).clamp(0.0, 1.0);
    return HoverBuilder(
      onActivate: item.onTap,
      onContextMenu: item.onContextMenu,
      focusRingRadius: 12,
      builder: (context, hover) => GestureDetector(
        onTap: item.onTap,
        onSecondaryTapUp: item.onContextMenu == null ? null : (d) => item.onContextMenu!(d.globalPosition),
        onLongPressStart: item.onContextMenu == null ? null : (d) => item.onContextMenu!(d.globalPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hover ? const Color(0xD9342F2A) : const Color(0xA8201D1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChannelLogo(name: c.name, url: c.logo, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p == null ? 'Direct' : '${formatClock(p.start)} – ${formatClock(p.stop)}',
                              style: monoStyle(12, height: 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 39,
                    child: Text(
                      p?.title ?? 'Programme non renseigné',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: p == null ? AppColors.faint : AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0x24FFFFFF)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: pct,
                            child: const ColoredBox(color: AppColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 8 px accent dot that breathes (1.6 s), next to "En direct maintenant".
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.size = 8, this.color = AppColors.accent});
  final double size;
  final Color color;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 1.0, end: 0.35).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
}
