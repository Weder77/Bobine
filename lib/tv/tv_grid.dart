import 'package:flutter/material.dart';

import 'tv_browse.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_rows.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

/// Id of a poster of a grid.
String tvGridId(TvItem it) => 'g:${it.key}';

/// Every poster of a list, seven a line (lazy: a category can hold
/// thousands). Up from the first line goes to [upFromTop] when given.
class TvPosterGrid extends StatelessWidget {
  const TvPosterGrid({
    super.key,
    required this.items,
    this.controller,
    this.upFromTop,
    this.padding = const EdgeInsets.fromLTRB(96, 16, 96, 80),
  });

  static const columns = 7;

  final List<TvItem> items;
  final ScrollController? controller;
  final String? Function()? upFromTop;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => GridView.builder(
    controller: controller,
    physics: const NeverScrollableScrollPhysics(),
    clipBehavior: Clip.none,
    padding: padding,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 36,
      crossAxisSpacing: 28,
      childAspectRatio: 2 / 3,
    ),
    itemCount: items.length,
    itemBuilder: (context, i) {
      final it = items[i];
      return TvFocusable(
        id: tvGridId(it),
        revealAxes: const {Axis.vertical},
        revealPadding: const EdgeInsets.only(top: 40, bottom: 60),
        onOk: () => tvOpen(context, it),
        onMove: i < columns && upFromTop != null ? (d) => d == TvDir.up ? upFromTop!() : null : null,
        builder: (context, on) => LayoutBuilder(
          builder: (context, box) => TvPosterCard(item: it, on: on, width: box.maxWidth, height: box.maxHeight),
        ),
      );
    },
  );
}

/// Above a grid: what the poster with the remote is (posters have no
/// title of their own), and how many there are.
class TvGridInfo extends StatelessWidget {
  const TvGridInfo({super.key, required this.item, required this.count, required this.noun});
  final TvItem? item;
  final int count;

  /// "film" or "série" (an s is added for more than one).
  final String noun;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: it == null
              ? const SizedBox.shrink()
              : Text.rich(
                  TextSpan(
                    text: it.title,
                    style: tvText(34, weight: FontWeight.w600, height: 1),
                    children: [
                      if (it.meta.isNotEmpty)
                        TextSpan(
                          text: '   ${it.meta}',
                          style: tvText(26, color: TvColors.muted, height: 1),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        const SizedBox(width: 24),
        Text('$count $noun${count > 1 ? 's' : ''}', style: tvMono(26)),
      ],
    );
  }
}

/// "Voir tout" of a row: all its items in a grid, Retour back to the row.
class TvGridScreen extends StatefulWidget {
  const TvGridScreen({super.key, required this.title, required this.items});
  final String title;
  final List<TvItem> items;

  static Future<void> open(BuildContext context, String title, List<TvItem> items) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => TvGridScreen(title: title, items: items),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );

  @override
  State<TvGridScreen> createState() => _TvGridScreenState();
}

class _TvGridScreenState extends State<TvGridScreen> {
  late final TvFocusController _c;
  final _grid = ScrollController();

  @override
  void initState() {
    super.initState();
    _c = TvFocusController(initial: widget.items.isEmpty ? null : tvGridId(widget.items.first))..addListener(_changed);
  }

  @override
  void dispose() {
    _c.dispose();
    _grid.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final id = _c.id;
    final focused = items.where((it) => tvGridId(it) == id).firstOrNull;
    final series = items.isNotEmpty && items.first.kind == TvItemKind.series;
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: TvStage(
        child: Material(
          color: TvColors.bg,
          child: TvFocusScope(
            controller: _c,
            onBack: () => Navigator.of(context).maybePop(),
            child: Stack(
              children: [
                Positioned(left: 96, right: 96, top: 72, child: Text(widget.title.toUpperCase(), style: tvTitle(84))),
                Positioned(
                  left: 96,
                  right: 96,
                  top: 190,
                  child: TvGridInfo(item: focused, count: items.length, noun: series ? 'série' : 'film'),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 250,
                  bottom: 0,
                  child: TvPosterGrid(items: items, controller: _grid),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
