import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/data/repository.dart';

void main() {
  test('a profile or a source made again under the same id starts clean', () {
    final repo = Repository(openMemoryDatabase());
    final lea = repo.createProfile(name: 'Léa', color: 1);
    repo.profileId = lea;
    repo.addRecentSearch('dessins animés');
    repo.profileId = 1;
    repo.deleteProfile(lea);
    final tom = repo.createProfile(name: 'Tom', color: 1);
    expect(tom, lea, reason: 'SQLite gives the id again');
    repo.profileId = tom;
    expect(repo.recentSearches(), isEmpty);

    final src = repo.insertSource(name: 'S', type: SourceType.m3u, url: 'http://s/a.m3u');
    repo.db.execute(
      "INSERT INTO epg_programs (source_id, channel, start, stop, title) VALUES (?, 'c', 1, 2, 'Journal')",
      [src],
    );
    repo.kvSet('live.cat.$src', 'x:sport');
    // Deleted the way the account does it, straight in the table.
    repo.db.execute('DELETE FROM sources WHERE id = ?', [src]);
    final again = repo.insertSource(name: 'T', type: SourceType.m3u, url: 'http://t/a.m3u');
    expect(again, src);
    expect(repo.db.select('SELECT 1 FROM epg_programs WHERE source_id = ?', [again]), isEmpty);
    expect(repo.kvGet('live.cat.$again'), isNull);
  });
}
