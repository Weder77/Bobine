import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services.dart';
import 'launch.dart';
import 'shell.dart';
import 'widgets/common.dart';
import 'widgets/net_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  Source? source;
  List<ProgressEntry> continueWatching = const [];
  List<Channel> favChannels = const [];
  List<Channel> recentChannels = const [];
  List<Movie> favMovies = const [];
  List<Movie> recentMovies = const [];
  List<Movie> topMovies = const [];
  List<Series> recentSeries = const [];
  List<Series> favSeries = const [];
  int liveCount = 0, movieCount = 0, seriesCount = 0;

  bool get empty => liveCount == 0 && movieCount == 0 && seriesCount == 0;
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppServices _s;
  _HomeData _d = _HomeData();

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_load);
    _s.settings.addListener(_load);
    _load();
  }

  @override
  void dispose() {
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
      d.favChannels = r.favoriteChannels(id);
      d.recentChannels = r.recentChannels(id, limit: 20);
      d.favMovies = r.favoriteMovies(id);
      d.favSeries = r.favoriteSeries(id);
      d.recentMovies = r.movies(id, sort: CatalogSort.added, limit: 30);
      d.topMovies = r.movies(id, sort: CatalogSort.rating, limit: 30);
      d.recentSeries = r.series(id, sort: CatalogSort.added, limit: 30);
    }
    if (mounted) setState(() => _d = d);
  }

  @override
  Widget build(BuildContext context) {
    final src = _d.source;
    if (src == null) return const SizedBox.shrink();
    if (_d.empty) {
      return ListenableBuilder(
        listenable: _s.imports,
        builder: (context, _) {
          final st = _s.imports.status(src.id);
          if (st != null) {
            return EmptyState(
              icon: Icons.downloading_rounded,
              title: 'Importation en cours…',
              message: '${st.label}\nLes grosses playlists sont traitées en arrière-plan, '
                  "l'application reste utilisable.",
              action: const SizedBox(width: 220, child: LinearProgressIndicator()),
            );
          }
          return EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Aucun contenu pour « ${src.name} »',
            message: src.lastError ?? "L'import n'a rien trouvé. Vérifie la source dans les réglages.",
            action: FilledButton.icon(
              onPressed: () => _s.refresh(src).catchError((Object _) {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          );
        },
      );
    }

    final nav = ShellNavigation.of(context);
    final heroMovie = _d.recentMovies.where((m) => m.poster != null).firstOrNull ??
        _d.topMovies.where((m) => m.poster != null).firstOrNull;
    final favMovieIds = _d.favMovies.map((m) => m.extId).toSet();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        if (_d.continueWatching.isNotEmpty)
          _ResumeHero(entry: _d.continueWatching.first)
        else if (heroMovie != null)
          _MovieHero(movie: heroMovie)
        else
          const SizedBox(height: 32),
        if (_d.continueWatching.isNotEmpty) ...[
          SectionRow(
            title: 'Continuer à regarder',
            height: 230,
            itemCount: _d.continueWatching.length,
            itemBuilder: (context, i) {
              final p = _d.continueWatching[i];
              return LandscapeCard(
                title: p.title,
                subtitle: [
                  if (p.subtitle != null) p.subtitle!,
                  'reste ${formatDuration(p.duration - p.position)}',
                ].join(' · '),
                image: p.image,
                progress: p.fraction,
                onTap: () => Launch.resume(context, p),
                onRemove: () {
                  _s.repo.removeProgress(p.sourceId, p.kind, p.extId);
                  _s.library.userChanged();
                },
              );
            },
          ),
          const SizedBox(height: 28),
        ],
        if (_d.favChannels.isNotEmpty || _d.recentChannels.isNotEmpty) ...[
          _ChannelRow(
            title: _d.favChannels.isNotEmpty ? 'Mes chaînes' : 'Chaînes récentes',
            channels: _d.favChannels.isNotEmpty ? _d.favChannels : _d.recentChannels,
            onMore: () => nav?.goTo(1),
          ),
          const SizedBox(height: 28),
        ],
        if (_d.recentMovies.isNotEmpty) ...[
          _movieRow('Films ajoutés récemment', _d.recentMovies, favMovieIds, () => nav?.goTo(2)),
          const SizedBox(height: 28),
        ],
        if (_d.favMovies.isNotEmpty) ...[
          _movieRow('Mes films', _d.favMovies, favMovieIds, null),
          const SizedBox(height: 28),
        ],
        if (_d.recentSeries.isNotEmpty) ...[
          _seriesRow('Séries récentes', _d.recentSeries, () => nav?.goTo(3)),
          const SizedBox(height: 28),
        ],
        if (_d.favSeries.isNotEmpty) ...[
          _seriesRow('Mes séries', _d.favSeries, null),
          const SizedBox(height: 28),
        ],
        if (_d.topMovies.isNotEmpty && _d.topMovies.first.rating != null)
          _movieRow('Les mieux notés', _d.topMovies, favMovieIds, null),
      ]),
    );
  }

  Widget _more(VoidCallback? onMore) => onMore == null
      ? const SizedBox.shrink()
      : TextButton(onPressed: onMore, child: const Text('Tout voir'));

  Widget _movieRow(String title, List<Movie> list, Set<String> favs, VoidCallback? onMore) {
    return SectionRow(
      title: title,
      height: 300,
      trailing: _more(onMore),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        return PosterCard(
          title: m.name,
          subtitle: m.year?.toString(),
          image: m.poster,
          rating: m.rating,
          favorite: favs.contains(m.extId),
          onTap: () => Launch.openMovie(context, m),
        );
      },
    );
  }

  Widget _seriesRow(String title, List<Series> list, VoidCallback? onMore) {
    return SectionRow(
      title: title,
      height: 300,
      trailing: _more(onMore),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final sr = list[i];
        return PosterCard(
          title: sr.name,
          subtitle: [if (sr.year != null) '${sr.year}', if (sr.genre != null) sr.genre!].join(' · '),
          image: sr.poster,
          rating: sr.rating,
          onTap: () => Launch.openSeries(context, sr),
        );
      },
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.title, required this.channels, this.onMore});
  final String title;
  final List<Channel> channels;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return SectionRow(
      title: title,
      height: 150,
      trailing: onMore == null ? null : TextButton(onPressed: onMore, child: const Text('Toutes les chaînes')),
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final c = channels[i];
        final now = s.epg.now(c);
        return HoverBuilder(
          builder: (context, hover) => GestureDetector(
            onTap: () => Launch.channel(context, c, channels),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 230,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hover ? AppColors.surface3 : AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: hover ? AppColors.accent : AppColors.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ChannelLogo(name: c.name, url: c.logo, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(c.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
                const Spacer(),
                Text(now?.title ?? 'En direct',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(height: 6),
                ProgressLine(now?.progressAt(DateTime.now()) ?? 0),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Large banner with a blurred background.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.image,
    required this.title,
    required this.meta,
    required this.actions,
    this.kicker,
    this.landscape = false,
  });
  final String? image;
  final String title;
  final String meta;
  final String? kicker;
  final List<Widget> actions;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 440,
      child: Stack(fit: StackFit.expand, children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: landscape ? 0 : 28, sigmaY: landscape ? 0 : 28),
          child: Opacity(
            opacity: landscape ? 0.85 : 0.55,
            child: NetImage(image, decodeWidth: landscape ? 1280 : 300, alignment: Alignment.topCenter),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.bg, Color(0xAA0A0C11), Colors.transparent],
              stops: [0, 0.45, 1],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, AppColors.bg],
              begin: Alignment(0, 0.2),
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 36),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                if (kicker != null)
                  Text(kicker!.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.accent, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontSize: 12)),
                const SizedBox(height: 8),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.05)),
                const SizedBox(height: 10),
                Text(meta, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
                const SizedBox(height: 22),
                Wrap(spacing: 12, runSpacing: 12, children: actions),
              ]),
            ),
            if (!landscape && image != null)
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: NetImage(image, width: 220, height: 330, decodeWidth: 220),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ResumeHero extends StatelessWidget {
  const _ResumeHero({required this.entry});
  final ProgressEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = entry;
    return _Hero(
      image: p.image,
      kicker: 'Reprendre',
      title: p.title,
      // Progress entries store a backdrop / episode still: show it wide.
      landscape: true,
      meta: [
        if (p.subtitle != null) p.subtitle!,
        '${formatDuration(p.position)} / ${formatDuration(p.duration)}',
      ].join('  ·  '),
      actions: [
        FilledButton.icon(
          onPressed: () => Launch.resume(context, p),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('Reprendre à ${formatDuration(p.position)}'),
        ),
        SizedBox(width: 200, child: Padding(
          padding: const EdgeInsets.only(top: 22),
          child: ProgressLine(p.fraction, height: 4),
        )),
      ],
    );
  }
}

class _MovieHero extends StatelessWidget {
  const _MovieHero({required this.movie});
  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final m = movie;
    return _Hero(
      image: m.poster,
      kicker: 'Nouveauté',
      title: m.name,
      meta: [
        if (m.year != null) '${m.year}',
        if (m.rating != null) '★ ${m.rating!.toStringAsFixed(1)}',
        if (m.added != null) 'ajouté ${formatRelative(m.added)}',
      ].join('  ·  '),
      actions: [
        FilledButton.icon(
          onPressed: () => Launch.movie(context, m),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Lecture'),
        ),
        OutlinedButton.icon(
          onPressed: () => Launch.openMovie(context, m),
          icon: const Icon(Icons.info_outline),
          label: const Text("Plus d'infos"),
        ),
      ],
    );
  }
}
