import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services.dart';
import 'catalog_controller.dart';
import 'launch.dart';
import 'shell.dart';
import 'titles.dart';
import 'widgets/billboard.dart';
import 'widgets/cards.dart';
import 'widgets/chips.dart';
import 'widgets/common.dart';
import 'widgets/rows.dart';

/// Height of the sub-bar under the header on Films / Séries.
const kSubBarHeight = 60.0;

/// Films or Séries: "Parcourir" (billboard and rows) or "Tout le
/// catalogue" (filterable grid), driven by [controller] and the sub-bar.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.controller});
  final CatalogController controller;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _RowData {
  _RowData(this.title, this.items, {this.sub, this.onMore, this.top = false, this.resume});
  final String title;
  final String? sub;
  final List<Object> items;
  final VoidCallback? onMore;
  final bool top;
  final List<ProgressEntry>? resume;
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final AppServices _s;
  CatalogController get _c => widget.controller;
  int _loadedVersion = -1;
  CatalogMode? _mode;

  // Rows mode.
  List<Object> _heroTitles = const [];
  List<ProgressEntry> _resume = const [];
  List<_RowData> _rows = const [];
  Set<String> _favorites = const {};
  final Set<String> _tmdbAsked = {};

  // Grid mode.
  List<Object> _items = const [];
  List<Object> _visible = const [];
  Map<String, double> _progress = const {};
  (String, CatalogSort)? _gridKey;
  String _gridQuery = '';
  final _filter = TextEditingController();
  Timer? _debounce;
  final _gridScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _c.addListener(_onController);
    _s.settings.addListener(_onSettings);
    _load();
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _s.settings.removeListener(_onSettings);
    _debounce?.cancel();
    _filter.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  void _onController() {
    if (!mounted) return;
    if (_mode != _c.mode && _gridScroll.hasClients) _gridScroll.jumpTo(0);
    if (_c.query != _filter.text) _filter.text = _c.query;
    setState(_load);
  }

  void _load() {
    final src = _c.source;
    if (src == null) return;
    final fresh = _loadedVersion != _c.version;
    _loadedVersion = _c.version;
    _mode = _c.mode;
    if (fresh) {
      _favorites = TitleCards.loadFavorites(_s, src.id);
      _loadRows(src);
      _gridKey = null;
    }
    if (_c.mode == CatalogMode.grid) _loadGrid(src);
  }

  // ------------------------------------------------------------------ rows

  void _loadRows(Source src) {
    final r = _s.repo;
    final series = _c.series;
    final kind = _c.kind;
    _resume = [
      for (final p in r.continueWatching(src.id))
        if (series ? p.kind == ContentKind.episode : p.kind == ContentKind.movie) p,
    ];
    final top = [
      for (final t in r.trending(src.id, limit: 40))
        if (series ? t is Series : t is Movie) t,
    ].take(10).toList();
    List<Object> list({int? categoryId, CatalogSort sort = CatalogSort.added}) => series
        ? r.series(src.id, categoryId: categoryId, sort: sort, limit: 30)
        : r.movies(src.id, categoryId: categoryId, sort: sort, limit: 30);
    final recent = list();
    final favorites = series ? r.favoriteSeries(src.id) : r.favoriteMovies(src.id);
    final best = list(sort: CatalogSort.rating);
    final cats = r.categories(src.id, kind).where((c) => c.count >= 6).take(6).toList();

    final hero = <Object>[];
    if (_resume.isNotEmpty) hero.add(_resume.first);
    for (final t in [...top, ...recent]) {
      if (hero.length >= 4) break;
      final poster = t is Movie ? t.poster : (t as Series).poster;
      if (poster != null && !hero.contains(t)) hero.add(t);
    }
    _heroTitles = hero;

    _rows = [
      if (_resume.isNotEmpty) _RowData(series ? 'Reprendre tes séries' : 'Reprendre', const [], resume: _resume),
      if (recent.isNotEmpty)
        _RowData(
          series ? 'Ajoutées récemment' : 'Ajoutés récemment',
          recent,
          onMore: () => _c.openGrid('all', CatalogSort.added),
        ),
      if (top.isNotEmpty)
        _RowData(
          series ? 'Top 10 séries' : "Top 10 films aujourd'hui",
          top,
          top: true,
          sub: series ? 'sur ta source' : null,
        ),
      if (favorites.isNotEmpty) _RowData('Mes favoris', favorites, onMore: () => _c.openGrid('fav')),
      for (final cat in cats) _RowData(cat.name, list(categoryId: cat.id), onMore: () => _c.openGrid('c:${cat.id}')),
      if (best.isNotEmpty &&
          (best.first is Movie ? (best.first as Movie).rating : (best.first as Series).rating) != null)
        _RowData('Les mieux notés', best, onMore: () => _c.openGrid('all', CatalogSort.rating)),
    ];
    TitleCards.prefetch(_s, [...hero, ...top], _tmdbAsked, () {
      if (mounted) setState(() {});
    });
  }

  List<HeroEntry> _heroEntries(TitleCards cards) {
    final first = _rows.where((r) => r.top).firstOrNull?.items.firstOrNull;
    final n1 = _c.series ? "N° 1 des séries aujourd'hui" : "N° 1 des films aujourd'hui";
    return [
      for (final t in _heroTitles)
        if (t is ProgressEntry)
          cards.resumeHero(t)
        else if (t is Movie)
          cards.movieHero(t, t == first ? n1 : 'Film · Nouveauté')
        else
          cards.seriesHero(t as Series, t == first ? n1 : 'Série · Nouveauté'),
    ];
  }

  Widget _buildRows() {
    final cards = TitleCards(context, _s, _favorites);
    final hero = _heroEntries(cards);
    final size = MediaQuery.sizeOf(context);
    final heroH = Billboard.heightFor(size, 600, 760, 0.80);
    final rows = <Widget>[
      for (final r in _rows)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RowTitle(title: r.title, sub: r.sub, big: r.top, onMore: r.onMore),
            if (r.resume != null)
              ResumeRail(
                entries: r.resume!,
                onPlay: (p) => Launch.resume(context, p),
                onRemove: (p) {
                  _s.repo.removeProgress(p.sourceId, p.kind, p.extId);
                  _s.library.userChanged();
                },
              )
            else if (r.top)
              TopTenRail(items: [for (final t in r.items) cards.top(t)])
            else
              PosterRail(items: [for (final o in r.items) cards.poster(o)]),
          ],
        ),
    ];
    if (rows.isEmpty && hero.isEmpty) {
      return _Empty(
        title: _c.series ? 'AUCUNE SÉRIE' : 'AUCUN FILM',
        text: "Cette source n'a rien proposé ici pour l'instant.",
        top: kTopBarHeight + kSubBarHeight,
      );
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          if (hero.isEmpty)
            const SizedBox(height: kTopBarHeight + kSubBarHeight + 24)
          else
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: heroH,
                  child: Billboard(
                    entries: hero,
                    minHeight: 600,
                    maxHeight: 760,
                    heightFactor: 0.80,
                    bottomPadding: 200,
                    controlsBottom: 214,
                    topPadding: kTopBarHeight + kSubBarHeight + 28,
                    autoplay: _s.settings.heroAutoplay,
                  ),
                ),
                SizedBox(height: heroH - 120),
              ],
            ),
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 30), rows[i]],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ grid

  void _loadGrid(Source src) {
    final key = (_c.cat, _c.sort);
    if (_gridKey != key) {
      _gridKey = key;
      final r = _s.repo;
      final catId = _c.cat.startsWith('c:') ? int.tryParse(_c.cat.substring(2)) : null;
      if (_c.series) {
        _items = _c.cat == 'fav' ? r.favoriteSeries(src.id) : r.series(src.id, categoryId: catId, sort: _c.sort);
        _progress = const {};
      } else {
        _items = _c.cat == 'fav' ? r.favoriteMovies(src.id) : r.movies(src.id, categoryId: catId, sort: _c.sort);
        _progress = {
          for (final p in r.continueWatching(src.id, limit: 500))
            if (p.kind == ContentKind.movie) p.extId: p.fraction,
        };
      }
      _gridQuery = '\u0000';
    }
    if (_gridQuery != _c.query) {
      _gridQuery = _c.query;
      final words = searchWords(_c.query);
      _visible = words.isEmpty
          ? _items
          : [
              for (final o in _items)
                if (matchesWords(o is Movie ? o.search : (o as Series).search, words)) o,
            ];
    }
  }

  Widget _buildGrid() {
    final cards = TitleCards(context, _s, _favorites);
    final unit = _c.series ? 'séries' : 'films';
    final e = _c.entry;
    final title = e == null || e.id == 'all' ? (_c.series ? 'Toutes les séries' : 'Tous les films') : e.label;
    final q = _c.query.trim();
    final count = q.isNotEmpty
        ? '${formatCount(_visible.length)} résultat${_visible.length > 1 ? 's' : ''}'
        : '${formatCount(_items.length)} $unit';
    return LayoutBuilder(
      builder: (context, box) {
        const side = 48.0, gap = 14.0;
        final width = box.maxWidth - side * 2;
        final cols = math.max(1, ((width + gap) / (172 + gap)).floor());
        final cellW = (width - gap * (cols - 1)) / cols;
        return CustomScrollView(
          controller: _gridScroll,
          scrollBehavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, kTopBarHeight + kSubBarHeight + 28, side, 0),
              sliver: SliverToBoxAdapter(child: _gridHeader(title, count)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 26)),
            SliverToBoxAdapter(
              child: ChipStrip(
                padding: const EdgeInsets.symmetric(horizontal: side),
                children: [
                  for (final e in _c.entries)
                    GroupChip(
                      label: e.label,
                      count: e.count,
                      locked: e.locked,
                      selected: e.id == _c.cat,
                      onTap: () => _c.openGrid(e.id),
                    ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 26)),
            if (_c.locked)
              SliverToBoxAdapter(child: _Locked(onPin: (pin) => _s.unlockParental(pin)))
            else if (_visible.isEmpty)
              SliverToBoxAdapter(
                child: _Empty(
                  title: q.isNotEmpty ? 'AUCUN RÉSULTAT' : "RIEN ICI POUR L'INSTANT",
                  text: q.isNotEmpty
                      ? 'Aucun titre ne correspond à « $q » dans cette catégorie.'
                      : 'Ajoute un titre à tes favoris depuis sa fiche ou par clic droit.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(side, 0, side, 96),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: 30,
                    mainAxisExtent: cellW * 1.5 + 10 + 18 + 5 + 12,
                  ),
                  delegate: SliverChildBuilderDelegate(childCount: _visible.length, (context, i) {
                    final o = _visible[i];
                    final item = cards.poster(o);
                    return GridPoster(item: item, progress: o is Movie ? _progress[o.extId] : null);
                  }),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _gridHeader(String title, String count) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_c.title} / catalogue'.toUpperCase(),
          style: monoStyle(13, weight: FontWeight.w500, height: 1).copyWith(letterSpacing: 13 * 0.06),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(title.toUpperCase(), style: posterStyle(76, height: 0.9).copyWith(letterSpacing: 76 * 0.01)),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(count, style: monoStyle(16, color: AppColors.textSoft, height: 1)),
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
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 180), () => _c.setQuery(v));
            },
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: _c.series ? 'Filtrer les séries' : 'Filtrer les films',
              prefixIcon: const Icon(Icons.search_rounded, size: 19, color: AppColors.faint),
              prefixIconConstraints: const BoxConstraints(minWidth: 42),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Segmented<CatalogSort>(
          value: _c.sort,
          onChanged: _c.setSort,
          options: const [
            (CatalogSort.added, 'Ajouts récents'),
            (CatalogSort.name, 'A–Z'),
            (CatalogSort.rating, 'Note'),
            (CatalogSort.year, 'Année'),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 900
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 18), tools])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: left),
                tools,
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_c.source == null) return const SizedBox.shrink();
    return _c.mode == CatalogMode.grid ? _buildGrid() : _buildRows();
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.text, this.top = 0});
  final String title;
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(48, top + 80, 48, 80),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: posterStyle(36, height: 1).copyWith(letterSpacing: 36 * 0.04),
        ),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.faint),
        ),
      ],
    ),
  );
}

