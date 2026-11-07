import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services.dart';
import 'launch.dart';
import 'quick_actions.dart';
import 'shell.dart';
import 'titles.dart';
import 'widgets/billboard.dart';
import 'widgets/common.dart';
import 'widgets/rows.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  Source? source;
  List<ProgressEntry> continueWatching = const [];
  List<Channel> liveChannels = const [];
  bool liveAreFavorites = false;
  List<Object> top = const [];
  List<Movie> recentMovies = const [];
  List<Series> recentSeries = const [];
  List<Object> favorites = const [];
  Set<String> favoriteKeys = const {};
  int liveCount = 0, movieCount = 0, seriesCount = 0;

  bool get empty => liveCount == 0 && movieCount == 0 && seriesCount == 0;
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppServices _s;
  _HomeData _d = _HomeData();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_load);
    _s.settings.addListener(_load);
    _load();
    // Keeps the "now" programmes and their progress current.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _s.library.removeListener(_load);
    _s.settings.removeListener(_load);
    super.dispose();
  }

  void _load() {
    final d = _HomeData();
    final src = _s.activeSource;
    d.source = src;
    if (src != null) {
      final r = _s.repo;
      final id = src.id;
      d.liveCount = r.count(id, ContentKind.live);
      d.movieCount = r.count(id, ContentKind.movie);
      d.seriesCount = r.count(id, ContentKind.series);
      d.continueWatching = r.continueWatching(id);
      final favs = r.favoriteChannels(id);
      d.liveAreFavorites = favs.isNotEmpty;
      final seen = <String>{};
      d.liveChannels = [
        for (final c in [...favs, ...r.recentChannels(id, limit: 20), ...r.channels(id, limit: 80)])
          if (seen.add(c.extId)) c,
      ];
      d.top = r.trending(id);
      d.recentMovies = r.movies(id, sort: CatalogSort.added, limit: 30);
      d.recentSeries = r.series(id, sort: CatalogSort.added, limit: 30);
      d.favorites = [...r.favoriteMovies(id), ...r.favoriteSeries(id)];
      d.favoriteKeys = TitleCards.loadFavorites(_s, id);
    }
    if (mounted) setState(() => _d = d);
    _prefetchTmdb();
  }

  // ------------------------------------------------------------- billboard

  /// Titles of the billboard: what you were watching, then the top of the
  /// latest additions (with an image), four in all.
  List<Object> _heroTitles() {
    final list = <Object>[];
    final resume = _d.continueWatching.firstOrNull;
    if (resume != null) list.add(resume);
    for (final t in _d.top) {
      if (list.length >= 4) break;
      final poster = t is Movie ? t.poster : (t as Series).poster;
      if (poster != null) list.add(t);
    }
    for (final m in _d.recentMovies) {
      if (list.length >= 4) break;
      if (m.poster != null && !list.contains(m)) list.add(m);
    }
    return list;
  }

  final Set<String> _tmdbAsked = {};
  void _prefetchTmdb() => TitleCards.prefetch(_s, [..._heroTitles(), ..._d.top], _tmdbAsked, () {
    if (mounted) setState(() {});
  });

  List<HeroEntry> _heroEntries(TitleCards cards) {
    final first = _d.top.firstOrNull;
    String kicker(Object t, String kind) => t == first ? "N° 1 aujourd'hui" : '$kind · Nouveauté';
    return [
      for (final t in _heroTitles())
        if (t is ProgressEntry)
          cards.resumeHero(t)
        else if (t is Movie)
          cards.movieHero(t, kicker(t, 'Film'))
        else
          cards.seriesHero(t as Series, kicker(t, 'Série')),
    ];
  }

  List<LiveNowItem> _liveNow() {
    final withGuide = <LiveNowItem>[];
    final without = <LiveNowItem>[];
    for (final c in _d.liveChannels) {
      final p = _s.epg.now(c);
      final item = LiveNowItem(
        channel: c,
        program: p,
        onTap: () => Launch.channel(context, c, _d.liveChannels),
        onContextMenu: (at) => showChannelActions(context, c, _d.liveChannels, at),
      );
      (p != null ? withGuide : without).add(item);
      if (withGuide.length >= 8) break;
    }
    return [...withGuide, ...without].take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final src = _d.source;
    if (src == null) return const SizedBox.shrink();
    if (_d.empty) return _EmptyHome(source: src);

    final nav = ShellNavigation.of(context);
    final size = MediaQuery.sizeOf(context);
    final cards = TitleCards(context, _s, _d.favoriteKeys);
    final hero = _heroEntries(cards);
    final live = _liveNow();
    final heroH = Billboard.heightFor(size, 640, 820, 0.88);

    final rows = <Widget>[
      if (_d.continueWatching.isNotEmpty)
        _Row(
          title: const RowTitle(title: 'Reprendre'),
          child: ResumeRail(
            entries: _d.continueWatching,
            onPlay: (p) => Launch.resume(context, p),
            onContextMenu: (p, at) => showProgressActions(context, p, at),
            onRemove: (p) {
              _s.repo.removeProgress(p.sourceId, p.kind, p.extId);
              _s.library.userChanged();
            },
          ),
        ),
      if (_d.top.isNotEmpty)
        _Row(
          title: const RowTitle(title: "Top 10 aujourd'hui", sub: 'films et séries sur ta source', big: true),
          child: TopTenRail(items: [for (final t in _d.top) cards.top(t)]),
        ),
      if (_d.recentMovies.isNotEmpty)
        _Row(
          title: RowTitle(title: 'Films ajoutés récemment', onMore: () => nav?.goTo(ShellTab.movies)),
          child: PosterRail(items: [for (final m in _d.recentMovies) cards.moviePoster(m)]),
        ),
      if (_d.recentSeries.isNotEmpty)
        _Row(
          title: RowTitle(title: 'Séries ajoutées récemment', onMore: () => nav?.goTo(ShellTab.series)),
          child: PosterRail(items: [for (final sr in _d.recentSeries) cards.seriesPoster(sr)]),
        ),
      if (_d.favorites.isNotEmpty)
        _Row(
          title: const RowTitle(title: 'Ma liste'),
          child: PosterRail(items: [for (final o in _d.favorites) cards.poster(o)]),
        ),
    ];

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          if (hero.isEmpty)
            const SizedBox(height: kTopBarHeight + 24)
          else
            // The live cards (or the first row) rise over the bottom of the
            // billboard, as in the design.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: heroH,
                  child: Billboard(entries: hero, autoplay: _s.settings.heroAutoplay),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (live.isNotEmpty) ...[
                      SizedBox(height: heroH - 236),
                      LiveNowStrip(
                        items: live,
                        title: _d.liveAreFavorites ? 'En direct sur tes chaînes' : 'En direct maintenant',
                        onGuide: () => nav?.goTo(ShellTab.guide),
                      ),
                      const SizedBox(height: 48),
                    ] else
                      SizedBox(height: heroH - 120),
                  ],
                ),
              ],
            ),
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 30), rows[i]],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.child});
  final Widget title;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, child]);
}

/// No content yet: import in progress, or nothing found.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.source});
  final Source source;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final src = source;
    return ListenableBuilder(
      listenable: s.imports,
      builder: (context, _) {
        final st = s.imports.status(src.id);
        if (st != null) {
          return EmptyState(
            icon: Icons.downloading_rounded,
            title: 'Importation en cours…',
            message:
                '${st.label}\nLes grosses playlists sont traitées en arrière-plan, '
                "l'application reste utilisable.",
            action: const SizedBox(width: 220, child: LinearProgressIndicator()),
          );
        }
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Aucun contenu pour « ${src.name} »',
          message: src.lastError ?? "L'import n'a rien trouvé. Vérifie la source dans les réglages.",
          action: FilledButton.icon(
            onPressed: () => s.refresh(src).catchError((Object _) {}),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        );
      },
    );
  }
}
