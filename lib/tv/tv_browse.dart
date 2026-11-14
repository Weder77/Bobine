import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services.dart';
import '../ui/launch.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_rows.dart';
import 'tv_series.dart';
import 'tv_shell.dart';
import 'tv_theme.dart';

/// What OK does on an item of a row.
Future<void> tvOpen(BuildContext context, TvItem it) async {
  switch (it.ref) {
    case final Channel c:
      await Launch.channel(context, c, it.channels ?? [c]);
    case final Movie m:
      await Launch.movie(context, m);
    case final Series sr:
      await TvSeriesScreen.open(context, sr);
    case final ProgressEntry p:
      await Launch.resume(context, p);
  }
}

double _cardHeight(TvRowStyle s) => s == TvRowStyle.live || s == TvRowStyle.wide ? 225 : 300;

/// Height of a row: its title, then the pictures with room for the ring.
double _rowHeight(TvRowStyle s) => 30 + 22 + _cardHeight(s) + 30;
const _rowGap = 22.0;

/// Accueil, Films or Séries: the big picture and the words of what is
/// selected at the top, the rows below (the selected row moves up).
class TvBrowsePage extends StatefulWidget {
  const TvBrowsePage({super.key, required this.tab, required this.setEntry});
  final TvTab tab;
  final void Function(String? Function()) setEntry;

  @override
  State<TvBrowsePage> createState() => _TvBrowsePageState();
}

