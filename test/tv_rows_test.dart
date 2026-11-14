import 'package:bobine/core/text.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/epg_cache.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/tv/tv_rows.dart';
import 'package:bobine/tv/tv_shell.dart';
import 'package:flutter_test/flutter_test.dart';

(Repository, int) _fixture({bool channels = true, bool movies = true}) {
  final repo = Repository(openMemoryDatabase());
  final id = repo.insertSource(
    name: 'S',
    type: SourceType.xtream,
    url: 'http://tv.example',
    username: 'u',
    password: 'p',
  );
  final db = repo.db;
  db.execute(
    "INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (20, ?, 'movie', 'act', 'Action', 0)",
    [id],
  );
  db.execute(
    "INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (21, ?, 'movie', 'adu', 'Adultes', 1)",
    [id],
  );
  db.execute(
    "INSERT INTO categories (id, source_id, kind, ext_id, name, position) VALUES (30, ?, 'series', 'fr', 'Made in France', 0)",
    [id],
  );
  if (channels) {
    for (var i = 1; i <= 3; i++) {
      db.execute('INSERT INTO channels (source_id, ext_id, name, search, position, number) VALUES (?, ?, ?, ?, ?, ?)', [
        id,
        'c$i',
        'Chaîne $i',
        searchKey('Chaîne $i'),
        i,
        i,
      ]);
    }
  }
  if (movies) {
    for (var i = 1; i <= 5; i++) {
      db.execute(
        'INSERT INTO movies (source_id, ext_id, category_id, name, search, position, rating, year, added) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, 'm$i', i == 5 ? 21 : 20, 'Film $i', 'film $i', i, i.toDouble(), 2020 + i, 1700000000 + i],
      );
    }
    db.execute(
      'INSERT INTO series (source_id, ext_id, category_id, name, search, position, rating, year, added) '
      'VALUES (?, ?, 30, ?, ?, 0, 8.1, 2021, 1700000100)',
      [id, 's1', 'Série 1', 'serie 1'],
    );
  }
  return (repo, id);
}

List<TvRow> _rows(Repository repo, int id, TvTab tab, {int rowLimit = 20}) => tvRows(
  repo: repo,
  epg: EpgCache(repo),
  sourceId: id,
  tab: tab,
  name: (c) => c.name,
  now: DateTime(2026, 11, 14, 21),
  rowLimit: rowLimit,
);

