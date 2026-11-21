import 'package:bobine/core/text.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/epg_cache.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/tv/tv_rows.dart';
import 'package:bobine/tv/tv_search.dart';
import 'package:flutter_test/flutter_test.dart';

(Repository, int) _fixture() {
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
  db.execute('INSERT INTO channels (source_id, ext_id, name, search, position, number) VALUES (?, ?, ?, ?, ?, ?)', [
    id,
    'c1',
    'Canal Film',
    searchKey('Canal Film'),
    1,
    1,
  ]);
  for (final (i, name) in ['Le Grand Film', 'Film secret', 'Autre chose'].indexed) {
    db.execute(
      'INSERT INTO movies (source_id, ext_id, category_id, name, search, position) VALUES (?, ?, ?, ?, ?, ?)',
      [id, 'm$i', i == 1 ? 21 : 20, name, searchKey(name), i],
    );
  }
  db.execute('INSERT INTO series (source_id, ext_id, name, search, position) VALUES (?, ?, ?, ?, 0)', [
    id,
    's1',
    'Le film de la série',
    searchKey('Le film de la série'),
  ]);
  return (repo, id);
}

List<TvRow> _search(Repository repo, int id, String q) =>
    tvSearchRows(repo: repo, epg: EpgCache(repo), sourceId: id, query: q, name: (c) => c.name);

void main() {
  test('chaînes, films et séries qui correspondent, chacun dans sa rangée', () {
    final (repo, id) = _fixture();
    final rows = _search(repo, id, 'film');
    expect(rows.map((r) => r.title), ['Chaînes', 'Films', 'Séries']);
    expect(rows[0].style, TvRowStyle.live);
    expect(rows[1].items.map((i) => i.title), containsAll(['Le Grand Film', 'Film secret']));
    expect(rows[2].items.single.kind, TvItemKind.series);
  });

  test('moins de deux lettres : rien (pas de recherche sur tout le catalogue)', () {
    final (repo, id) = _fixture();
    expect(_search(repo, id, ''), isEmpty);
    expect(_search(repo, id, 'f'), isEmpty);
  });

  test('sans résultat : aucune rangée ; le contenu verrouillé n’apparaît pas', () {
    final (repo, id) = _fixture();
    expect(_search(repo, id, 'zzz'), isEmpty);
    repo.setCategoryLocked(id, ContentKind.movie, 'adu', true);
    repo.hideLocked = true;
    final films = _search(repo, id, 'film').firstWhere((r) => r.title == 'Films');
    expect(films.items.map((i) => i.title), isNot(contains('Film secret')));
  });
}
