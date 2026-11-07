import 'package:flutter/material.dart';

import '../core/text.dart';
import '../data/models.dart';
import '../services.dart';
import 'widgets/common.dart';

/// One channel as shown in Direct and the guide: its streams of different
/// qualities grouped (when the setting is on), the best one played.
class ChannelTile {
  const ChannelTile({required this.channel, required this.name, required this.quality, required this.variants});

  /// Stream that plays (the best quality of the group).
  final Channel channel;
  final String name;
  final String? quality;
  final List<Channel> variants;
}

/// Channel groups and channels shared by Direct and Guide TV, so both show
/// the same group.
class LiveCatalog extends ChangeNotifier {
  LiveCatalog(this._s) {
    _s.library.addListener(_onLibrary);
    _s.settings.addListener(_onSettings);
    reload();
  }

  final AppServices _s;
  Source? source;
  List<CategoryEntry> entries = const [];
  String cat = 'all';
  Set<String> favs = const {};
  List<ChannelTile> tiles = const [];

  /// Channels of the group before grouping (stream count).
  int streamCount = 0;

  int _contentVersion = -1;
  bool _clean = true, _group = true;

  @override
  void dispose() {
    _s.library.removeListener(_onLibrary);
    _s.settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onLibrary() {
    if (_s.library.content != _contentVersion || source?.id != _s.settings.activeSourceId) {
      reload();
    } else if (source != null) {
      // Favourites / recent changed.
      favs = _s.repo.favoriteKeys(source!.id, ContentKind.live);
      entries = withFavoriteCount(entries, favs.length);
      if (cat == 'fav' || cat == 'recent') _loadChannels();
      notifyListeners();
    }
  }

  void _onSettings() {
    if (_s.settings.cleanNames != _clean || _s.settings.groupQualities != _group) {
      _loadChannels();
      notifyListeners();
    }
  }

  void reload() {
    _contentVersion = _s.library.content;
    final src = _s.activeSource;
    source = src;
    if (src == null) {
      entries = const [];
      tiles = const [];
      notifyListeners();
      return;
    }
    final cats = _s.repo.categories(src.id, ContentKind.live);
    favs = _s.repo.favoriteKeys(src.id, ContentKind.live);
    final total = _s.repo.count(src.id, ContentKind.live);
    final recent = _s.repo.recentChannels(src.id, limit: 1).isNotEmpty;
    entries = [
      CategoryEntry(id: 'all', label: 'Toutes', count: total),
      CategoryEntry(id: 'fav', label: 'Favoris', count: favs.length),
      if (recent) const CategoryEntry(id: 'recent', label: 'Récentes'),
      for (final c in cats) CategoryEntry(id: 'c:${c.id}', label: c.name, count: c.count, locked: c.locked),
    ];
    final saved = _s.repo.kvGet('live.cat.${src.id}');
    cat = saved != null && entries.any((e) => e.id == saved) ? saved : 'all';
    _loadChannels();
    notifyListeners();
  }

  void select(String id) {
    if (id == cat) return;
    cat = id;
    if (source != null) _s.repo.kvSet('live.cat.${source!.id}', id);
    _loadChannels();
    notifyListeners();
  }

  void _loadChannels() {
    final src = source;
    if (src == null) return;
    final list = switch (cat) {
      'fav' => _s.repo.favoriteChannels(src.id),
      'recent' => _s.repo.recentChannels(src.id),
      'all' => _s.repo.channels(src.id),
      _ => _s.repo.channels(src.id, categoryId: int.tryParse(cat.substring(2))),
    };
    streamCount = list.length;
    _clean = _s.settings.cleanNames;
    _group = _s.settings.groupQualities;
    tiles = group(list, clean: _clean, merge: _group);
  }

  /// Groups [channels] by name once qualities and prefixes are removed,
  /// keeping the order of first appearance.
  static List<ChannelTile> group(List<Channel> channels, {required bool clean, required bool merge}) {
    if (!merge) {
      return [
        for (final c in channels)
          ChannelTile(channel: c, name: clean ? cleanChannelName(c.name) : c.name, quality: channelQuality(c.name), variants: [c]),
      ];
    }
    final byKey = <String, List<Channel>>{};
    for (final c in channels) {
      final k = channelMatchKey(c.name);
      byKey.putIfAbsent(k.isEmpty ? '#${c.extId}' : k, () => []).add(c);
    }
    return [
      for (final variants in byKey.values)
        () {
          final best = variants.reduce(
            (a, b) => qualityRank(channelQuality(b.name)) > qualityRank(channelQuality(a.name)) ? b : a,
          );
          return ChannelTile(
            channel: best,
            name: clean ? cleanChannelName(best.name) : best.name,
            quality: channelQuality(best.name),
            variants: variants,
          );
        }(),
    ];
  }

  /// Channels played when zapping (one per tile).
  List<Channel> get playList => [for (final t in tiles) t.channel];

  /// Tiles whose name, or programme on air, matches [query].
  List<ChannelTile> filtered(String query) {
    final words = searchWords(query);
    if (words.isEmpty || source == null) return tiles;
    final onAir = {
      for (final h in _s.repo.searchPrograms(source!.id, query, back: Duration.zero, ahead: Duration.zero, limit: 2000))
        h.channel.extId,
    };
    return [
      for (final t in tiles)
        if (t.variants.any((c) => matchesWords(c.search, words) || onAir.contains(c.extId))) t,
    ];
  }

  String get label => entries.where((e) => e.id == cat).firstOrNull?.label ?? '';
}