void main() {
  test('Accueil : En direct maintenant, Reprendre, Top 10 aujourd’hui, Ajoutés récemment', () {
    final (repo, id) = _fixture();
    repo.saveProgress(
      sourceId: id,
      kind: ContentKind.movie,
      extId: 'm2',
      position: const Duration(minutes: 30),
      duration: const Duration(minutes: 100),
      title: 'Film 2',
    );
    final rows = _rows(repo, id, TvTab.home);
    expect(rows.map((r) => r.title), ['En direct maintenant', 'Reprendre', 'Top 10 aujourd’hui', 'Ajoutés récemment']);
    expect(rows.map((r) => r.style), [TvRowStyle.live, TvRowStyle.wide, TvRowStyle.top, TvRowStyle.poster]);
    final resume = rows[1].items.single;
    expect(resume.title, 'Film 2');
    expect(resume.progress, closeTo(0.3, 0.01));
    expect(resume.progressLabel, 'reste 1 h 10');
    expect(rows[2].items.first.number, '1');
    // Newest first.
    expect(rows[3].items.first.title, 'Film 5');
  });

  test('une rangée vide est omise (pas de chaînes, rien à reprendre)', () {
    final (repo, id) = _fixture(channels: false);
    expect(_rows(repo, id, TvTab.home).map((r) => r.title), ['Top 10 aujourd’hui', 'Ajoutés récemment']);
    final (empty, eid) = _fixture(channels: false, movies: false);
    expect(_rows(empty, eid, TvTab.home), isEmpty);
    expect(_rows(empty, eid, TvTab.films), isEmpty);
  });

  test('le contenu verrouillé par le contrôle parental n’apparaît nulle part', () {
    final (repo, id) = _fixture();
    repo.setCategoryLocked(id, ContentKind.movie, 'adu', true);
    repo.hideLocked = true;
    for (final tab in [TvTab.home, TvTab.films]) {
      final titles = {for (final r in _rows(repo, id, tab)) ...r.items.map((i) => i.title)};
      expect(titles, isNot(contains('Film 5')), reason: tab.name);
    }
    expect(_rows(repo, id, TvTab.films).map((r) => r.title), isNot(contains('Adultes')));
  });

  test('Films : « Ma liste » seulement quand un film y est', () {
    final (repo, id) = _fixture();
    expect(_rows(repo, id, TvTab.films).map((r) => r.title), isNot(contains('Ma liste')));
    repo.toggleFavorite(id, ContentKind.movie, 'm3');
    final rows = _rows(repo, id, TvTab.films);
    expect(rows.map((r) => r.title), contains('Ma liste'));
    expect(rows.firstWhere((r) => r.title == 'Ma liste').items.single.title, 'Film 3');
    expect(rows.map((r) => r.title), containsAllInOrder(['Nouveautés', 'Ma liste', 'Top 10 des films', 'Action']));
  });

  test('Séries : catégorie du fournisseur, et l’élément mène à la série', () {
    final (repo, id) = _fixture();
    final rows = _rows(repo, id, TvTab.series);
    expect(rows.map((r) => r.title), containsAll(['Nouveautés', 'Top 10 des séries', 'Made in France']));
    final item = rows.first.items.single;
    expect(item.kind, TvItemKind.series);
    expect(item.meta, '★ 8,1   ·   2021');
  });

  test('Voir tout : seulement sur une rangée coupée, et il donne toute la liste', () {
    final (repo, id) = _fixture();
    final rows = _rows(repo, id, TvTab.films, rowLimit: 3);
    TvRow row(String t) => rows.firstWhere((r) => r.title == t);
    expect(row('Nouveautés').items, hasLength(3));
    expect(row('Nouveautés').all!().map((i) => i.title), ['Film 5', 'Film 4', 'Film 3', 'Film 2', 'Film 1']);
    expect(row('Action').all!(), hasLength(4));
    expect(row('Top 10 des films').all, isNull);
    final full = _rows(repo, id, TvTab.films);
    expect(full.firstWhere((r) => r.title == 'Nouveautés').all, isNull);
  });

  test('Films : À la une, Tout, puis les catégories du fournisseur (sans les verrouillées)', () {
    final (repo, id) = _fixture();
    expect(tvCatalogPills(repo, id, TvTab.films).map((p) => p.label), ['À la une', 'Tout', 'Action', 'Adultes']);
    expect(tvCatalogPills(repo, id, TvTab.series).map((p) => p.label), ['À la une', 'Tout', 'Made in France']);
    expect(tvCatalogPills(repo, id, TvTab.home), isEmpty);
    repo.setCategoryLocked(id, ContentKind.movie, 'adu', true);
    repo.hideLocked = true;
    expect(tvCatalogPills(repo, id, TvTab.films).map((p) => p.label), ['À la une', 'Tout', 'Action']);
  });

  test('la grille d’une pastille : tout, ou la catégorie, en entier', () {
    final (repo, id) = _fixture();
    expect(tvCatalogItems(repo, id, TvTab.films, 'all'), hasLength(5));
    final action = tvCatalogItems(repo, id, TvTab.films, 'c:20');
    expect(action.map((i) => i.title), ['Film 1', 'Film 2', 'Film 3', 'Film 4']);
    expect(action.first.kicker, 'Film · Action');
    final series = tvCatalogItems(repo, id, TvTab.series, 'all');
    expect(series.single.kind, TvItemKind.series);
  });
}
