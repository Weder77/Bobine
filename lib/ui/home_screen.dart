import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../features/tmdb.dart';
import '../services.dart';
import 'launch.dart';
import 'quick_actions.dart';
import 'shell.dart';
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

String _favKey(ContentKind kind, String extId) => '${kind.db}:$extId';

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
      final favMovies = r.favoriteMovies(id);
      final favSeries = r.favoriteSeries(id);
      d.favorites = [...favMovies, ...favSeries];
      d.favoriteKeys = {
        for (final m in favMovies) _favKey(ContentKind.movie, m.extId),
        for (final sr in favSeries) _favKey(ContentKind.series, sr.extId),
      };
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

  /// Fetches the TMDB details (backdrop, synopsis, genres) of the billboard
  /// and Top 10 once, then redraws.
  final Set<String> _tmdbAsked = {};
  void _prefetchTmdb() {
    if (!_s.tmdb.enabled) return;
    for (final t in [..._heroTitles(), ..._d.top]) {
      if (t is Movie && _tmdbAsked.add('m:${t.sourceId}:${t.extId}')) {
        _s.tmdb.movie(t).then((info) {
          if (info != null && mounted) setState(() {});
        });
      } else if (t is Series && _tmdbAsked.add('s:${t.sourceId}:${t.extId}')) {
        _s.tmdb.series(t).then((info) {
          if (info != null && mounted) setState(() {});
        });
      }
    }
  }

  HeroEntry _movieHero(Movie m, String kicker) {
    final t = _s.tmdb.cachedMovie(m);
    final fav = _d.favoriteKeys.contains(_favKey(ContentKind.movie, m.extId));
    return HeroEntry(
      key: 'm${m.extId}',
      kicker: kicker,
      title: displayTitle(m.name),
      rating: m.rating ?? t?.rating,
      year: '${m.year ?? cleanTitle(m.name).$2 ?? t?.year ?? ''}',
      genre: t?.genres.take(2).join(', '),
      duration: t?.runtimeMinutes == null ? null : formatSpan(Duration(minutes: t!.runtimeMinutes!)),
      quality: qualityOf(m.name),
      synopsis: t?.overview,
      backdrop: t?.backdrop,
      poster: m.poster ?? t?.poster,
      primaryLabel: 'Lecture',
      onPrimary: () => Launch.movie(context, m),
      onInfo: () => Launch.openMovie(context, m),
      favorite: fav,
      onFavorite: () => _s.toggleFavorite(ContentKind.movie, m.extId, m.sourceId),
    );
  }

  HeroEntry _seriesHero(Series sr, String kicker) {
    final t = _s.tmdb.cachedSeries(sr);
    final fav = _d.favoriteKeys.contains(_favKey(ContentKind.series, sr.extId));
    final started = _s.repo.lastEpisodeProgress(sr.sourceId, sr.extId) != null;
    return HeroEntry(
      key: 's${sr.extId}',
      kicker: kicker,
      title: displayTitle(sr.name),
      rating: sr.rating ?? t?.rating,
      year: '${sr.year ?? t?.year ?? ''}',
      genre: (t?.genres.isNotEmpty ?? false) ? t!.genres.take(2).join(', ') : sr.genre,
      quality: qualityOf(sr.name),
      synopsis: (sr.plot != null && sr.plot!.isNotEmpty) ? sr.plot : t?.overview,
      backdrop: t?.backdrop ?? sr.backdrop,
      poster: sr.poster ?? t?.poster,
      primaryLabel: started ? 'Reprendre' : 'Lecture S01E01',
      onPrimary: () => playSeries(context, sr),
      onInfo: () => Launch.openSeries(context, sr),
      favorite: fav,
      onFavorite: () => _s.toggleFavorite(ContentKind.series, sr.extId, sr.sourceId),
    );
  }

  HeroEntry _resumeHero(ProgressEntry p) {
    final episode = p.kind == ContentKind.episode;
    final movie = episode ? null : _s.repo.movieByExt(p.sourceId, p.extId);
    final series = episode && p.seriesExt != null ? _s.repo.seriesByExt(p.sourceId, p.seriesExt!) : null;
    final base = movie != null
        ? _movieHero(movie, 'Film · Reprendre')
        : series != null
        ? _seriesHero(series, 'Série · Tu en es à ${p.subtitle?.split(' · ').first ?? "l'épisode"}')
        : null;
    final left = 'reste ${formatSpan(p.duration - p.position)}';
    return HeroEntry(
      key: 'r${p.extId}',
      kicker: base?.kicker ?? (episode ? 'Série · Reprendre' : 'Film · Reprendre'),
      title: displayTitle(series?.name ?? p.title),
      rating: base?.rating,
      year: base?.year,
      genre: base?.genre,
      duration: base?.duration,
      quality: base?.quality,
      synopsis: base?.synopsis,
      backdrop: base?.backdrop,
      poster: base?.poster ?? p.image,
      progress: p.fraction,
      progressLabel: episode && p.subtitle != null ? '${p.subtitle} · $left' : left,
      primaryLabel: 'Reprendre',
      onPrimary: () => Launch.resume(context, p),
      onInfo: base?.onInfo,
      favorite: base?.favorite ?? false,
      onFavorite: base?.onFavorite,
    );
  }

  List<HeroEntry> _heroEntries() {
    final first = _d.top.firstOrNull;
    String kicker(Object t, String kind) => t == first ? "N° 1 aujourd'hui" : '$kind · Nouveauté';
    return [
      for (final t in _heroTitles())
        if (t is ProgressEntry)
          _resumeHero(t)
        else if (t is Movie)
          _movieHero(t, kicker(t, 'Film'))
        else
          _seriesHero(t as Series, kicker(t, 'Série')),
    ];
  }

  // ------------------------------------------------------------------ rows

  PosterItem _moviePoster(Movie m) {
    final t = _s.tmdb.cachedMovie(m);
    return PosterItem(
      key: 'm${m.extId}',
      title: displayTitle(m.name),
      poster: m.poster ?? t?.poster,
      year: m.year ?? cleanTitle(m.name).$2 ?? t?.year,
      rating: m.rating ?? t?.rating,
      genre: t?.genres.firstOrNull,
      favorite: _d.favoriteKeys.contains(_favKey(ContentKind.movie, m.extId)),
      onPlay: () => Launch.movie(context, m),
      onFavorite: () => _s.toggleFavorite(ContentKind.movie, m.extId, m.sourceId),
      onContextMenu: (at) => showMovieActions(context, m, at),
    );
  }

  PosterItem _seriesPoster(Series sr) {
    final t = _s.tmdb.cachedSeries(sr);
    return PosterItem(
      key: 's${sr.extId}',
      title: displayTitle(sr.name),
      poster: sr.poster ?? t?.poster,
      year: sr.year ?? t?.year,
      rating: sr.rating ?? t?.rating,
      genre: sr.genre?.split(RegExp(r'[,/]')).first.trim() ?? t?.genres.firstOrNull,
      favorite: _d.favoriteKeys.contains(_favKey(ContentKind.series, sr.extId)),
      onPlay: () => playSeries(context, sr),
      onFavorite: () => _s.toggleFavorite(ContentKind.series, sr.extId, sr.sourceId),
      onContextMenu: (at) => showSeriesActions(context, sr, at),
    );
  }

  PosterItem _poster(Object o) => o is Movie ? _moviePoster(o) : _seriesPoster(o as Series);

  TopItem _topItem(Object o) {
    if (o is Movie) {
      return TopItem(
        title: displayTitle(o.name),
        poster: o.poster,
        onPlay: () => Launch.movie(context, o),
        onContextMenu: (at) => showMovieActions(context, o, at),
      );
    }
    final sr = o as Series;
    return TopItem(
      title: displayTitle(sr.name),
      poster: sr.poster,
      onPlay: () => playSeries(context, sr),
      onContextMenu: (at) => showSeriesActions(context, sr, at),
    );
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
    final hero = _heroEntries();
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
          child: TopTenRail(items: [for (final t in _d.top) _topItem(t)]),
        ),
      if (_d.recentMovies.isNotEmpty)
        _Row(
          title: RowTitle(title: 'Films ajoutés récemment', onMore: () => nav?.goTo(ShellTab.movies)),
          child: PosterRail(items: [for (final m in _d.recentMovies) _moviePoster(m)]),
        ),
      if (_d.recentSeries.isNotEmpty)
        _Row(
          title: RowTitle(title: 'Séries ajoutées récemment', onMore: () => nav?.goTo(ShellTab.series)),
          child: PosterRail(items: [for (final sr in _d.recentSeries) _seriesPoster(sr)]),
        ),
      if (_d.favorites.isNotEmpty)
        _Row(
          title: const RowTitle(title: 'Ma liste'),
          child: PosterRail(items: [for (final o in _d.favorites) _poster(o)]),
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
