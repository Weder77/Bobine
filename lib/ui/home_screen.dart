import 'dart:async';
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
import 'widgets/live_card.dart';
import 'widgets/net_image.dart';

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
  List<Movie> favMovies = const [];
  List<Movie> recentMovies = const [];
  List<Movie> topMovies = const [];
  List<Series> recentSeries = const [];
  List<Series> favSeries = const [];
  int liveCount = 0, liveCategories = 0, movieCount = 0, seriesCount = 0;

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
      d.liveCategories = r.categories(id, ContentKind.live).length;
      d.movieCount = r.count(id, ContentKind.movie);
      d.seriesCount = r.count(id, ContentKind.series);
      d.continueWatching = r.continueWatching(id);
      final favs = r.favoriteChannels(id);
      final recent = r.recentChannels(id, limit: 20);
      d.liveAreFavorites = favs.isNotEmpty;
      d.liveChannels = favs.isNotEmpty ? favs : (recent.isNotEmpty ? recent : r.channels(id).take(12).toList());
      d.favMovies = r.favoriteMovies(id);
      d.favSeries = r.favoriteSeries(id);
      d.recentMovies = r.movies(id, sort: CatalogSort.added, limit: 30);
      d.topMovies = r.movies(id, sort: CatalogSort.rating, limit: 30);
      d.recentSeries = r.series(id, sort: CatalogSort.added, limit: 30);
    }
    if (mounted) setState(() => _d = d);
    _prefetchTmdb();
  }

  List<Movie> _heroMovies() =>
      _d.recentMovies.where((m) => m.poster != null).take(4 - _d.continueWatching.take(2).length).toList();

  /// Fetches TMDB backdrops of the banner films once, then redraws.
  final Set<String> _tmdbAsked = {};
  void _prefetchTmdb() {
    if (!_s.tmdb.enabled) return;
    for (final m in _heroMovies()) {
      if (!_tmdbAsked.add('${m.sourceId}:${m.extId}')) continue;
      _s.tmdb.movie(m).then((info) {
        if (info != null && mounted) setState(() {});
      });
    }
  }

  List<_HeroItem> _heroItems() {
    final items = <_HeroItem>[];
    for (final p in _d.continueWatching.take(2)) {
      final isEpisode = p.kind == ContentKind.episode;
      items.add(
        _HeroItem(
          kicker: isEpisode ? 'SÉRIE · REPRENDRE' : 'FILM · REPRENDRE',
          title: p.title,
          meta: [if (p.subtitle != null && p.subtitle!.isNotEmpty) p.subtitle!],
          image: p.image,
          landscape: true,
          progress: p.fraction,
          progressLabel: 'reste ${formatRuntime((p.duration - p.position).inSeconds)}',
          primaryLabel: 'Reprendre',
          onPrimary: (c) => Launch.resume(c, p),
        ),
      );
    }
    for (final m in _heroMovies()) {
      final t = _s.tmdb.cachedMovie(m);
      items.add(
        _HeroItem(
          kicker: 'FILM · NOUVEAU',
          title: m.name,
          meta: ['Film', if ((m.year ?? t?.year) != null) '${m.year ?? t?.year}', ...?t?.genres.take(2)],
          rating: m.rating ?? t?.rating,
          image: t?.backdrop ?? m.poster,
          landscape: t?.backdrop != null,
          overview: t?.overview,
          primaryLabel: 'Lecture',
          onPrimary: (c) => Launch.movie(c, m),
          secondaryLabel: "Plus d'infos",
          onSecondary: (c) => Launch.openMovie(c, m),
        ),
      );
    }
    return items;
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
              onPressed: () => _s.refresh(src).catchError((Object _) {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          );
        },
      );
    }

    final nav = ShellNavigation.of(context);
    final favMovieIds = _d.favMovies.map((m) => m.extId).toSet();
    final hero = _heroItems();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: EdgeInsets.only(top: hero.isEmpty ? 24 : 0, bottom: 64),
        children: [
          if (hero.isNotEmpty) _HeroCarousel(items: hero),
          const SizedBox(height: 40),
          if (_d.continueWatching.isNotEmpty) ...[
            SectionRow(
              title: 'Reprendre',
              height: 216,
              itemWidth: 300,
              gap: 12,
              itemCount: _d.continueWatching.length,
              itemBuilder: (context, i) {
                final p = _d.continueWatching[i];
                return LandscapeCard(
                  title: p.title,
                  subtitle: p.subtitle ?? (p.kind == ContentKind.episode ? 'Épisode' : 'Film'),
                  trailing: 'reste ${formatRuntime((p.duration - p.position).inSeconds)}',
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
            const SizedBox(height: 36),
          ],
          if (_d.liveChannels.isNotEmpty) ...[
            _LiveRow(
              title: _d.liveAreFavorites ? 'En direct sur tes chaînes' : 'En direct maintenant',
              channels: _d.liveChannels,
              onGuide: () => nav?.goTo(ShellTab.guide),
            ),
            const SizedBox(height: 36),
          ],
          if (_d.recentMovies.isNotEmpty) ...[
            _movieRow('Films ajoutés récemment', _d.recentMovies, favMovieIds, () => nav?.goTo(ShellTab.movies)),
            const SizedBox(height: 36),
          ],
          if (_d.favMovies.isNotEmpty) ...[
            _movieRow('Films favoris', _d.favMovies, favMovieIds, null),
            const SizedBox(height: 36),
          ],
          if (_d.recentSeries.isNotEmpty) ...[
            _seriesRow('Séries récentes', _d.recentSeries, () => nav?.goTo(ShellTab.series)),
            const SizedBox(height: 36),
          ],
          if (_d.favSeries.isNotEmpty) ...[
            _seriesRow('Séries favorites', _d.favSeries, null),
            const SizedBox(height: 36),
          ],
          if (_d.topMovies.isNotEmpty && _d.topMovies.first.rating != null)
            _movieRow('Les mieux notés', _d.topMovies, favMovieIds, null),
        ],
      ),
    );
  }

  Widget? _more(VoidCallback? onMore) =>
      onMore == null ? null : TextButton(onPressed: onMore, child: const Text('Tout voir'));

  Widget _movieRow(String title, List<Movie> list, Set<String> favs, VoidCallback? onMore) {
    return SectionRow(
      title: title,
      height: 318,
      gap: 12,
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
      height: 318,
      gap: 12,
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

// ---------------------------------------------------------------- banner

class _HeroItem {
  const _HeroItem({
    required this.kicker,
    required this.title,
    required this.meta,
    required this.image,
    required this.landscape,
    required this.primaryLabel,
    required this.onPrimary,
    this.rating,
    this.progress,
    this.progressLabel,
    this.secondaryLabel,
    this.onSecondary,
    this.overview,
  });
  final String kicker;
  final String title;
  final List<String> meta;
  final double? rating;
  final String? image;
  final bool landscape;
  final double? progress;
  final String? progressLabel;
  final String primaryLabel;
  final void Function(BuildContext) onPrimary;
  final String? secondaryLabel;
  final void Function(BuildContext)? onSecondary;

  /// Synopsis line (from TMDB).
  final String? overview;
}

/// Full-width banner under the glass bar (auto-advance, dots to pick).
class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.items});
  final List<_HeroItem> items;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  int _index = 0;
  Timer? _timer;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (!mounted || _hover || widget.items.length < 2) return;
      setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  void didUpdateWidget(_HeroCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.items.length) _index = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Cross-fading children fill the banner (the default layout centers them).
  static Widget _fill(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.expand, children: [...previous, ?current]);

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final height = (MediaQuery.sizeOf(context).height * 0.74).clamp(540.0, 780.0);
    return MouseRegion(
      onEnter: (_) => _hover = true,
      onExit: (_) => _hover = false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.surface),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  layoutBuilder: _fill,
                  child: _HeroBackground(key: ValueKey(_index), item: item),
                ),
                // Scrims: under the glass bar, on the left for the text, at the bottom.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment(0, -0.45),
                      colors: [Color(0x800A0A0C), Color(0x000A0A0C)],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xE60A0A0C), Color(0x990A0A0C), Color(0x000A0A0C)],
                      stops: [0, 0.34, 0.68],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment(0, 0.1),
                      colors: [Color(0xBF0A0A0C), Color(0x000A0A0C)],
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  layoutBuilder: _fill,
                  child: _HeroContent(key: ValueKey('c$_index'), item: item),
                ),
                if (widget.items.length > 1)
                  Positioned(
                    right: 32,
                    bottom: 36,
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Semantics(
                              button: true,
                              label: 'À la une ${i + 1}',
                              child: GestureDetector(
                                onTap: () => setState(() => _index = i),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: i == _index ? 24 : 8,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: i == _index ? Colors.white : Colors.white.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({super.key, required this.item});
  final _HeroItem item;

  @override
  Widget build(BuildContext context) {
    if (item.landscape) {
      return NetImage(
        item.image,
        decodeWidth: 1600,
        alignment: const Alignment(0, -0.3),
        placeholder: const ColoredBox(color: AppColors.surface),
      );
    }
    // Portrait poster: blurred, enlarged poster as the backdrop and the
    // poster itself on the right.
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Opacity(
            opacity: 0.6,
            child: NetImage(item.image, decodeWidth: 300, placeholder: const ColoredBox(color: AppColors.surface)),
          ),
        ),
        Align(
          alignment: const Alignment(0.82, 0.25),
          child: Container(
            width: 280,
            height: 420,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24))],
            ),
            clipBehavior: Clip.antiAlias,
            child: NetImage(item.image, decodeWidth: 280),
          ),
        ),
      ],
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({super.key, required this.item});
  final _HeroItem item;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.075).clamp(64.0, 116.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 40, 36, 56),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LumenMark(size: 20),
                  const SizedBox(width: 8),
                  Text(item.kicker, style: labelStyle(color: AppColors.textSoft, size: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: posterStyle(
                  titleSize,
                  height: 0.88,
                  shadows: const [Shadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 4))],
                ),
              ),
              if (item.meta.isNotEmpty || item.rating != null) ...[
                const SizedBox(height: 14),
                _MetaLine(meta: item.meta, rating: item.rating),
              ],
              if (item.overview != null) ...[
                const SizedBox(height: 14),
                Text(
                  item.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.textSoft),
                ),
              ],
              if (item.progress != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(width: 240, child: ProgressLine(item.progress!, track: const Color(0x40FFFFFF))),
                    const SizedBox(width: 12),
                    Text(
                      item.progressLabel ?? '',
                      style: const TextStyle(fontSize: 14, color: AppColors.textSoft, fontFeatures: tabularFigures),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => item.onPrimary(context),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: Text(item.primaryLabel),
                  ),
                  if (item.secondaryLabel != null && item.onSecondary != null)
                    OutlinedButton.icon(
                      onPressed: () => item.onSecondary!(context),
                      icon: const Icon(Icons.info_outline_rounded, size: 22),
                      label: Text(item.secondaryLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Film • 2024 • ★ 6,8" line.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.meta, this.rating});
  final List<String> meta;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSoft);
    final parts = <Widget>[
      for (final m in meta) Text(m, style: style),
      if (rating != null && rating! > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 17, color: AppColors.accent),
            const SizedBox(width: 3),
            Text(rating!.toStringAsFixed(1).replaceAll('.', ','), style: style),
          ],
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const Text('•', style: TextStyle(color: AppColors.faint)),
          parts[i],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------- live cards

class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.title, required this.channels, required this.onGuide});
  final String title;
  final List<Channel> channels;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return SectionRow(
      title: title,
      height: 216,
      itemWidth: 300,
      gap: 12,
      trailing: TextButton(onPressed: onGuide, child: const Text('Ouvrir le guide')),
      itemCount: channels.length,
      itemBuilder: (context, i) =>
          LiveCard(channel: channels[i], onTap: () => Launch.channel(context, channels[i], channels)),
    );
  }
}
