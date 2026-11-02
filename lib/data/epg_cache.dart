import '../core/text.dart';
import 'models.dart';
import 'repository.dart';

/// Resolves channels to EPG ids and memoises "now playing" lookups so long
/// channel lists can show the current programme without hitting SQLite on
/// every frame.
class EpgCache {
  EpgCache(this._repo);
  final Repository _repo;

  final Map<String, String?> _keys = {};
  final Map<String, _NowEntry> _now = {};

  void clear() {
    _keys.clear();
    _now.clear();
  }

  String _id(Channel c) => '${c.sourceId}:${c.extId}';

  /// EPG channel key for [c], or null when no guide data matches.
  String? keyFor(Channel c) {
    final id = _id(c);
    if (_keys.containsKey(id)) return _keys[id];
    String? key;
    final epgId = c.epgId?.trim().toLowerCase();
    if (epgId != null && epgId.isNotEmpty && _repo.hasEpgFor(c.sourceId, epgId)) {
      key = epgId;
    } else {
      final byName = _repo.epgIdForNameKey(c.sourceId, channelMatchKey(c.name));
      if (byName != null) key = byName;
    }
    _keys[id] = key;
    return key;
  }

  /// Current programme for [c] (cached until it ends).
  Program? now(Channel c) {
    final id = _id(c);
    final t = DateTime.now();
    final cached = _now[id];
    if (cached != null && t.isBefore(cached.validUntil)) return cached.program;
    final key = keyFor(c);
    final p = key == null ? null : _repo.programAt(c.sourceId, key, t);
    _now[id] = _NowEntry(p, p?.stop ?? t.add(const Duration(minutes: 5)));
    return p;
  }

  /// Programmes of [c] between [from] and [to].
  List<Program> programs(Channel c, DateTime from, DateTime to) {
    final key = keyFor(c);
    if (key == null) return const [];
    return _repo.programs(c.sourceId, key, from, to);
  }
}

class _NowEntry {
  _NowEntry(this.program, this.validUntil);
  final Program? program;
  final DateTime validUntil;
}