class _TvBrowsePageState extends State<TvBrowsePage> {
  final _scroll = ScrollController();
  TvFocusController? _c;
  AppServices? _s;
  List<TvRow> _rows = const [];
  TvItem? _featured;
  Timer? _tick;
  int? _row;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (s != _s) {
      _s?.library.removeListener(_reload);
      _s = s..library.addListener(_reload);
      _reload();
    }
    final c = TvFocusScope.maybeOf(context);
    if (c != _c) {
      _c?.removeListener(_onFocus);
      _c = c?..addListener(_onFocus);
    }
  }

  @override
  void initState() {
    super.initState();
    // The programmes on air move on.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _reload());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _s?.library.removeListener(_reload);
    _c?.removeListener(_onFocus);
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    final s = _s;
    final source = s?.activeSource;
    final rows = source == null || s == null
        ? const <TvRow>[]
        : tvRows(repo: s.repo, epg: s.epg, sourceId: source.id, tab: widget.tab, name: s.channelName);
    final preferred = switch (widget.tab) {
      TvTab.films => 'Top 10 des films',
      TvTab.series => 'Nouveautés',
      _ => 'Ajoutés récemment',
    };
    final pool = [
      ...rows.where((r) => r.title == preferred),
      ...rows.where((r) => r.style == TvRowStyle.poster || r.style == TvRowStyle.top),
    ];
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _featured = pool.isEmpty ? null : pool.first.items.first;
    });
  }

  (int, int)? _pos(String? id) {
    if (id == null || !id.startsWith('r')) return null;
    final parts = id.substring(1).split('-');
    if (parts.length != 2) return null;
    final r = int.tryParse(parts[0]), i = int.tryParse(parts[1]);
    return r == null || i == null ? null : (r, i);
  }

  void _onFocus() {
    final pos = _pos(_c?.id);
    final row = pos?.$1;
    if (row != _row) {
      _row = row;
      var offset = 0.0;
      for (var k = 0; k < (row ?? 0) && k < _rows.length; k++) {
        offset += _rowHeight(_rows[k].style) + _rowGap;
      }
      if (_scroll.hasClients) {
        _scroll.animateTo(
          offset.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    }
    setState(() {});
  }

  TvItem? get _selected {
    final pos = _pos(_c?.id);
    if (pos == null || pos.$1 >= _rows.length) return null;
    final items = _rows[pos.$1].items;
    return pos.$2 < items.length ? items[pos.$2] : null;
  }

  Widget _heroButton(String id, IconData icon, String label, VoidCallback onOk, {bool strong = false}) => TvFocusable(
    id: id,
    onOk: onOk,
    builder: (context, on) => AnimatedScale(
      scale: on ? 1.05 : 1,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 76,
        padding: EdgeInsets.only(left: strong ? 32 : 28, right: strong ? 42 : 36),
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0x29FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: on ? TvColors.bg : Colors.white),
            const SizedBox(width: 14),
            Text(
              label,
              style: tvText(
                30,
                weight: strong ? FontWeight.w700 : FontWeight.w600,
                height: 1,
                color: on ? TvColors.bg : Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _info(TvItem info, bool card) {
    final s = AppScope.of(context);
    final featured = _featured;
    final inList = featured != null && _isFavorite(s, featured);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(info.kicker.toUpperCase(), style: tvKicker()),
        const SizedBox(height: 20),
        Text(
          info.title.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tvTitle(tvTitleSize(info.title, 116), height: 0.88).copyWith(
            shadows: const [Shadow(color: Color(0x80000000), offset: Offset(0, 6), blurRadius: 40)],
          ),
        ),
        if (info.meta.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(info.meta, style: tvText(26, color: TvColors.soft)),
        ],
        if (info.synopsis != null && info.synopsis!.isNotEmpty) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: 860,
            child: Text(
              info.synopsis!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tvText(26, weight: FontWeight.w400, height: 1.45, color: TvColors.soft),
            ),
          ),
        ],
        const SizedBox(height: 30),
        SizedBox(
          height: 76,
          child: Stack(
            children: [
              AnimatedOpacity(
                opacity: card ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: card,
                  child: featured == null
                      ? const SizedBox.shrink()
                      : Row(
                          children: [
                            _heroButton(
                              'hero-play',
                              Icons.play_arrow_rounded,
                              featured.kind == TvItemKind.series ? 'Voir la série' : 'Lecture',
                              () => tvOpen(context, featured),
                              strong: true,
                            ),
                            const SizedBox(width: 18),
                            _heroButton(
                              'hero-list',
                              inList ? Icons.check_rounded : Icons.add_rounded,
                              inList ? 'Dans ma liste' : 'Ma liste',
                              () => setState(() => _toggleFavorite(s, featured)),
                            ),
                          ],
                        ),
                ),
              ),
              if (card && info.progress != null)
                Row(
                  children: [
                    SizedBox(width: 380, child: TvBar(value: info.progress!, height: 8, radius: 4)),
                    const SizedBox(width: 22),
                    Text(info.progressLabel ?? '', style: tvMono(26)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static bool _isFavorite(AppServices s, TvItem it) => switch (it.ref) {
    final Movie m => s.repo.isFavorite(m.sourceId, ContentKind.movie, m.extId),
    final Series sr => s.repo.isFavorite(sr.sourceId, ContentKind.series, sr.extId),
    _ => false,
  };

  static void _toggleFavorite(AppServices s, TvItem it) {
    switch (it.ref) {
      case final Movie m:
        s.toggleFavorite(ContentKind.movie, m.extId, m.sourceId);
      case final Series sr:
        s.toggleFavorite(ContentKind.series, sr.extId, sr.sourceId);
    }
  }

  Widget _card(TvRow row, TvItem it, String id) => TvFocusable(
    id: id,
    onOk: () => tvOpen(context, it),
    revealAxes: const {Axis.horizontal},
    builder: (context, on) => switch (row.style) {
      TvRowStyle.live => TvLiveCard(item: it, on: on),
      TvRowStyle.wide => TvWideCard(item: it, on: on),
      TvRowStyle.top => TvTopCard(item: it, on: on),
      TvRowStyle.poster => TvPosterCard(item: it, on: on),
    },
  );

  Widget _rowView(int ri, TvRow row) => SizedBox(
    height: _rowHeight(row.style),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 96),
          child: Text(row.title, style: tvText(30, weight: FontWeight.w600, height: 1)),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(96, 22, 96, 30),
            itemCount: row.items.length,
            separatorBuilder: (_, _) => SizedBox(width: row.style == TvRowStyle.top ? 16 : 24),
            itemBuilder: (context, i) => _card(row, row.items[i], 'r$ri-$i'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final featured = _featured;
    final rows = _rows;
    widget.setEntry(() => featured != null ? 'hero-play' : (rows.isEmpty ? null : 'r0-0'));
    if (featured == null && rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('RIEN À AFFICHER', style: tvTitle(64)),
            const SizedBox(height: 18),
            Text(
              'Ta source ne propose rien ici pour l’instant. Tu peux l’actualiser dans Réglages.',
              style: tvText(28, color: TvColors.muted),
            ),
          ],
        ),
      );
    }
    final selected = _selected;
    final info = selected ?? featured ?? rows.first.items.first;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: 1920,
          height: 900,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: SizedBox.expand(
              key: ValueKey(info.key),
              child: TvPicture(url: info.backdrop ?? info.image, tintKey: info.key, decodeWidth: 1280),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          top: 0,
          width: 1920,
          height: 900,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D0C0B), Color(0xEB0D0C0B), Color(0x730D0C0B), Color(0x000D0C0B)],
                  stops: [0, 0.30, 0.54, 0.74],
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          top: 0,
          width: 1920,
          height: 900,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF0D0C0B), Color(0xE60D0C0B), Color(0x000D0C0B)],
                  stops: [0, 0.30, 0.58],
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 96, bottom: 450, width: 980, child: _info(info, selected != null)),
        Positioned(
          left: 0,
          right: 0,
          top: 660,
          bottom: 0,
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const NeverScrollableScrollPhysics(),
            // The rows gone up stay under the title, as in the design.
            clipBehavior: Clip.hardEdge,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (ri, row) in rows.indexed) ...[
                    if (ri > 0) const SizedBox(height: _rowGap),
                    _rowView(ri, row),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
