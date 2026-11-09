import 'dart:isolate';

import 'db.dart';
import 'models.dart';
import 'repository.dart';

/// What the search page shows for a query.
class SearchOutcome {
  const SearchOutcome(this.results, this.programs);

  /// Channels, films and series; null when the query is too short.
  final SearchResults? results;

  /// Programmes of the guide.
  final List<ProgramHit> programs;
}

/// Searches [query] with [repo]: channels, films and series from two
/// letters, the TV guide from three.
SearchOutcome runSearch(Repository repo, int sourceId, String query) {
  final t = query.trim();
  return SearchOutcome(
    t.length < 2 ? null : repo.search(sourceId, t),
    t.length < 3 ? const [] : repo.searchPrograms(sourceId, t),
  );
}

/// [runSearch] on another isolate, with its own connection to the database
/// at [dbPath]: reading tens of thousands of titles and the whole guide
/// takes a moment on big playlists, and typing must never wait for it.
///
/// [profileId] and [hideLocked] are those of the UI's repository (hidden and
/// locked categories are left out the same way).
Future<SearchOutcome> searchInBackground(
  String dbPath, {
  required int sourceId,
  required String query,
  required int profileId,
  required bool hideLocked,
}) => Isolate.run(() {
  final db = openWorkerDatabase(dbPath);
  try {
    final repo = Repository(db)
      ..profileId = profileId
      ..hideLocked = hideLocked;
    return runSearch(repo, sourceId, query);
  } finally {
    db.close();
  }
});