/// Locked category: the parental code in four boxes.
class _Locked extends StatefulWidget {
  const _Locked({required this.onPin});
  final bool Function(String pin) onPin;

  @override
  State<_Locked> createState() => _LockedState();
}

class _LockedState extends State<_Locked> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  bool _wrong = false;

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() => _wrong = false);
    if (v.length < 4) return;
    if (!widget.onPin(v)) {
      setState(() => _wrong = true);
      _ctl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _ctl.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 48),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 40, color: AppColors.accent),
          const SizedBox(height: 18),
          Text('CATÉGORIE VERROUILLÉE', style: posterStyle(36, height: 1).copyWith(letterSpacing: 36 * 0.04)),
          const SizedBox(height: 18),
          Text(
            _wrong ? 'Code incorrect. Réessaie.' : "Saisis ton code parental à 4 chiffres pour l'afficher.",
            style: TextStyle(fontSize: 16, height: 1.5, color: _wrong ? AppColors.accent : AppColors.faint),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _focus.requestFocus,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The real field, invisible: the boxes show its digits.
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: _ctl,
                      focusNode: _focus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _changed,
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _focus,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Container(
                          width: 52,
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _focus.hasFocus && i == v.length ? AppColors.accent : AppColors.borderInput,
                              width: _focus.hasFocus && i == v.length ? 1.5 : 1,
                            ),
                          ),
                          child: i < v.length
                              ? Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control of the design (sorts, days): white pill on the chosen
