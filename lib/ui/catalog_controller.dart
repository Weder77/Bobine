import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services.dart';
import 'widgets/common.dart';

enum CatalogMode { rows, grid }

/// State of the Films or Séries page, shared with the header's sub-bar:
/// "Parcourir" (rows) or "Tout le catalogue" (grid), category, sort and
/// filter of the grid.
class CatalogController extends ChangeNotifier {
  CatalogController(this._s, {required this.series}) {
    final saved = _s.repo.kvGet('catalog.sort.${kind.db}');
    sort =
        CatalogSort.values.where((v) => v.name == saved && v != CatalogSort.provider).firstOrNull ?? CatalogSort.added;
    _s.library.addListener(_onLibrary);
    reload();
  }

  final AppServices _s;
  final bool series;
  ContentKind get kind => series ? ContentKind.series : ContentKind.movie;
  String get title => series ? 'Séries' : 'Films';

  Source? source;
  List<CategoryEntry> entries = const [];
  CatalogMode mode = CatalogMode.rows;
  String cat = 'all';
  final _catIds = <String, int>{};

  /// Row of the chosen category, null for "all" and "fav".
  int? get categoryId => _catIds[cat];
  late CatalogSort sort;
  String query = '';

  /// Bumped when the content or the user's data changed (the page reloads
  /// what depends on them).
  int version = 0;

  /// Bumped only when the provider's content was reloaded: the rows and
  /// the grid made from it are kept across a favourite or a position.
  int contentVersion = 0;
  int _contentVersion = -1;

  bool _shown = true, _stale = false;

  /// The page is on screen. Hidden, it does not reload at each change (a
  /// favourite, a position, the end of an import): it does when shown.
  set shown(bool v) {
    if (v == _shown) return;
    _shown = v;
    if (v && _stale) {
      _stale = false;
      _onLibrary();
    }
  }

  @override
  void dispose() {
    _s.library.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (!_shown) {
      _stale = true;
      return;
    }
    if (_s.library.content != _contentVersion || source?.id != _s.settings.activeSourceId) {
      reload();
    } else if (source != null) {
      final favs = _s.repo.favoriteKeys(source!.id, kind).length;
      entries = withFavoriteCount(entries, favs);
      version++;
      notifyListeners();
    }
  }

  void reload() {
    _contentVersion = _s.library.content;
    final src = _s.activeSource;
    source = src;
    if (src == null) {
      entries = const [];
    } else {
      // Locked categories are listed (with a padlock) unless in a kids
      // profile, where they cannot be unlocked.
      final cats = _s.repo.categories(src.id, kind, includeLocked: !_s.profile.kids);
      entries = [
        CategoryEntry(
          id: 'all',
          label: series ? 'Toutes les séries' : 'Tous les films',
          count: _s.repo.count(src.id, kind),
        ),
        CategoryEntry(id: 'fav', label: 'Mes favoris', count: _s.repo.favoriteKeys(src.id, kind).length),
        for (final c in cats) CategoryEntry(id: 'x:${c.extId}', label: c.name, count: c.count, locked: c.locked),
      ];
      // By the provider's id, which an import keeps (see the live list).
      _catIds
        ..clear()
        ..addAll({for (final c in cats) 'x:${c.extId}': c.id});
      if (!entries.any((e) => e.id == cat)) cat = 'all';
    }
    version++;
    contentVersion++;
    notifyListeners();
  }

  CategoryEntry? get entry => entries.where((e) => e.id == cat).firstOrNull;

  /// Whether the chosen category is locked and the parental code not typed.
  bool get locked => (entry?.locked ?? false) && _s.repo.hideLocked;

  void openGrid([String? category, CatalogSort? sortBy]) {
    mode = CatalogMode.grid;
    if (category != null) cat = category;
    if (sortBy != null) setSort(sortBy, notify: false);
    query = '';
    notifyListeners();
  }

  void toRows() {
    mode = CatalogMode.rows;
    cat = 'all';
    query = '';
    notifyListeners();
  }

  void clearCategory() {
    cat = 'all';
    query = '';
    notifyListeners();
  }

  void setSort(CatalogSort v, {bool notify = true}) {
    sort = v;
    _s.repo.kvSet('catalog.sort.${kind.db}', v.name);
    if (notify) notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }
}
