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

  static const _rowHeight = 82.0;

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
    return widget.guide ? _buildGuide() : _buildLive();
  }

  String get _catLabel => _entries.where((e) => e.id == _cat).firstOrNull?.label ?? '';

  // --------------------------------------------------------------- live

  Widget _buildLive() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CategoryPane(entries: _entries, selected: _cat, onSelect: _selectCategory),
      const SizedBox(width: 16),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 48, top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: _buildListColumn()),
            const SizedBox(width: 28),
            Expanded(flex: 6, child: _buildPreview()),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildListColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_catLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(30)),
            const SizedBox(height: 2),
            Text('${formatCount(_visible.length)} chaînes · ↑ ↓ pour naviguer, Entrée pour le plein écran',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: Colors.transparent,
            side: const BorderSide(color: AppColors.borderStrong),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          onPressed: () => ShellNavigation.of(context)?.goTo(ShellTab.guide),
          icon: const Icon(Icons.calendar_view_week_rounded, size: 18),
          label: const Text('Guide TV'),
        ),
      ]),
      const SizedBox(height: 14),
      TextField(
        key: ValueKey('filter-$_cat'),
        onChanged: (v) => setState(() {
          _filter = v;
          _applyFilter();
        }),
        decoration: const InputDecoration(
          hintText: 'Rechercher une chaîne',
          prefixIcon: Icon(Icons.search_rounded, size: 18),
          contentPadding: EdgeInsets.symmetric(vertical: 11),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: _visible.isEmpty
            ? EmptyState(
                icon: _cat == 'fav' ? Icons.star_outline_rounded : Icons.tv_off_rounded,
                title: _cat == 'fav' ? 'Aucune chaîne favorite' : 'Aucune chaîne',
                message: _cat == 'fav' ? "Clique sur l'étoile d'une chaîne pour l'ajouter ici." : null,
              )
            : _buildList(),
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
          padding: const EdgeInsets.only(right: 10, bottom: 24),
          itemExtent: _rowHeight,
          itemCount: _visible.length,
          itemBuilder: (context, i) {
            final c = _visible[i];
            return _ChannelTile(
              channel: c,
              index: i,
              selected: i == _selected,
              favorite: _favs.contains(c.extId),
              now: _s.epg.now(c),
              next: _s.epg.next(c),
              onTap: () {
                _listFocus.requestFocus();
                _select(i, immediate: true);
              },
              onDoubleTap: () => _fullscreen(i),
              onFavorite: () => _toggleFav(c),
            );
          },
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
    final upcoming = programs.where((p) => p.start.isAfter(now)).take(8).toList();
    final fav = _favs.contains(c.extId);

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
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
                  if (playing) ...[
                    StreamBuilder<bool>(
                      stream: _s.player.player.stream.buffering,
                      builder: (context, snap) => snap.data == true
                          ? const Center(child: CircularProgressIndicator())
                          : const SizedBox.shrink(),
                    ),
                    const Positioned(top: 14, left: 14, child: LiveBadge()),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: StreamBuilder<int?>(
                        stream: _s.player.player.stream.height,
                        initialData: _s.player.player.state.height,
                        builder: (context, snap) => (snap.data ?? 0) <= 0
                            ? const SizedBox.shrink()
                            : Pill('${snap.data}p',
                                color: AppColors.bg.withValues(alpha: 0.72), textColor: AppColors.textSoft),
                      ),
                    ),
                  ],
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: IconButton(
                      tooltip: 'Plein écran (Entrée)',
                      onPressed: () => _fullscreen(),
                      style: IconButton.styleFrom(backgroundColor: AppColors.bg.withValues(alpha: 0.72)),
                      icon: const Icon(Icons.fullscreen_rounded, color: AppColors.text),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 18),
      Row(children: [
        ChannelLogo(name: c.name, url: c.logo, size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(24)),
            const SizedBox(height: 2),
            Text(
              [
                'Chaîne ${c.number ?? _selected + 1}',
                if (c.catchupDays > 0) 'Replay ${c.catchupDays} jours',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ]),
        ),
        IconButton.outlined(
          tooltip: fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          onPressed: () => _toggleFav(c),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            side: const BorderSide(color: AppColors.borderStrong),
          ),
          icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
              color: fav ? AppColors.accent : AppColors.text),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => _fullscreen(),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Regarder'),
        ),
      ]),
      const SizedBox(height: 18),
      if (current != null)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MAINTENANT · ${formatClock(current.start)} – ${formatClock(current.stop)}',
                style: labelStyle(color: AppColors.accent)),
            const SizedBox(height: 8),
            Text(current.title, style: displayStyle(20)),
            const SizedBox(height: 12),
            ProgressLine(current.progressAt(now)),
            if (current.description != null) ...[
              const SizedBox(height: 12),
              Text(current.description!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSoft, height: 1.5)),
            ],
          ]),
        )
      else
        const Text('Aucune information de programme pour cette chaîne.', style: TextStyle(color: AppColors.muted)),
      if (upcoming.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('À SUIVRE', style: labelStyle()),
        const SizedBox(height: 4),
        for (var i = 0; i < upcoming.length; i++)
          Tooltip(
            message: upcoming[i].description ?? '',
            waitDuration: const Duration(milliseconds: 700),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: i == upcoming.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: Color(0xFF16191F))),
              ),
              child: Row(children: [
                SizedBox(
                  width: 60,
                  child: Text(formatClock(upcoming[i].start),
                      style: const TextStyle(color: AppColors.muted, fontFeatures: tabularFigures)),
                ),
                Expanded(child: Text(upcoming[i].title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
      ],
    ]);
  }

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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(48, 8, 48, 20),
        child: Wrap(
          spacing: 24,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Guide TV', style: displayStyle(30)),
            Wrap(spacing: 8, runSpacing: 8, children: [
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
                      child: Row(children: [
                        Expanded(child: Text(e.label, overflow: TextOverflow.ellipsis)),
                        if (e.count != null)
                          Text('${e.count}', style: const TextStyle(color: AppColors.faint, fontSize: 13)),
                      ]),
                    ),
                ],
                child: const _GuideChip(label: 'Toutes les catégories', selected: false, trailing: true),
              ),
            ]),
            ValueListenableBuilder<int>(
              valueListenable: _grid.day,
              builder: (context, day, _) => Row(mainAxisSize: MainAxisSize.min, children: [
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
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var d = 0; d < days; d++)
                      _DayButton(
                        label: formatDay(DateTime.now().add(Duration(days: d))),
                        selected: d == day,
                        onTap: () => _grid.toDay(d),
                      ),
                  ]),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, fontSize: 14),
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
              ]),
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
                ),
              ),
      ),
    ]);
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
        color: selected ? AppColors.accentTint : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? AppColors.accent : AppColors.borderStrong),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.text : AppColors.textSoft,
            )),
        if (trailing) ...[
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textSoft),
        ],
      ]),
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
          color: selected ? AppColors.surface3 : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.text : AppColors.muted,
                  )),
            ),
          ),
        ),
      );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.index,
    required this.selected,
    required this.favorite,
    required this.now,
    required this.next,
    required this.onTap,
    required this.onDoubleTap,
    required this.onFavorite,
  });

  final Channel channel;
  final int index;
  final bool selected;
  final bool favorite;
  final Program? now;
  final Program? next;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    final t = DateTime.now();
    final left = now?.stop.difference(t);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: HoverBuilder(builder: (context, hover) {
        return GestureDetector(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.selected : (hover ? AppColors.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.accent : Colors.transparent),
            ),
            child: Row(children: [
              SizedBox(
                width: 36,
                child: Text('${c.number ?? index + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.accent : AppColors.faint,
                      fontFeatures: tabularFigures,
                    )),
              ),
              ChannelLogo(name: c.name, url: c.logo, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Flexible(
                        flex: 0,
                        child: Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      if (now != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(now!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                        ),
                      ] else
                        const Spacer(),
                    ]),
                    if (now != null) ...[
                      const SizedBox(height: 6),
                      ProgressLine(now!.progressAt(t), height: 3),
                      if (next != null) ...[
                        const SizedBox(height: 5),
                        Text('Ensuite ${formatClock(next!.start)} ${next!.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.faint)),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (hover || favorite)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                  onPressed: onFavorite,
                  icon: Icon(favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 20, color: favorite ? AppColors.accent : AppColors.muted),
                )
              else if (left != null)
                Text(formatRuntime(left.inSeconds < 60 ? 60 : left.inSeconds),
                    style: const TextStyle(fontSize: 13, color: AppColors.muted, fontFeatures: tabularFigures)),
            ]),
          ),
        );
      }),
    );
  }
}