/// option inside a dark rounded box.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged, this.pill = false});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// Fully rounded (Parcourir / Tout le catalogue) instead of 6 px corners.
  final bool pill;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: pill ? const Color(0x990D0C0B) : AppColors.surface,
      borderRadius: BorderRadius.circular(pill ? 999 : 6),
      border: Border.all(color: pill ? const Color(0x24FFFFFF) : AppColors.borderInput),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (v, label)) in options.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          HoverBuilder(
            onActivate: () => onChanged(v),
            focusRingRadius: pill ? 999 : 4,
            builder: (context, hover) => GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(horizontal: pill ? 16 : 12, vertical: pill ? 9 : 10),
                decoration: BoxDecoration(
                  color: v == value ? AppColors.action : (hover ? const Color(0x14FFFFFF) : Colors.transparent),
                  borderRadius: BorderRadius.circular(pill ? 999 : 4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: v == value ? AppColors.onAction : AppColors.textSoft,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------------ sub-bar

/// Second line of the header on Films / Séries: the page title, the
/// "Catégories" menu, "Effacer ✕" and Parcourir / Tout le catalogue.
class CatalogSubBar extends StatelessWidget {
  const CatalogSubBar({super.key, required this.controller});
  final CatalogController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final grid = c.mode == CatalogMode.grid;
      final hasCat = grid && c.cat != 'all';
      return Container(
        height: kSubBarHeight,
        padding: const EdgeInsets.fromLTRB(48, 0, 48, 6),
        child: Row(
          children: [
            Text(c.title.toUpperCase(), style: posterStyle(42, height: 1).copyWith(letterSpacing: 42 * 0.04)),
            const SizedBox(width: 18),
            _CategoriesButton(
              label: hasCat ? (c.entry?.label ?? 'Catégories') : 'Catégories',
              onTap: () => _showCategories(context, c),
            ),
            if (hasCat) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: c.clearCategory,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSoft,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                child: const Text('Effacer ✕'),
              ),
            ],
            const Spacer(),
            Segmented<CatalogMode>(
              pill: true,
              value: c.mode,
              onChanged: (m) => m == CatalogMode.rows ? c.toRows() : c.openGrid(grid ? c.cat : 'all'),
              options: const [(CatalogMode.rows, 'Parcourir'), (CatalogMode.grid, 'Tout le catalogue')],
            ),
          ],
        ),
      );
    },
  );
}

