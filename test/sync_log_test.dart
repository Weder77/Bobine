import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';

Map<String, int> _log(Repository r) => {
  for (final row in r.db.select('SELECT tbl, key, changed_at FROM sync_log'))
    '${row['tbl']} ${row['key']}': row['changed_at'] as int,
};

void main() {
  _conflictPolicies();

  test('sources and profiles get a uid; the first profile is the same everywhere', () {
    final repo = Repository(openMemoryDatabase());
    expect(repo.db.select('SELECT uid FROM profiles WHERE id = 1').single['uid'], kDefaultProfileUid);
    final a = repo.insertSource(name: 'A', type: SourceType.m3u, url: 'http://a');
    final b = repo.insertSource(name: 'B', type: SourceType.m3u, url: 'http://b');
    final uids = repo.db.select('SELECT uid FROM sources ORDER BY id').map((r) => r['uid'] as String).toList();
    expect(uids, hasLength(2));
    expect(uids.toSet(), hasLength(2));
    expect(uids.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(_log(repo).keys, containsAll(['sources ${uids[0]}', 'sources ${uids[1]}']));
    expect(a, isNot(b));
  });

  test('every change to the user data is noted, imports are not', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s');
    repo.db.execute('DELETE FROM sync_log');

    final before = DateTime.now().millisecondsSinceEpoch;
    repo.toggleFavorite(src, ContentKind.movie, '42');
    final key = 'favorites [1,$src,"movie","42"]';
    expect(_log(repo)[key], inInclusiveRange(before - 5, DateTime.now().millisecondsSinceEpoch + 5));

    repo.toggleFavorite(src, ContentKind.movie, '42'); // removed: still noted, the row is gone
    expect(_log(repo).keys, [key]);
    expect(repo.isFavorite(src, ContentKind.movie, '42'), isFalse);

    repo.setCategoryHidden(src, ContentKind.live, 'sport', true);
    repo.setChannelHidden(src, 'tf1', true);
    repo.touchChannel(src, 'tf1');
    expect(
      _log(repo).keys,
      containsAll([
        'category_prefs [$src,"live","sport"]',
        'channel_prefs [$src,"tf1"]',
        'recent_channels [1,$src,"tf1"]',
      ]),
    );

    repo.db.execute('DELETE FROM sync_log');
    // What an import writes on a source is not the user's.
    repo.db.execute('UPDATE sources SET content_updated_at = 1, last_error = NULL, account_info = NULL WHERE id = ?', [
      src,
    ]);
    expect(_log(repo), isEmpty);
    repo.updateSource(src, name: 'Renommée', url: 'http://s');
    expect(_log(repo).keys.single, startsWith('sources '));
  });

  test('changes made while muted (coming from the account) are not noted', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s');
    repo.db.execute('DELETE FROM sync_log');
    repo.db.execute('INSERT INTO sync_mute VALUES (1)');
    repo.toggleFavorite(src, ContentKind.movie, '42');
    repo.createProfile(name: 'Léa', color: 0);
    repo.db.execute('DELETE FROM sync_mute');
    expect(_log(repo), isEmpty);
    expect(repo.profiles().last.name, 'Léa');
    expect(repo.db.select("SELECT uid FROM profiles WHERE name = 'Léa'").single['uid'], isNotNull);
  });

  test('a new source reusing the id of a deleted one does not inherit its notes', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s');
    repo.toggleFavorite(src, ContentKind.movie, '42');
    repo.deleteSource(src);
    final again = repo.insertSource(name: 'T', type: SourceType.m3u, url: 'http://t');
    expect(again, src); // SQLite reuses the id
    expect(_log(repo).keys.where((k) => k.startsWith('favorites')), isEmpty);
    expect(_log(repo).keys.where((k) => k.startsWith('sources')), hasLength(2)); // deleted one + new one
  });
}

void _conflictPolicies() {
  test('noted whatever conflict policy the statement uses (upsert, OR IGNORE, OR REPLACE)', () {
    final repo = Repository(openMemoryDatabase());
    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s');
    repo.setCategoryLocked(src, ContentKind.live, 'xx', true); // upsert
    repo.setCategoryLocked(src, ContentKind.live, 'xx', false); // upsert on an existing row
    repo.db.execute('UPDATE sync_log SET changed_at = 1');
    repo.db.execute("INSERT OR IGNORE INTO favorites VALUES (1, ?, 'movie', 'm', 5)", [src]);
    repo.db.execute("INSERT OR REPLACE INTO favorites VALUES (1, ?, 'movie', 'm', 6)", [src]);
    repo.setCategoryHidden(src, ContentKind.live, 'xx', true);
    final log = _log(repo);
    expect(log['category_prefs [$src,"live","xx"]'], greaterThan(1));
    expect(log['favorites [1,$src,"movie","m"]'], greaterThan(1));
    expect(repo.db.select('SELECT locked, hidden FROM category_prefs').single.values, [0, 1]);
  });
}
