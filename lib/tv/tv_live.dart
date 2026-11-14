import 'dart:async';

import 'package:flutter/material.dart';

import '../services.dart';
import '../ui/launch.dart';
import '../ui/live_catalog.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// "sam. 7 nov. 22:32".
String tvDayTime(DateTime t) => '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} ${tvClock(t)}';

/// Direct: the groups of channels in pills, then every channel of the
/// chosen group in a mosaic of four columns.
class TvLivePage extends StatefulWidget {
  const TvLivePage({super.key, required this.setEntry});
  final void Function(String? Function()) setEntry;

  @override
  State<TvLivePage> createState() => _TvLivePageState();
}

class _TvLivePageState extends State<TvLivePage> {
  LiveCatalog? _cat;
  TvFocusController? _c;
  Timer? _tick;
  final _grid = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cat ??= LiveCatalog(AppScope.of(context))..addListener(_changed);
    final c = TvFocusScope.maybeOf(context);
    if (c != _c) {
      _c?.removeListener(_onFocus);
      _c = c?..addListener(_onFocus);
    }
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _changed());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _select?.cancel();
    _c?.removeListener(_onFocus);
    _cat?.dispose();
    _grid.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Arriving on a pill shows its group (as the tabs of the top bar), once
  /// the remote stays on it: each group loads its channels (and is kept as
  /// the last one), passing over pills does not.
  Timer? _select;

  void _onFocus() {
    final id = _c?.id;
    _select?.cancel();
    if (id == null || _cat == null || !id.startsWith('grp-')) return;
    _select = Timer(const Duration(milliseconds: 300), () => _show(id.substring(4)));
  }

  void _show(String entry) {
    _select?.cancel();
    final cat = _cat;
    if (!mounted || cat == null || entry == cat.cat) return;
    cat.select(entry);
    if (_grid.hasClients) _grid.jumpTo(0);
  }

  /// The group of a pill now, then its first channel.
  void _enter(String entry) {
    _show(entry);
    // Already on screen (the group was shown while the remote stayed on it).
    final shown = _cat?.tiles.firstOrNull;
    final id = shown == null ? null : 'ch-${shown.channel.extId}';
    if (id != null && (_c?.isRegistered(id) ?? false)) return _c?.focus(id, dir: TvDir.down);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final first = _cat?.tiles.firstOrNull;
      if (mounted && first != null) _c?.focus('ch-${first.channel.extId}', dir: TvDir.down);
    });
    // Now, not at the next frame some other change brings: the next key
    // would come first.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _pill(String id, String label, bool current) => TvPillButton(
    id: 'grp-$id',
    label: label,
    current: current,
    onOk: () => _enter(id),
    onMove: (d) {
      if (d != TvDir.down) return null;
      _enter(id);
      // Where entering put the remote (the first channel, or the pill itself
      // until the grid is built).
      return _c?.id;
    },
  );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cat = _cat!;
    final tiles = cat.tiles;
    final list = cat.playList;
    final now = DateTime.now();
    // Down from the tabs: the groups first (then Down again into the channels).
    widget.setEntry(() => 'grp-${cat.cat}');
    return Stack(
      children: [
        Positioned(
          left: 96,
          right: 96,
          top: 158,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('DIRECT', style: tvTitle(84)),
              const SizedBox(width: 28),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(color: TvColors.accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Text('${tiles.length} chaîne${tiles.length > 1 ? 's' : ''} · ${tvDayTime(now)}', style: tvMono(26)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 262,
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 96),
            itemCount: cat.entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final e = cat.entries[i];
              return _pill(e.id, e.label, e.id == cat.cat);
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 340,
          bottom: 0,
          child: tiles.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(96, 40, 96, 0),
                  child: Text(
                    cat.cat == 'fav'
                        ? 'Aucune chaîne favorite. Celles de ton compte Bobine apparaissent ici.'
                        : 'Aucune chaîne dans ce groupe.',
                    style: tvText(28, color: TvColors.muted),
                  ),
                )
              : GridView.builder(
                  controller: _grid,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(96, 22, 96, 60),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 28,
                    crossAxisSpacing: 28,
                    childAspectRatio: 411 / 231,
                  ),
                  itemCount: tiles.length,
                  itemBuilder: (context, i) {
                    final t = tiles[i];
                    final it = tvChannel(t.channel, s.epg, t.name, now, list);
                    return TvFocusable(
                      id: 'ch-${t.channel.extId}',
                      // Up from the first line: the pill of this group (the one
                      // above may be another, which would change the group).
                      onMove: i < 4 ? (d) => d == TvDir.up ? 'grp-${cat.cat}' : null : null,
                      revealAxes: const {Axis.vertical},
                      revealPadding: const EdgeInsets.only(top: 40, bottom: 48),
                      onOk: () => Launch.channel(context, t.channel, list),
                      builder: (context, on) => LayoutBuilder(
                        builder: (context, box) => TvLiveCard(
                          item: it,
                          on: on,
                          width: box.maxWidth,
                          height: box.maxHeight,
                          next: on ? s.epg.next(t.channel)?.title : null,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
