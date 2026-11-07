import 'dart:async';
import 'dart:ui' show ImageFilter;

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
import 'program_actions.dart';
import 'settings_family.dart';
import 'shell.dart';
import 'widgets/common.dart';
import 'widgets/live_card.dart';
import 'widgets/net_image.dart';

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
    // The mini-player keeps playing while the user browses.
    if (_s.pip.active) return;
    if (_s.player.current.value?.isLive ?? false) _s.player.stop();
  }

  void _onLibrary() {
    if (_s.library.content != _contentVersion || _source?.id != _s.settings.activeSourceId) {
      _reload();
    } else {
      // Favourites / EPG changed.
      setState(() {
        if (_source != null) _favs = _s.repo.favoriteKeys(_source!.id, ContentKind.live);
        _entries = withFavoriteCount(_entries, _favs.length);
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
      for (final c in cats) CategoryEntry(id: 'c:${c.id}', label: c.name, count: c.count, locked: c.locked),
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
    final top = _gridTop + (i ~/ _columns) * _rowExtent;
    final bottom = top + _rowExtent;
    if (top < pos.pixels + 20) {
      _listScroll.jumpTo((top - 20).clamp(0, pos.maxScrollExtent));
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _listScroll.jumpTo((bottom - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
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
    // A card, chip or button inside has the focus: normal arrow navigation.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // At the edges the arrows leave the grid (menu above, categories left).
    if ((k == LogicalKeyboardKey.arrowUp && _selected < _columns) ||
        (k == LogicalKeyboardKey.arrowLeft && _selected % _columns == 0)) {
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _select(_selected + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _select(_selected - 1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _select((_selected + _columns).clamp(0, _visible.length - 1));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _select((_selected - _columns).clamp(0, _visible.length - 1));
    } else if (k == LogicalKeyboardKey.pageDown) {
      _select((_selected + _columns * 3).clamp(0, _visible.length - 1));
    } else if (k == LogicalKeyboardKey.pageUp) {
      _select((_selected - _columns * 3).clamp(0, _visible.length - 1));
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
      final stale = cached.programs.isEmpty ? age.inMinutes >= 2 : (upcoming.isEmpty || age.inMinutes >= 30);
      if (!stale) return upcoming;
    }
    final src = _source;
    if (src != null && src.isXtream && c.url == null && _shortEpgLoading.add(key)) {
      final api = XtreamApi.forSource(src);
      api
          .shortEpg(c.extId, offset: Duration(minutes: src.epgOffsetMinutes))
          .then((progs) {
            _shortEpg[key] = (fetchedAt: DateTime.now(), programs: progs);
            if (mounted) setState(() {});
          })
          .catchError((Object _) {
            _shortEpg[key] = (fetchedAt: DateTime.now(), programs: const <Program>[]);
          })
          .whenComplete(() {
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
    return widget.guide ? _buildGuide() : _buildLive();
  }

  String get _catLabel => _entries.where((e) => e.id == _cat).firstOrNull?.label ?? '';

  // --------------------------------------------------------------- live

  /// Grid metrics of the last layout (keyboard navigation, scrolling).
  int _columns = 4;
  double _rowExtent = 240;
  double _gridTop = 0;

  /// Categories shown as chips; all of them are in the menu.
  List<CategoryEntry> get _chipEntries {
    final chips = <CategoryEntry>[
      ..._entries.where((e) => !e.id.startsWith('c:')),
      ..._entries.where((e) => e.id.startsWith('c:')).take(6),
    ];
    if (!chips.any((e) => e.id == _cat)) {
      final current = _entries.where((e) => e.id == _cat).firstOrNull;
      if (current != null) chips.add(current);
    }
    return chips;
  }

  Widget _buildLive() {
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.5).clamp(380.0, 520.0);
    return Focus(
      focusNode: _listFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, box) {
          const side = 48.0, gap = 14.0, minCard = 270.0;
          final width = box.maxWidth - side * 2;
          _columns = ((width + gap) / (minCard + gap)).floor().clamp(1, 8);
          final cardW = (width - gap * (_columns - 1)) / _columns;
          _rowExtent = cardW * 9 / 16 + 4 + 56 + 22;
          _gridTop = heroHeight + 8 + 92;
          return Scrollbar(
            controller: _listScroll,
            child: CustomScrollView(
              controller: _listScroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(side, 8, side, 0),
                    child: SizedBox(height: heroHeight, child: _buildHero()),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 92, child: _buildChips())),
                if (_visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: _cat == 'fav' ? Icons.star_outline_rounded : Icons.tv_off_rounded,
                        title: _cat == 'fav' ? 'Aucune chaîne favorite' : 'Aucune chaîne',
                        message: _cat == 'fav' ? "Ajoute une chaîne avec l'étoile pour la retrouver ici." : null,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(side, 0, side, 48),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columns,
                        mainAxisExtent: _rowExtent - 22,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: 22,
                      ),
                      delegate: SliverChildBuilderDelegate(childCount: _visible.length, (context, i) {
                        final c = _visible[i];
                        return LiveCard(
                          channel: c,
                          width: cardW,
                          selected: i == _selected,
                          favorite: _favs.contains(c.extId),
                          onTap: () {
                            _listFocus.requestFocus();
                            _select(i, immediate: true);
                          },
                          onDoubleTap: () => _fullscreen(i),
                          onActivate: () => _fullscreen(i),
                          onFocus: () => _select(i),
                          onContextMenu: (pos) => _channelMenu(c, pos),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 26, 48, 22),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in _chipEntries) ...[
                    _GuideChip(
                      label: e.count == null ? e.label : '${e.label} · ${formatCount(e.count!)}',
                      selected: e.id == _cat,
                      onTap: () => _selectCategory(e.id),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _categoryMenu(),
                  const SizedBox(width: 10),
                  _GuideChip(
                    label: 'Ranger…',
                    selected: false,
                    onTap: () => showCategoryManager(context, ContentKind.live),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 260,
            child: TextField(
              key: ValueKey('filter-$_cat'),
              onChanged: (v) => setState(() {
                _filter = v;
                _applyFilter();
              }),
              decoration: InputDecoration(
                hintText: 'Rechercher une chaîne',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: AppColors.borderStrong),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: AppColors.text, width: 1.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryMenu() => PopupMenuButton<String>(
    tooltip: 'Toutes les catégories',
    onSelected: _selectCategory,
    constraints: const BoxConstraints(maxHeight: 480, minWidth: 260),
    itemBuilder: (_) => [
      for (final e in _entries)
        PopupMenuItem(
          value: e.id,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  e.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: e.id == _cat ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              if (e.count != null) Text('${e.count}', style: const TextStyle(color: AppColors.faint, fontSize: 13)),
            ],
          ),
        ),
    ],
    child: const _GuideChip(label: 'Toutes les catégories', selected: false, trailing: true),
  );

  /// The selected channel, large: live preview behind, programme in poster
  /// capitals, actions, and what comes next.
  Widget _buildHero() {
    final c = _current;
    if (c == null) {
      return Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.center,
        child: Text(_catLabel, style: posterStyle(64)),
      );
    }
    final programs = _programsFor(c);
    final now = DateTime.now();
    final current = programs.where((p) => p.isLiveAt(now)).firstOrNull;
    final upcoming = programs.where((p) => p.start.isAfter(now)).take(3).toList();
    final fav = _favs.contains(c.extId);
    final titleSize = (MediaQuery.sizeOf(context).width * 0.058).clamp(52.0, 92.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ValueListenableBuilder(
        valueListenable: _s.player.current,
        builder: (context, item, _) {
          final playing = item != null && item.isLive && item.extId == c.extId;
          return GestureDetector(
            onDoubleTap: () => _fullscreen(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.surface),
                if (playing)
                  Video(
                    controller: _s.player.video,
                    controls: NoVideoControls,
                    fit: BoxFit.cover,
                    fill: Colors.black,
                    subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                  )
                else ...[
                  if (c.logo != null)
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                      child: Opacity(opacity: 0.5, child: NetImage(c.logo, decodeWidth: 160)),
                    ),
                  Align(
                    alignment: const Alignment(0.55, -0.1),
                    child: ChannelLogo(name: c.name, url: c.logo, size: 150),
                  ),
                ],
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xE60A0A0C), Color(0x800A0A0C), Color(0x000A0A0C)],
                      stops: [0, 0.38, 0.7],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment(0, 0),
                      colors: [Color(0xCC0A0A0C), Color(0x000A0A0C)],
                    ),
                  ),
                ),
                if (playing)
                  StreamBuilder<bool>(
                    stream: _s.player.player.stream.buffering,
                    builder: (context, snap) => snap.data == true
                        ? const Center(child: CircularProgressIndicator(color: AppColors.text))
                        : const SizedBox.shrink(),
                  ),
                Positioned(
                  left: 44,
                  right: 360,
                  bottom: 40,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ChannelLogo(name: c.name, url: c.logo, size: 56),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${c.number ?? _selected + 1} · ${c.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const LiveBadge(),
                                    if (c.catchupDays > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        'Replay ${c.catchupDays} jours',
                                        style: const TextStyle(fontSize: 13, color: AppColors.textSoft),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        current?.title ?? c.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: posterStyle(
                          titleSize,
                          shadows: const [Shadow(color: Color(0x80000000), blurRadius: 24)],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (current != null)
                        Row(
                          children: [
                            Text(formatClock(current.start), style: _timeStyle),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 240,
                              child: ProgressLine(
                                current.progressAt(now),
                                color: AppColors.live,
                                track: const Color(0x40FFFFFF),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(formatClock(current.stop), style: _timeStyle),
                            const SizedBox(width: 10),
                            Text(
                              '· encore ${formatRuntime(current.stop.difference(now).inSeconds)}',
                              style: const TextStyle(fontSize: 14, color: AppColors.muted),
                            ),
                          ],
                        )
                      else
                        const Text('Pas de programme disponible', style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _fullscreen(),
                            icon: const Icon(Icons.play_arrow_rounded, size: 26),
                            label: const Text('Plein écran'),
                          ),
                          if (!playing)
                            OutlinedButton.icon(
                              onPressed: () => _select(_selected, immediate: true),
                              icon: const Icon(Icons.visibility_outlined, size: 21),
                              label: const Text('Aperçu'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => ShellNavigation.of(context)?.goTo(ShellTab.guide),
                            icon: const Icon(Icons.calendar_view_week_rounded, size: 21),
                            label: const Text('Guide TV'),
                          ),
                          if (current != null && canReplay(c, current))
                            OutlinedButton.icon(
                              onPressed: () => Launch.replay(context, c, current),
                              icon: const Icon(Icons.replay_rounded, size: 21),
                              label: const Text('Depuis le début'),
                            ),
                          _recordButton(c, current),
                          RoundAction(
                            icon: fav ? Icons.star_rounded : Icons.star_outline_rounded,
                            tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                            color: fav ? AppColors.accent : null,
                            onPressed: () => _toggleFav(c),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (upcoming.isNotEmpty)
                  Positioned(
                    right: 22,
                    bottom: 22,
                    width: 300,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xB80A0A0C),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('À SUIVRE', style: labelStyle()),
                          const SizedBox(height: 8),
                          for (final p in upcoming)
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => showProgramActions(context, c, p, channels: _visible),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    SizedBox(width: 52, child: Text(formatClock(p.start), style: _timeStyle)),
                                    if (_s.repo.hasReminder(c.sourceId, c.extId, p.start))
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Icon(
                                          Icons.notifications_active_rounded,
                                          size: 14,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        p.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Right-click menu of a channel card.
  Future<void> _channelMenu(Channel c, Offset at) async {
    final fav = _favs.contains(c.extId);
    final size = MediaQuery.sizeOf(context);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      items: [
        const PopupMenuItem(value: 'play', child: Text('Regarder en plein écran')),
        PopupMenuItem(value: 'fav', child: Text(fav ? 'Retirer des favoris' : 'Ajouter aux favoris')),
        const PopupMenuItem(value: 'record', child: Text('Enregistrer maintenant')),
        const PopupMenuItem(value: 'hide', child: Text('Masquer la chaîne')),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'play':
        _fullscreen(_visible.indexOf(c));
      case 'fav':
        _toggleFav(c);
      case 'record':
        _s.recordings.recordNow(c, current: _s.epg.now(c));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement de « ${c.name} » démarré')));
      case 'hide':
        _s.repo.setChannelHidden(c.sourceId, c.extId, true);
        _s.visibilityChanged();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('« ${c.name} » est masquée. Réglages → Catégories et chaînes pour la retrouver.'),
            action: SnackBarAction(
              label: 'Annuler',
              onPressed: () {
                _s.repo.setChannelHidden(c.sourceId, c.extId, false);
                _s.visibilityChanged();
              },
            ),
          ),
        );
    }
  }

  /// Records the current programme (or stops the recording of this channel).
  Widget _recordButton(Channel c, Program? current) {
    final active = _s.repo
        .recordings()
        .where((r) => r.status == RecordingStatus.recording && r.sourceId == c.sourceId && r.channelExt == c.extId)
        .firstOrNull;
    return RoundAction(
      icon: active != null ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
      tooltip: active != null
          ? "Arrêter l'enregistrement"
          : (current != null ? 'Enregistrer cette émission' : 'Enregistrer'),
      color: AppColors.live,
      onPressed: () async {
        if (active != null) {
          await _s.recordings.stop(active.id);
        } else {
          _s.recordings.recordNow(c, current: current);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Enregistrement de « ${current?.title ?? c.name} » démarré')));
          }
        }
        if (mounted) setState(() {});
      },
    );
  }

  static const _timeStyle = TextStyle(fontSize: 14, color: AppColors.muted, fontFeatures: tabularFigures);

  // -------------------------------------------------------------- guide

  final _grid = EpgGridController();

  Widget _buildGuide() {
    // A few categories as chips, the full list in a menu.
    final chips = <CategoryEntry>[
      ..._entries.where((e) => e.id == 'fav' && (e.count ?? 0) > 0),
      ..._entries.where((e) => e.id.startsWith('c:')).take(6),
    ];
    if (!chips.any((e) => e.id == _cat)) {
      final current = _entries.where((e) => e.id == _cat).firstOrNull;
      if (current != null) chips.add(current);
    }
    final days = _s.settings.epgDays.clamp(1, 7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 8, 48, 20),
          child: Wrap(
            spacing: 24,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Guide TV', style: displayStyle(30)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in chips)
                    _GuideChip(label: e.label, selected: e.id == _cat, onTap: () => _selectCategory(e.id)),
                  PopupMenuButton<String>(
                    tooltip: 'Toutes les catégories',
                    onSelected: _selectCategory,
                    constraints: const BoxConstraints(maxHeight: 480, minWidth: 260),
                    itemBuilder: (_) => [
                      for (final e in _entries)
                        PopupMenuItem(
                          value: e.id,
                          child: Row(
                            children: [
                              Expanded(child: Text(e.label, overflow: TextOverflow.ellipsis)),
                              if (e.count != null)
                                Text('${e.count}', style: const TextStyle(color: AppColors.faint, fontSize: 13)),
                            ],
                          ),
                        ),
                    ],
                    child: const _GuideChip(label: 'Toutes les catégories', selected: false, trailing: true),
                  ),
                ],
              ),
              ValueListenableBuilder<int>(
                valueListenable: _grid.day,
                builder: (context, day, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.outlined(
                      tooltip: '2 heures plus tôt',
                      onPressed: () => _grid.scrollBy(-120),
                      style: IconButton.styleFrom(side: const BorderSide(color: AppColors.borderStrong)),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var d = 0; d < days; d++)
                            _DayButton(
                              label: formatDay(DateTime.now().add(Duration(days: d))),
                              selected: d == day,
                              onTap: () => _grid.toDay(d),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        textStyle: const TextStyle(
                          fontFamily: AppFonts.body,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: _grid.toNow,
                      child: const Text('Maintenant'),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: '2 heures plus tard',
                      onPressed: () => _grid.scrollBy(120),
                      style: IconButton.styleFrom(side: const BorderSide(color: AppColors.borderStrong)),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _visible.isEmpty
              ? const EmptyState(icon: Icons.tv_off_rounded, title: 'Aucune chaîne dans cette catégorie')
              : Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 32),
                  child: EpgGrid(
                    controller: _grid,
                    channels: _visible,
                    epgVersion: _s.library.epg,
                    onPlay: (i) => _fullscreen(i),
                    onProgram: (i, p) => showProgramActions(context, _visible[i], p, channels: _visible),
                  ),
                ),
        ),
      ],
    );
  }
}

class _GuideChip extends StatelessWidget {
  const _GuideChip({required this.label, required this.selected, this.onTap, this.trailing = false});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: selected ? AppColors.action : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? AppColors.action : AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? AppColors.onAction : AppColors.textSoft,
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSoft),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: chip),
    );
  }
}

class _DayButton extends StatelessWidget {
  const _DayButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AppColors.action : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? AppColors.onAction : AppColors.muted,
            ),
          ),
        ),
      ),
    ),
  );
}
