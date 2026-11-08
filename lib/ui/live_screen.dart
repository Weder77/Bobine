import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'launch.dart';
import 'live_catalog.dart';
import 'quick_actions.dart';
import 'shell.dart';
import 'widgets/billboard.dart' show QualityBadge;
import 'widgets/cards.dart';
import 'widgets/chips.dart';
import 'widgets/common.dart';
import 'widgets/rows.dart' show PulseDot;

/// "Direct": every channel as a 16:9 tile showing what it plays now; the
/// first one, twice as big, leads the "Toutes" group. A click plays it.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.catalog});
  final LiveCatalog catalog;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late final AppServices _s;
  final _filter = TextEditingController();
  List<ChannelTile> _tiles = const [];
  Timer? _clock;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    widget.catalog.addListener(_refresh);
    _filter.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 180), _refresh);
    });
    _refresh();
    // "Now playing" and the clock of the kicker.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_refresh);
    _clock?.cancel();
    _debounce?.cancel();
    _filter.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _tiles = widget.catalog.filtered(_filter.text));
  }

  void _play(ChannelTile t) => Launch.channel(context, t.channel, [for (final x in _tiles) x.channel]);

  void _menu(ChannelTile t, Offset at) =>
      showChannelActions(context, t.channel, [for (final x in _tiles) x.channel], at);

  @override
  Widget build(BuildContext context) {
    final cat = widget.catalog;
    if (cat.source == null) return const SizedBox.shrink();
    final feature = cat.cat == 'all' && _filter.text.trim().isEmpty;
    final now = DateTime.now();
    final count = _tiles.length;
    return LayoutBuilder(
      builder: (context, box) {
        const side = 48.0, gap = 16.0;
        final width = box.maxWidth - side * 2;
        final cols = ((width + gap) / (320 + gap)).floor().clamp(1, 12);
        final cellW = (width - gap * (cols - 1)) / cols;
        final cellH = cellW * 9 / 16;
        // The big tile takes 2 × 2 cells; the cells to its right are filled
        // first (CSS grid "dense").
        final big = feature && cols >= 2 && _tiles.length > 1;
        final besideCount = big ? (2 * (cols - 2)).clamp(0, _tiles.length - 1) : 0;
        final restStart = big ? 1 + besideCount : 0;
        return CustomScrollView(
          scrollBehavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, 40, side, 0),
              sliver: SliverToBoxAdapter(child: _header(now, count)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: ChipStrip(
                padding: const EdgeInsets.symmetric(horizontal: side),
                children: [
                  for (final e in cat.entries)
                    GroupChip(
                      label: e.label,
                      count: e.count,
                      locked: e.locked,
                      selected: e.id == cat.cat,
                      onTap: () => cat.select(e.id),
                    ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            if (_tiles.isEmpty)
              SliverToBoxAdapter(child: _empty(cat))
            else ...[
              if (big)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(side, 0, side, gap),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      height: cellH * 2 + gap,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: cellW * 2 + gap,
                            height: cellH * 2 + gap,
                            child: _tile(_tiles.first, 1, big: true),
                          ),
                          for (var c = 0; c < cols - 2; c++) ...[
                            const SizedBox(width: gap),
                            SizedBox(
                              width: cellW,
                              child: Column(
                                children: [
                                  for (var r = 0; r < 2; r++) ...[
                                    if (r > 0) const SizedBox(height: gap),
                                    SizedBox(
                                      height: cellH,
                                      child: 1 + r * (cols - 2) + c < restStart
                                          ? _tile(_tiles[1 + r * (cols - 2) + c], 2 + r * (cols - 2) + c)
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(side, 0, side, 96),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: 16 / 9,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: _tiles.length - restStart,
                    (context, i) => _tile(_tiles[restStart + i], restStart + i + 1),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _header(DateTime now, int count) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PulseDot(),
            const SizedBox(width: 10),
            Text(
              '${formatShortDate(now)} · ${formatClock(now)}'.toUpperCase(),
              style: labelStyle(color: AppColors.accent, size: 13).copyWith(letterSpacing: 13 * 0.18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text('DIRECT', style: posterStyle(76, height: 0.9)),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${formatCount(count)} chaîne${count > 1 ? 's' : ''}',
                style: monoStyle(16, color: AppColors.textSoft, height: 1),
              ),
            ),
          ],
        ),
      ],
    );
    final tools = Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 300,
          height: 44,
          child: TextField(
            controller: _filter,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Filtrer chaînes et programmes',
              prefixIcon: Icon(Icons.search_rounded, size: 19, color: AppColors.faint),
              prefixIconConstraints: const BoxConstraints(minWidth: 42),
              suffixIcon: _filter.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      onPressed: _filter.clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => ShellNavigation.of(context)?.goTo(ShellTab.guide),
          style:
              OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600),
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (s) => BorderSide(
                    color: s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
                        ? AppColors.text
                        : AppColors.borderStrong,
                  ),
                ),
              ),
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('Guide TV'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 760
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 18), tools])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: title),
                tools,
              ],
            ),
    );
  }

  Widget _empty(LiveCatalog cat) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 48),
    child: Column(
      children: [
        Text(
          cat.cat == 'fav' && _filter.text.isEmpty ? 'AUCUNE CHAÎNE FAVORITE' : 'AUCUNE CHAÎNE',
          textAlign: TextAlign.center,
          style: posterStyle(36, height: 1).copyWith(letterSpacing: 36 * 0.04),
        ),
        const SizedBox(height: 12),
        Text(
          cat.cat == 'fav' && _filter.text.isEmpty
              ? "Ajoute une chaîne aux favoris (clic droit) pour la retrouver ici."
              : 'Rien ne correspond à ce filtre dans ce groupe.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.faint),
        ),
      ],
    ),
  );

  Widget _tile(ChannelTile t, int number, {bool big = false}) => LiveTile(
    tile: t,
    number: t.channel.number ?? number,
    big: big,
    favorite: t.variants.any((c) => widget.catalog.favs.contains(c.extId)),
    now: _s.epg.now(t.channel),
    next: _s.epg.next(t.channel),
    onTap: () => _play(t),
    onContextMenu: (at) => _menu(t, at),
  );
}

