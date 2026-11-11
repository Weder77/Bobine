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
  final _catIds = <String, int>{};
  Set<String> favs = const {};
  List<ChannelTile> tiles = const [];

  /// Channels of the group before grouping (stream count).
  int streamCount = 0;

  int _contentVersion = -1;
  bool _clean = true, _group = true;
  String _quality = 'Auto';

  @override
  void dispose() {
    _s.library.removeListener(_onLibrary);
    _s.settings.removeListener(_onSettings);
    super.dispose();
  }

  bool _shown = true, _stale = false;

  /// Direct or the guide is on screen. Hidden, the channels are not
  /// loaded and grouped again at each change (a profile, a favourite, the
  /// end of an import): they are when shown.
  set shown(bool v) {
    if (v == _shown) return;
    _shown = v;
    if (v && _stale) {
      _stale = false;
      _onLibrary();
    }
  }

  void _onLibrary() {
    if (!_shown) {
      _stale = true;
      return;
    }
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
    if (!_shown) {
      _stale = true;
      _contentVersion = -1; // grouped again when shown
      return;
    }
    if (_s.settings.cleanNames != _clean ||
        _s.settings.groupQualities != _group ||
        _s.settings.preferredQuality != _quality) {
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
      for (final c in cats) CategoryEntry(id: 'x:${c.extId}', label: c.name, count: c.count, locked: c.locked),
    ];
    // Groups are known by the provider's id: the row numbers change at
    // every import, and the remembered group became its neighbour.
    _catIds
      ..clear()
      ..addAll({for (final c in cats) 'x:${c.extId}': c.id});
    var saved = _s.repo.kvGet('live.cat.${src.id}');
    if (saved != null && saved.startsWith('c:')) {
      // Saved by an earlier version, by row number.
      final old = int.tryParse(saved.substring(2));
      final c = cats.where((c) => c.id == old).firstOrNull;
      saved = c == null ? null : 'x:${c.extId}';
    }
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
      _ => _catIds[cat] == null ? const <Channel>[] : _s.repo.channels(src.id, categoryId: _catIds[cat]),
    };
    streamCount = list.length;
    _clean = _s.settings.cleanNames;
    _group = _s.settings.groupQualities;
    _quality = _s.settings.preferredQuality;
    tiles = group(list, clean: _clean, merge: _group, preferred: _quality);
  }

  /// Groups [channels] by name once qualities and prefixes are removed,
  /// keeping the order of first appearance.
  static List<ChannelTile> group(
    List<Channel> channels, {
    required bool clean,
    required bool merge,
    String preferred = 'Auto',
  }) {
    if (!merge) {
      return [
        for (final c in channels)
          ChannelTile(
            channel: c,
            name: clean ? cleanChannelName(c.name) : c.name,
            quality: channelQuality(c.name),
            variants: [c],
          ),
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
          final best =
              variants.where((c) => channelQuality(c.name) == preferred).firstOrNull ??
              variants.reduce(
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
    final onAir = _s.repo.channelsOnAir(source!.id, query);
    return [
      for (final t in tiles)
        if (t.variants.any((c) => matchesWords(c.search, words) || onAir.contains(c.extId))) t,
    ];
  }

  String get label => entries.where((e) => e.id == cat).firstOrNull?.label ?? '';
}