class _CategoriesButton extends StatelessWidget {
  const _CategoriesButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 6,
    builder: (context, hover) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        decoration: BoxDecoration(
          color: hover ? const Color(0x1AFFFFFF) : const Color(0x8C0D0C0B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xB3FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    ),
  );
}

/// The categories in three columns under the sub-bar.
Future<void> _showCategories(BuildContext context, CatalogController c) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (context, _, _) {
      final size = MediaQuery.sizeOf(context);
      final width = math.min(1180.0, size.width - 96);
      final cols = math.max(1, math.min(3, ((width - 36 + 20) / (260 + 20)).floor()));
      final perCol = (c.entries.length / cols).ceil();
      final grid = c.mode == CatalogMode.grid;
      Widget item(CategoryEntry e) {
        final on = grid && e.id == c.cat;
        return HoverBuilder(
          onActivate: () {
            Navigator.pop(context);
            c.openGrid(e.id);
          },
          focusRingRadius: 6,
          builder: (context, hover) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              c.openGrid(e.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: hover ? const Color(0x12FFFFFF) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The whole name (on two lines if needed), the padlock
                  // right after it, the count on the right.
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: e.label,
                        children: [
                          if (e.locked)
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.accent),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: on ? AppColors.accent : AppColors.text,
                      ),
                    ),
                  ),
                  if (e.count != null) ...[
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(formatCount(e.count!), style: monoStyle(12, height: 1.2)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }

      return Stack(
        children: [
          Positioned(
            left: 48,
            top: kTopBarHeight + 56,
            width: width,
            child: Material(
              color: AppColors.surface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0x1AFFFFFF)),
              ),
              elevation: 0,
              shadowColor: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxHeight: size.height - kTopBarHeight - 96),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0xA6000000), blurRadius: 80, offset: Offset(0, 30))],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var col = 0; col < cols; col++) ...[
                        if (col > 0) const SizedBox(width: 20),
                        Expanded(
                          child: Column(children: [for (final e in c.entries.skip(col * perCol).take(perCol)) item(e)]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

// ------------------------------------------------------------- grid poster

/// Poster of "Tout le catalogue": on hover a larger copy (×1.12) is shown
/// above everything with play, "+", "i" and the genre.
class GridPoster extends StatefulWidget {
  const GridPoster({super.key, required this.item, this.progress});
  final PosterItem item;
  final double? progress;

  @override
  State<GridPoster> createState() => _GridPosterState();
}

class _GridPosterState extends State<GridPoster> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _base = false, _over = false, _focus = false;

  void _update({bool? base, bool? over, bool? focus}) {
    _base = base ?? _base;
    _over = over ?? _over;
    _focus = focus ?? _focus;
    final show = _base || _over || _focus;
    if (show && !_portal.isShowing) {
      _portal.show();
    } else if (!show && _portal.isShowing) {
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.item;
    // Hidden tab or covered page: no floating copy left behind.
    if (!TickerMode.valuesOf(context).enabled && _portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _update(base: false, over: false, focus: false));
      });
    }
    final meta = [
      if (m.year != null) Text('${m.year}'),
      if (m.rating != null && m.rating! > 0)
        Text('★ ${m.rating!.toStringAsFixed(1).replaceAll('.', ',')}', style: const TextStyle(color: AppColors.accent)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: LayoutBuilder(
            builder: (context, box) => CompositedTransformTarget(
              link: _link,
              child: OverlayPortal(
                controller: _portal,
                overlayChildBuilder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.center,
                    followerAnchor: Alignment.center,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _update(over: true)),
                      onExit: (_) => setState(() => _update(over: false)),
                      child: SizedBox(
                        width: box.maxWidth,
                        height: box.maxHeight,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 1, end: 1.12),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.ease,
                          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                          child: _poster(m, lifted: true),
                        ),
                      ),
                    ),
                  ),
                ),
                child: FocusableActionDetector(
                  mouseCursor: SystemMouseCursors.click,
                  onShowHoverHighlight: (v) => setState(() => _update(base: v)),
                  onShowFocusHighlight: (v) => setState(() => _update(focus: v)),
                  actions: {
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        m.onPlay();
                        return null;
                      },
                    ),
                  },
                  child: _poster(m, lifted: false),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          m.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
        ),
        const SizedBox(height: 5),
        DefaultTextStyle.merge(
          style: monoStyle(12, height: 1),
          child: Row(
            children: [
              for (final (i, w) in meta.indexed) ...[if (i > 0) const SizedBox(width: 8), w],
            ],
          ),
        ),
      ],
    );
  }

  Widget _poster(PosterItem m, {required bool lifted}) => GestureDetector(
    onTap: m.onPlay,
    onSecondaryTapUp: m.onContextMenu == null ? null : (d) => m.onContextMenu!(d.globalPosition),
    onLongPressStart: m.onContextMenu == null ? null : (d) => m.onContextMenu!(d.globalPosition),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: lifted ? const [BoxShadow(color: Color(0xB3000000), blurRadius: 50, offset: Offset(0, 24))] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Artwork(url: m.poster, label: m.title, decodeWidth: 240),
          if (widget.progress != null && widget.progress! > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ProgressLine(widget.progress!, height: 3, track: const Color(0x59FFFFFF)),
            ),
          if (lifted)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xF70D0C0B), Color(0xF70D0C0B), Color(0x000D0C0B)],
                    stops: [0, 0.3, 1],
                  ),
                ),
                child: Row(
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
                      const SizedBox(width: 8),
                      CircleAction(icon: Icons.info_outline_rounded, onTap: m.onInfo!, tooltip: "Plus d'infos"),
                    ],
                    if (m.genre != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.genre!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSoft),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
