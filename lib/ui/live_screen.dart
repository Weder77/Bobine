import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../player/play_items.dart';
import '../services.dart';
import 'epg_grid.dart';
import 'launch.dart';
import 'shell.dart';
import 'widgets/common.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.active, this.guide = false});

  /// Whether the tab is visible (the preview stops when leaving the tab).
  final bool active;

  /// "Guide TV" tab: same categories, shown as a programme grid.
  final bool guide;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late final AppServices _s;
  Source? _source;
  List<CategoryEntry> _entries = const [];
  String _cat = 'all';
  List<Channel> _channels = const [];
  List<Channel> _visible = const [];
  Set<String> _favs = const {};
  int _selected = -1;
  String _filter = '';
  int _contentVersion = -1;

  final _listScroll = ScrollController();
  final _listFocus = FocusNode(debugLabel: 'channels');
  Timer? _previewDebounce;
  Timer? _clock;
  /// Xtream short-EPG fallback, with the time it was fetched.
  final Map<String, ({DateTime fetchedAt, List<Program> programs})> _shortEpg = {};
  final Set<String> _shortEpgLoading = {};

  static const _rowHeight = 66.0;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_onLibrary);
    _s.player.current.addListener(_onPlayerChanged);
    _reload();
    // Refresh "now playing" lines every 30 s.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && widget.active) setState(() {});
    });
  }

  @override
  void didUpdateWidget(LiveScreen old) {
    super.didUpdateWidget(old);
    // Deferred: stopping notifies listeners, not allowed during this build.
    if (old.active && !widget.active) scheduleMicrotask(_stopPreview);
    if (!old.active && widget.active && !widget.guide) _listFocus.requestFocus();
  }

  @override
  void dispose() {
    _s.library.removeListener(_onLibrary);
    _s.player.current.removeListener(_onPlayerChanged);
    _previewDebounce?.cancel();
    _clock?.cancel();
    _listScroll.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _stopPreview() {
    if (_s.player.current.value?.isLive ?? false) _s.player.stop();
  }

  void _onLibrary() {
    if (_s.library.content != _contentVersion || _source?.id != _s.settings.activeSourceId) {
      _reload();
    } else {
      // Favourites / EPG changed.
      setState(() {
        if (_source != null) _favs = _s.repo.favoriteKeys(_source!.id, ContentKind.live);
        if (_cat == 'fav' || _cat == 'recent') _loadChannels();
      });
    }
  }

  /// Keeps the selection in sync after zapping in the full screen player.
  void _onPlayerChanged() {
    final cur = _s.player.current.value;
    if (cur == null || !cur.isLive || !mounted) return;
    final i = _visible.indexWhere((c) => c.extId == cur.extId);
    if (i >= 0 && i != _selected) {
      setState(() => _selected = i);
      _ensureVisible(i);
    }
  }

  void _reload() {
    _contentVersion = _s.library.content;
    _shortEpg.clear(); // source switched or edited (credentials, EPG offset)
    final src = _s.activeSource;
    _source = src;
    if (src == null) return;
    final cats = _s.repo.categories(src.id, ContentKind.live);
    _favs = _s.repo.favoriteKeys(src.id, ContentKind.live);
    final total = _s.repo.count(src.id, ContentKind.live);
    _entries = [
      CategoryEntry(id: 'fav', label: 'Favoris', count: _favs.length, icon: Icons.star_rounded),
      const CategoryEntry(id: 'recent', label: 'Récemment regardées', icon: Icons.history_rounded),
      CategoryEntry(id: 'all', label: 'Toutes les chaînes', count: total, icon: Icons.apps_rounded),
      for (final c in cats) CategoryEntry(id: 'c:${c.id}', label: c.name, count: c.count),
    ];
    final saved = _s.repo.kvGet('live.cat.${src.id}');
    if (saved != null && _entries.any((e) => e.id == saved)) {
      _cat = saved;
    } else if (_favs.isNotEmpty) {
      _cat = 'fav';
    } else {
      _cat = cats.isNotEmpty ? 'c:${cats.first.id}' : 'all';
    }
    _loadChannels();
    if (mounted) setState(() {});
  }

  void _loadChannels() {
    final src = _source;
    if (src == null) return;
    _channels = switch (_cat) {
      'fav' => _s.repo.favoriteChannels(src.id),
      'recent' => _s.repo.recentChannels(src.id),
      'all' => _s.repo.channels(src.id),
      _ => _s.repo.channels(src.id, categoryId: int.tryParse(_cat.substring(2))),
    };
    _applyFilter();
  }

  void _applyFilter() {
    final words = searchWords(_filter);
    _visible = words.isEmpty ? _channels : _channels.where((c) => matchesWords(c.search, words)).toList();
    final cur = _s.player.current.value;
    _selected = cur == null ? -1 : _visible.indexWhere((c) => c.extId == cur.extId);
    if (_selected < 0 && _visible.isNotEmpty) _selected = 0;
  }

  void _selectCategory(String id) {
    setState(() {
      _cat = id;
      _filter = '';
      _loadChannels();
    });
    if (_source != null) _s.repo.kvSet('live.cat.${_source!.id}', id);
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
  }

  Channel? get _current => (_selected >= 0 && _selected < _visible.length) ? _visible[_selected] : null;

  void _select(int i, {bool preview = true, bool immediate = false}) {
    if (i < 0 || i >= _visible.length) return;
    setState(() => _selected = i);
    _ensureVisible(i);
    if (!preview) return;
    _previewDebounce?.cancel();
    void go() {
      final src = _source;
      final c = _current;
      if (src == null || c == null || !widget.active) return;
      _s.player.play(channelItem(src, c));
      _s.repo.touchChannel(src.id, c.extId);
    }

    if (immediate) {
      go();
    } else {
      _previewDebounce = Timer(const Duration(milliseconds: 350), go);
    }
  }

  void _ensureVisible(int i) {
    if (!_listScroll.hasClients) return;
    final pos = _listScroll.position;
    final top = i * _rowHeight;
    if (top < pos.pixels) {
      _listScroll.jumpTo(top);
    } else if (top + _rowHeight > pos.pixels + pos.viewportDimension) {
      _listScroll.jumpTo((top + _rowHeight - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  Future<void> _fullscreen([int? index]) async {
    final i = index ?? _selected;
    if (i < 0 || i >= _visible.length) return;
    _previewDebounce?.cancel();
    // From the list the stream keeps playing in the preview afterwards; the
    // guide has no preview, so playback stops when leaving the player.
    await Launch.channel(context, _visible[i], _visible, keepAlive: !widget.guide);
    if (mounted) {
      if (!widget.guide) _listFocus.requestFocus();
      setState(() {});
    }
  }

  void _toggleFav(Channel c) {
    _s.toggleFavorite(ContentKind.live, c.extId, c.sourceId);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _select(_selected + 1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _select(_selected - 1);
    } else if (k == LogicalKeyboardKey.pageDown) {
      _select((_selected + 10).clamp(0, _visible.length - 1));
    } else if (k == LogicalKeyboardKey.pageUp) {
      _select((_selected - 10).clamp(0, _visible.length - 1));
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _fullscreen();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  List<Program> _programsFor(Channel c) {
    final now = DateTime.now();
    final list = _s.epg.programs(c, now, now.add(const Duration(hours: 14)));
    if (list.isNotEmpty) return list;
    final key = '${c.sourceId}:${c.extId}';
    final cached = _shortEpg[key];
    var upcoming = const <Program>[];
    if (cached != null) {
      upcoming = cached.programs.where((p) => p.stop.isAfter(now)).toList();
      final age = now.difference(cached.fetchedAt);
      // Empty answers / errors are retried after 2 min; real data after 30 min
      // or as soon as everything fetched is over.
      final stale = cached.programs.isEmpty
          ? age.inMinutes >= 2
          : (upcoming.isEmpty || age.inMinutes >= 30);
      if (!stale) return upcoming;
    }
    final src = _source;
    if (src != null && src.isXtream && c.url == null && _shortEpgLoading.add(key)) {
      final api = XtreamApi.forSource(src);
      api.shortEpg(c.extId, offset: Duration(minutes: src.epgOffsetMinutes)).then((progs) {
        _shortEpg[key] = (fetchedAt: DateTime.now(), programs: progs);
        if (mounted) setState(() {});
      }).catchError((Object _) {
        _shortEpg[key] = (fetchedAt: DateTime.now(), programs: const <Program>[]);
      }).whenComplete(() {
        _shortEpgLoading.remove(key);
        api.close();
      });
    }
    return upcoming;
  }

  @override
  Widget build(BuildContext context) {
    final src = _source;
    if (src == null) return const SizedBox.shrink();
    final catLabel = _entries.where((e) => e.id == _cat).firstOrNull?.label ?? '';
    return Row(children: [
      CategoryPane(entries: _entries, selected: _cat, onSelect: _selectCategory),
      Expanded(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(catLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('${formatCount(_visible.length)} chaînes',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  key: ValueKey('filter-$_cat'),
                  onChanged: (v) => setState(() {
                    _filter = v;
                    _applyFilter();
                  }),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une chaîne',
                    prefixIcon: Icon(Icons.search, size: 18),
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => ShellNavigation.of(context)
                    ?.goTo(widget.guide ? ShellTab.live : ShellTab.guide),
                icon: Icon(widget.guide ? Icons.view_list_rounded : Icons.calendar_view_week_rounded,
                    size: 18),
                label: Text(widget.guide ? 'Liste des chaînes' : 'Guide TV'),
              ),
            ]),
          ),
          Expanded(
            child: _visible.isEmpty
                ? EmptyState(
                    icon: _cat == 'fav' ? Icons.star_outline_rounded : Icons.tv_off_rounded,
                    title: _cat == 'fav' ? 'Aucune chaîne favorite' : 'Aucune chaîne',
                    message: _cat == 'fav' ? "Clique sur l'étoile d'une chaîne pour l'ajouter ici." : null,
                  )
                : widget.guide
                    ? EpgGrid(
                        channels: _visible,
                        epgVersion: _s.library.epg,
                        onPlay: (i) => _fullscreen(i),
                      )
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 5, child: _buildList()),
                        Expanded(flex: 6, child: _buildPreview()),
                      ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildList() {
    return Focus(
      focusNode: _listFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scrollbar(
        controller: _listScroll,
        child: ListView.builder(
          controller: _listScroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
          itemExtent: _rowHeight,
          itemCount: _visible.length,
          itemBuilder: (context, i) => _ChannelTile(
            channel: _visible[i],
            index: i,
            selected: i == _selected,
            favorite: _favs.contains(_visible[i].extId),
            now: _s.epg.now(_visible[i]),
            onTap: () {
              _listFocus.requestFocus();
              _select(i, immediate: true);
            },
            onDoubleTap: () => _fullscreen(i),
            onFavorite: () => _toggleFav(_visible[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final c = _current;
    if (c == null) return const SizedBox.shrink();
    final programs = _programsFor(c);
    final now = DateTime.now();
    final current = programs.where((p) => p.isLiveAt(now)).firstOrNull;
    final upcoming = programs.where((p) => p.start.isAfter(now)).take(10).toList();
    final fav = _favs.contains(c.extId);

    return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 24, 24), children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: Colors.black,
            child: ValueListenableBuilder(
              valueListenable: _s.player.current,
              builder: (context, item, _) {
                final playing = item != null && item.isLive && item.extId == c.extId;
                return GestureDetector(
                  onTap: playing ? null : () => _select(_selected, immediate: true),
                  onDoubleTap: () => _fullscreen(),
                  child: Stack(fit: StackFit.expand, children: [
                    if (playing)
                      Video(
                        controller: _s.player.video,
                        controls: NoVideoControls,
                        fill: Colors.black,
                        subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                      )
                    else
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          ChannelLogo(name: c.name, url: c.logo, size: 72),
                          const SizedBox(height: 14),
                          const Text("Clique pour l'aperçu", style: TextStyle(color: AppColors.muted)),
                        ]),
                      ),
                    if (playing)
                      StreamBuilder<bool>(
                        stream: _s.player.player.stream.buffering,
                        builder: (context, snap) => snap.data == true
                            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                            : const SizedBox.shrink(),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: IconButton.filledTonal(
                        tooltip: 'Plein écran (Entrée)',
                        onPressed: () => _fullscreen(),
                        icon: const Icon(Icons.fullscreen_rounded),
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      Row(children: [
        ChannelLogo(name: c.name, url: c.logo, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Row(children: [
              const LiveBadge(),
              if (c.catchupDays > 0) ...[
                const SizedBox(width: 6),
                Pill('Replay ${c.catchupDays} j', icon: Icons.history),
              ],
            ]),
          ]),
        ),
        IconButton(
          tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          onPressed: () => _toggleFav(c),
          icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: fav ? AppColors.accent : AppColors.muted),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: () => _fullscreen(),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Regarder'),
        ),
      ]),
      const SizedBox(height: 18),
      if (current != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MAINTENANT · ${formatClock(current.start)} – ${formatClock(current.stop)}',
                style: const TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            const SizedBox(height: 6),
            Text(current.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ProgressLine(current.progressAt(now)),
            if (current.description != null) ...[
              const SizedBox(height: 10),
              Text(current.description!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFC1C8D2), height: 1.4)),
            ],
          ]),
        )
      else
        const Text('Aucune information de programme pour cette chaîne.',
            style: TextStyle(color: AppColors.muted)),
      if (upcoming.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('À SUIVRE',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        const SizedBox(height: 6),
        for (final p in upcoming)
          Tooltip(
            message: p.description ?? '',
            waitDuration: const Duration(milliseconds: 700),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 56,
                  child: Text(formatClock(p.start),
                      style: const TextStyle(color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
                ),
                Expanded(child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.index,
    required this.selected,
    required this.favorite,
    required this.now,
    required this.onTap,
    required this.onDoubleTap,
    required this.onFavorite,
  });

  final Channel channel;
  final int index;
  final bool selected;
  final bool favorite;
  final Program? now;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: HoverBuilder(builder: (context, hover) {
        return GestureDetector(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.14)
                  : (hover ? AppColors.surface2 : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.6) : Colors.transparent),
            ),
            child: Row(children: [
              SizedBox(
                width: 38,
                child: Text('${c.number ?? index + 1}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.accent : AppColors.faint,
                    )),
              ),
              ChannelLogo(name: c.name, url: c.logo, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? AppColors.text : const Color(0xFFDDE2EA),
                        )),
                    if (now != null) ...[
                      const SizedBox(height: 2),
                      Text(now!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      ProgressLine(now!.progressAt(DateTime.now()), height: 2),
                    ],
                  ],
                ),
              ),
              if (hover || favorite)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 20, color: favorite ? AppColors.accent : AppColors.muted),
                ),
            ]),
          ),
        );
      }),
    );
  }
}
