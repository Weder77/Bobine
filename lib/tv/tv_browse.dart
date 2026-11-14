import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services.dart';
import '../ui/launch.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_grid.dart';
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

  /// Card ids by row: the row and the item (positions change when "Reprendre"
  /// comes or goes; the card with the remote must stay the same one).
  List<List<String>> _ids = const [];
  Map<String, (int, int)> _where = const {};

  /// Last card with the remote in each row (by title): Up and Down land there.
  final Map<String, String> _last = {};

  /// The big picture follows the remote once it stays on a card (a row run
  /// through does not load every picture).
  TvItem? _picture;
  Timer? _pictureTimer;

  /// Films and Séries: À la une (the rows), Tout or a category (a grid).
  List<TvPill> _pills = const [];
  String _pill = 'une';
  List<TvItem> _gridItems = const [];
  Map<String, TvItem> _gridById = const {};
  final _grid = ScrollController();

  /// A pill shows its grid once the remote stays on it (a category can
  /// hold thousands of films).
  Timer? _pillTimer;

  /// "Voir tout" cards: their row.
  Map<String, int> _more = const {};

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
    // The programmes on air move on (Accueil's live row; Films and Séries
    // do not change with the time, and a whole category is not read again).
    if (widget.tab == TvTab.home) _tick = Timer.periodic(const Duration(minutes: 1), (_) => _reload());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pictureTimer?.cancel();
    _pillTimer?.cancel();
    _s?.library.removeListener(_reload);
    _c?.removeListener(_onFocus);
    _scroll.dispose();
    _grid.dispose();
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
    final was = _pos(_c?.id);
    final wasRow = was == null || was.$1 >= _rows.length ? null : _rows[was.$1].title;
    final pills = source == null || s == null ? const <TvPill>[] : tvCatalogPills(s.repo, source.id, widget.tab);
    final pill = pills.any((p) => p.id == _pill) ? _pill : 'une';
    final grid = pill == 'une' || source == null || s == null
        ? const <TvItem>[]
        : tvCatalogItems(s.repo, source.id, widget.tab, pill);
    final ids = <List<String>>[];
    final where = <String, (int, int)>{};
    final more = <String, int>{};
    for (final (ri, row) in rows.indexed) {
      if (row.all != null) more['more:${row.title}'] = ri;
      final line = <String>[];
      for (final (i, it) in row.items.indexed) {
        var id = 'c:${row.title}:${it.key}';
        if (where.containsKey(id)) id = '$id#$i';
        where[id] = (ri, i);
        line.add(id);
      }
      ids.add(line);
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _ids = ids;
      _where = where;
      _more = more;
      _pills = pills;
      _pill = pill;
      _setGrid(grid);
      _featured = pool.isEmpty ? null : pool.first.items.first;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepFocus(wasRow));
  }

  /// After a reload: the card with the remote went away (a film finished
  /// leaves "Reprendre"): its row's first card, or the buttons; its row
  /// moved: the rows follow.
  void _keepFocus(String? title) {
    final c = _c, id = c?.id;
    if (!mounted || c == null || id == null) return;
    if (id.startsWith('g:') && !_gridById.containsKey(id)) {
      // Gone from the grid (hidden, locked meanwhile): the first poster.
      final first = _gridItems.firstOrNull;
      c.focus(first == null ? 'bp-$_pill' : tvGridId(first));
      return;
    }
    if (!id.startsWith('c:') && !id.startsWith('more:')) return;
    if (id.startsWith('more:')) {
      if (!_more.containsKey(id)) c.focus(_featured != null ? 'hero-play' : _firstCard);
      return;
    }
    if (!_where.containsKey(id)) {
      final ri = _rows.indexWhere((r) => r.title == title);
      final to = ri >= 0 && _ids[ri].isNotEmpty ? _ids[ri].first : (_featured != null ? 'hero-play' : _firstCard);
      _last.remove(title);
      if (to != null) c.focus(to);
      return;
    }
    _row = null;
    _onFocus();
  }

  String? get _firstCard => _ids.isEmpty || _ids.first.isEmpty ? null : _ids.first.first;

  (int, int)? _pos(String? id) {
    if (id == null) return null;
    final more = _more[id];
    return more != null ? (more, -1) : _where[id];
  }

  void _setGrid(List<TvItem> items) {
    _gridItems = items;
    _gridById = {for (final it in items) tvGridId(it): it};
  }

  /// Shows what [pill] holds (now: Down or OK on it).
  void _showPill(String pill) {
    _pillTimer?.cancel();
    final s = _s, source = s?.activeSource;
    if (!mounted || pill == _pill || s == null || source == null) return;
    setState(() {
      _pill = pill;
      _setGrid(pill == 'une' ? const [] : tvCatalogItems(s.repo, source.id, widget.tab, pill));
    });
    if (_grid.hasClients) _grid.jumpTo(0);
  }

  /// The page of [pill], then its first item.
  void _enterPill(String pill) {
    _showPill(pill);
    String? target() {
      final first = _gridItems.firstOrNull;
      return _pill == 'une' ? (_featured != null ? 'hero-play' : _firstCard) : (first == null ? null : tvGridId(first));
    }

    // Already on screen (the pill was shown while the remote stayed on it).
    final now = target();
    if (now != null && (_c?.isRegistered(now) ?? false)) return _c?.focus(now, dir: TvDir.down);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final to = target();
      if (to != null) _c?.focus(to, dir: TvDir.down);
    });
    // Now, not at the next frame some other change brings: the next key
    // would come first.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  String? get _pillId => _pills.isEmpty ? null : 'bp-$_pill';

  /// Where Up / Down go from a card of row [ri] (null: the nearest).
  String? _moveFrom(int ri, TvDir d) => switch (d) {
    TvDir.up => ri == 0 ? (_featured != null ? 'hero-play' : null) : _rowTarget(ri - 1),
    TvDir.down => ri + 1 < _rows.length ? _rowTarget(ri + 1) : null,
    _ => null,
  };

  String? _rowTarget(int ri) {
    final last = _last[_rows[ri].title];
    if (last != null && (_c?.isRegistered(last) ?? false)) return last;
    return _ids[ri].isEmpty ? null : _ids[ri].first;
  }

  void _onFocus() {
    final id = _c?.id;
    _pillTimer?.cancel();
    if (id != null && id.startsWith('bp-')) {
      _pillTimer = Timer(const Duration(milliseconds: 300), () => _showPill(id.substring(3)));
    }
    final pos = _pos(id);
    final row = pos?.$1;
    if (pos != null) _last[_rows[pos.$1].title] = id!;
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
    _pictureTimer?.cancel();
    _pictureTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _picture = _selected);
    });
    setState(() {});
  }

  TvItem? get _selected {
    final pos = _pos(_c?.id);
    if (pos == null || pos.$1 >= _rows.length) return null;
    final items = _rows[pos.$1].items;
    return pos.$2 >= 0 && pos.$2 < items.length ? items[pos.$2] : null;
  }

  Widget _heroButton(String id, IconData icon, String label, VoidCallback onOk, {bool strong = false}) => TvFocusable(
    id: id,
    onOk: onOk,
    onMove: (d) => switch (d) {
      TvDir.down => _rows.isNotEmpty ? _rowTarget(0) : null,
      TvDir.up => _pillId,
      _ => null,
    },
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
          // Under the pills of Films and Séries, one line leaves them room.
          maxLines: _pills.isEmpty ? 2 : 1,
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

  Widget _card(int ri, TvRow row, TvItem it, String id) => TvFocusable(
    id: id,
    onOk: () => tvOpen(context, it),
    onMove: (d) => _moveFrom(ri, d),
    revealAxes: const {Axis.horizontal},
    builder: (context, on) => switch (row.style) {
      TvRowStyle.live => TvLiveCard(item: it, on: on),
      TvRowStyle.wide => TvWideCard(item: it, on: on),
      TvRowStyle.top => TvTopCard(item: it, on: on),
      TvRowStyle.poster => TvPosterCard(item: it, on: on),
    },
  );

  Widget _moreCard(int ri, TvRow row) => TvFocusable(
    id: 'more:${row.title}',
    onOk: () => TvGridScreen.open(context, row.title, row.all!()),
    onMove: (d) => _moveFrom(ri, d),
    revealAxes: const {Axis.horizontal},
    builder: (context, on) => TvMoreCard(on: on),
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
            itemCount: row.items.length + (row.all != null ? 1 : 0),
            separatorBuilder: (_, _) => SizedBox(width: row.style == TvRowStyle.top ? 16 : 24),
            itemBuilder: (context, i) =>
                i < row.items.length ? _card(ri, row, row.items[i], _ids[ri][i]) : _moreCard(ri, row),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final featured = _featured;
    final rows = _rows;
    final grid = _gridItems;
    widget.setEntry(() {
      if (_pill == 'une') return featured != null ? 'hero-play' : _firstCard;
      return grid.isEmpty ? _pillId : tvGridId(grid.first);
    });
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
    if (_pill != 'une') return _gridView();
    final selected = _selected;
    final info = selected ?? featured ?? rows.first.items.first;
    // Off a card (the buttons, the top bar), the featured one at once.
    final picture = selected == null ? info : (_picture ?? info);
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
              key: ValueKey(picture.key),
              child: TvPicture(url: picture.backdrop ?? picture.image, tintKey: picture.key, decodeWidth: 1280),
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
        Positioned(left: 96, bottom: 450, width: 980, child: _info(info, _pos(_c?.id) != null)),
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
        if (_pills.isNotEmpty) _pillRow(),
      ],
    );
  }

  Widget _pillRow() => Positioned(
    left: 0,
    right: 0,
    top: 152,
    height: 66,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 96),
      itemCount: _pills.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (context, i) {
        final p = _pills[i];
        return TvPillButton(
          id: 'bp-${p.id}',
          label: p.label,
          current: p.id == _pill,
          large: true,
          onOk: () => _enterPill(p.id),
          onMove: (d) {
            if (d != TvDir.down) return null;
            _enterPill(p.id);
            // Where entering put the remote (the first poster, or the pill
            // itself until the grid is built).
            return _c?.id;
          },
        );
      },
    ),
  );

  /// Tout or a category: every poster, under the pills.
  Widget _gridView() {
    final focused = _gridById[_c?.id];
    final items = _gridItems;
    return Stack(
      children: [
        _pillRow(),
        Positioned(
          left: 96,
          right: 96,
          top: 254,
          child: TvGridInfo(
            item: focused ?? items.firstOrNull,
            count: items.length,
            noun: widget.tab == TvTab.series ? 'série' : 'film',
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 306,
          bottom: 0,
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(96, 40, 96, 0),
                  child: Text('Rien dans cette catégorie.', style: tvText(28, color: TvColors.muted)),
                )
              : TvPosterGrid(items: items, controller: _grid, upFromTop: () => _pillId),
        ),
      ],
    );
  }
}
