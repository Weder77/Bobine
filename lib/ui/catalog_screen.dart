import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services.dart';
import 'launch.dart';
import 'widgets/common.dart';

/// Films or Séries: category pane + virtualised poster grid.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.series});
  final bool series;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _Item {
  _Item({required this.extId, required this.name, required this.key, this.poster, this.year, this.rating, this.movie, this.show});
  final String extId;
  final String name;
  final String key;
  final String? poster;
  final int? year;
  final double? rating;
  final Movie? movie;
  final Series? show;
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final AppServices _s;
  Source? _source;
  List<CategoryEntry> _entries = const [];
  String _cat = 'all';
  CatalogSort _sort = CatalogSort.added;
  List<_Item> _items = const [];
  List<_Item> _visible = const [];
  Set<String> _favs = const {};
  Map<String, double> _progress = const {};
  String _filter = '';
  Timer? _debounce;
  int _contentVersion = -1;
  final _scroll = ScrollController();

  ContentKind get _kind => widget.series ? ContentKind.series : ContentKind.movie;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_onLibrary);
    final savedSort = _s.repo.kvGet('catalog.sort.${_kind.db}');
    _sort = CatalogSort.values.where((v) => v.name == savedSort).firstOrNull ?? CatalogSort.added;
    _reload();
  }

  @override
  void dispose() {
    _s.library.removeListener(_onLibrary);
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onLibrary() {
    if (_s.library.content != _contentVersion || _source?.id != _s.settings.activeSourceId) {
      _reload();
    } else {
      setState(() {
        _loadUserData();
        _entries = withFavoriteCount(_entries, _favs.length);
        if (_cat == 'fav') _loadItems();
      });
    }
  }

  void _loadUserData() {
    final src = _source;
    if (src == null) return;
    _favs = _s.repo.favoriteKeys(src.id, _kind);
    if (!widget.series) {
      _progress = {
        for (final p in _s.repo.continueWatching(src.id, limit: 500))
          if (p.kind == ContentKind.movie) p.extId: p.fraction,
      };
    }
  }

  void _reload() {
    _contentVersion = _s.library.content;
    final src = _s.activeSource;
    _source = src;
    if (src == null) return;
    _loadUserData();
    final cats = _s.repo.categories(src.id, _kind);
    _entries = [
      CategoryEntry(id: 'all', label: widget.series ? 'Toutes les séries' : 'Tous les films',
          count: _s.repo.count(src.id, _kind), icon: Icons.apps_rounded),
      CategoryEntry(id: 'fav', label: 'Mes favoris', count: _favs.length, icon: Icons.favorite_rounded),
      for (final c in cats) CategoryEntry(id: 'c:${c.id}', label: c.name, count: c.count),
    ];
    if (!_entries.any((e) => e.id == _cat)) _cat = 'all';
    _loadItems();
    if (mounted) setState(() {});
  }

  void _loadItems() {
    final src = _source;
    if (src == null) return;
    final catId = _cat.startsWith('c:') ? int.tryParse(_cat.substring(2)) : null;
    if (widget.series) {
      final list = _cat == 'fav'
          ? _s.repo.favoriteSeries(src.id)
          : _s.repo.series(src.id, categoryId: catId, sort: _sort);
      _items = [
        for (final x in list)
          _Item(extId: x.extId, name: x.name, key: x.search, poster: x.poster,
              year: x.year, rating: x.rating, show: x),
      ];
    } else {
      final list = _cat == 'fav'
          ? _s.repo.favoriteMovies(src.id)
          : _s.repo.movies(src.id, categoryId: catId, sort: _sort);
      _items = [
        for (final x in list)
          _Item(extId: x.extId, name: x.name, key: x.search, poster: x.poster,
              year: x.year, rating: x.rating, movie: x),
      ];
    }
    _applyFilter();
  }

  void _applyFilter() {
    final words = searchWords(_filter);
    _visible = words.isEmpty ? _items : _items.where((i) => matchesWords(i.key, words)).toList();
  }

  void _select(String id) {
    setState(() {
      _cat = id;
      _loadItems();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final label = _entries.where((e) => e.id == _cat).firstOrNull?.label ?? '';
    return Row(children: [
      CategoryPane(entries: _entries, selected: _cat, onSelect: _select),
      Expanded(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('${formatCount(_visible.length)} ${widget.series ? 'séries' : 'films'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 180), () {
                      setState(() {
                        _filter = v;
                        _applyFilter();
                      });
                    });
                  },
                  decoration: InputDecoration(
                    hintText: widget.series ? 'Filtrer les séries' : 'Filtrer les films',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<CatalogSort>(
                tooltip: 'Trier',
                initialValue: _sort,
                onSelected: (v) {
                  _s.repo.kvSet('catalog.sort.${_kind.db}', v.name);
                  setState(() {
                    _sort = v;
                    _loadItems();
                  });
                },
                itemBuilder: (_) => [
                  for (final v in CatalogSort.values)
                    PopupMenuItem(value: v, child: Text(v.label)),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.sort_rounded, size: 18, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Text(_sort.label, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              ),
            ]),
          ),
          Expanded(
            child: _visible.isEmpty
                ? EmptyState(
                    icon: _cat == 'fav' ? Icons.favorite_outline : Icons.movie_filter_outlined,
                    title: _cat == 'fav' ? 'Aucun favori' : 'Rien à afficher',
                    message: _cat == 'fav' ? 'Ajoute des favoris depuis la fiche d\'un titre.' : null,
                  )
                : Scrollbar(
                    controller: _scroll,
                    child: GridView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(28, 6, 28, 32),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: 22,
                        crossAxisSpacing: 18,
                        childAspectRatio: 0.54,
                      ),
                      itemCount: _visible.length,
                      itemBuilder: (context, i) {
                        final it = _visible[i];
                        return LayoutBuilder(
                          builder: (context, c) => PosterCard(
                            width: c.maxWidth,
                            title: it.name,
                            subtitle: it.year?.toString(),
                            image: it.poster,
                            rating: it.rating,
                            favorite: _favs.contains(it.extId),
                            progress: _progress[it.extId],
                            onTap: () => it.movie != null
                                ? Launch.openMovie(context, it.movie!)
                                : Launch.openSeries(context, it.show!),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ]),
      ),
    ]);
  }
}