/// 16:9 tile of a channel: badge, name and number at the top, quality and
/// favourite star on the right; the programme, its progress and (on hover)
/// what comes next at the bottom.
class LiveTile extends StatelessWidget {
  const LiveTile({
    super.key,
    required this.tile,
    required this.number,
    required this.now,
    required this.next,
    required this.onTap,
    this.onContextMenu,
    this.big = false,
    this.favorite = false,
  });
  final ChannelTile tile;
  final int number;
  final Program? now;
  final Program? next;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;
  final bool big;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final c = tile.channel;
    final p = now;
    final t = DateTime.now();
    final pct = p?.progressAt(t) ?? 0;
    final width = MediaQuery.sizeOf(context).width;
    return HoverBuilder(
      onActivate: onTap,
      onContextMenu: onContextMenu,
      builder: (context, hover) => Semantics(
        button: true,
        label: tile.name,
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapUp: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
          onLongPressStart: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(decoration: BoxDecoration(gradient: AppColors.placeholderGradient(hueOf(tile.name)))),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        AppColors.bg.withAlpha(0xF5),
                        AppColors.bg.withAlpha(0x8C),
                        AppColors.bg.withAlpha(0x1A),
                        AppColors.bg.withAlpha(0x80),
                      ],
                      stops: [0, 0.45, 0.72, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  top: 14,
                  child: Row(
                    children: [
                      ChannelLogo(name: tile.name, url: c.logo, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.15),
                            ),
                            const SizedBox(height: 4),
                            Text('$number', style: monoStyle(12, color: AppColors.textSoft, height: 1)),
                          ],
                        ),
                      ),
                      if (favorite) ...[
                        Icon(Icons.star_rounded, size: 17, color: AppColors.accent),
                        const SizedBox(width: 8),
                      ],
                      if (tile.quality != null) QualityBadge(tile.quality!),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (big) ...[
                        if (p?.category != null)
                          Text(
                            p!.category!.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle(color: AppColors.accent, size: 12),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          (p?.title ?? tile.name).toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: posterStyle((width * 0.044).clamp(40.0, 64.0), height: 0.9),
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        Text(
                          p?.title ?? 'Programme non renseigné',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: p == null ? AppColors.faint : AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (p != null)
                        Row(
                          children: [
                            Text(formatClock(p.start), style: monoStyle(12, color: AppColors.textSoft, height: 1)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: SizedBox(
                                  height: 3,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(color: AppColors.ink.withAlpha(0x33)),
                                      FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: pct,
                                        child: ColoredBox(color: AppColors.accent),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(formatClock(p.stop), style: monoStyle(12, color: AppColors.textSoft, height: 1)),
                          ],
                        ),
                      if (next != null)
                        AnimatedOpacity(
                          opacity: big || hover ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text.rich(
                              TextSpan(
                                text: 'Ensuite ${formatClock(next!.start)} · ',
                                children: [
                                  TextSpan(
                                    text: next!.title,
                                    style: TextStyle(color: AppColors.text),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Accent outline on hover / focus.
                IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: hover ? AppColors.accent : Colors.transparent, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
