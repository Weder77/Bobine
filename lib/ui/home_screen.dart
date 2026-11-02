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
  }

  List<_HeroItem> _heroItems() {
    final items = <_HeroItem>[];
    for (final p in _d.continueWatching.take(2)) {
      final isEpisode = p.kind == ContentKind.episode;
      items.add(
        _HeroItem(
          kicker: isEpisode ? 'REPRENDRE · SÉRIE' : 'REPRENDRE · FILM',
          title: p.title,
          meta: p.subtitle ?? '',
          image: p.image,
          landscape: true,
          progress: p.fraction,
          progressLabel: 'reste ${formatRuntime((p.duration - p.position).inSeconds)}',
          primaryLabel: 'Reprendre',
          onPrimary: (c) => Launch.resume(c, p),
        ),
      );
    }
    for (final m in _d.recentMovies.where((m) => m.poster != null).take(4 - items.length)) {
      items.add(
        _HeroItem(
          kicker: 'NOUVEAU · FILM',
          title: m.name,
          meta: [
            if (m.year != null) '${m.year}',
            if (m.rating != null) '★ ${m.rating!.toStringAsFixed(1).replaceAll('.', ',')}',
          ].join(' · '),
          image: m.poster,
          landscape: false,
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
        padding: const EdgeInsets.only(top: 8, bottom: 56),
        children: [
          if (hero.isNotEmpty) _HeroCarousel(items: hero),
          const SizedBox(height: 28),
          _QuickTiles(data: _d, onOpen: (tab) => nav?.goTo(tab)),
          const SizedBox(height: 44),
          if (_d.continueWatching.isNotEmpty) ...[
            SectionRow(
              title: 'Continuer à regarder',
              height: 250,
              itemCount: _d.continueWatching.length,
              itemBuilder: (context, i) {
                final p = _d.continueWatching[i];
                return LandscapeCard(
                  title: p.title,
                  subtitle: [
                    if (p.subtitle != null) p.subtitle!,
                    'reste ${formatRuntime((p.duration - p.position).inSeconds)}',
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
            const SizedBox(height: 40),
          ],
          if (_d.liveChannels.isNotEmpty) ...[
            _LiveRow(
              title: _d.liveAreFavorites ? 'En direct sur tes chaînes' : 'En direct maintenant',
              channels: _d.liveChannels,
              onGuide: () => nav?.goTo(ShellTab.guide),
            ),
            const SizedBox(height: 40),
          ],
          if (_d.recentMovies.isNotEmpty) ...[
            _movieRow('Films ajoutés récemment', _d.recentMovies, favMovieIds, () => nav?.goTo(ShellTab.movies)),
            const SizedBox(height: 40),
          ],
          if (_d.favMovies.isNotEmpty) ...[
            _movieRow('Mes films', _d.favMovies, favMovieIds, null),
            const SizedBox(height: 40),
          ],
          if (_d.recentSeries.isNotEmpty) ...[
            _seriesRow('Séries récentes', _d.recentSeries, () => nav?.goTo(ShellTab.series)),
            const SizedBox(height: 40),
          ],
          if (_d.favSeries.isNotEmpty) ...[_seriesRow('Mes séries', _d.favSeries, null), const SizedBox(height: 40)],
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
      height: 324,
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
      height: 324,
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
    this.progress,
    this.progressLabel,
    this.secondaryLabel,
    this.onSecondary,
  });
  final String kicker;
  final String title;
  final String meta;
  final String? image;
  final bool landscape;
  final double? progress;
  final String? progressLabel;
  final String primaryLabel;
  final void Function(BuildContext) onPrimary;
  final String? secondaryLabel;
  final void Function(BuildContext)? onSecondary;
}

/// Rotating banner (auto-advance, dots to pick an item).
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
    return MouseRegion(
      onEnter: (_) => _hover = true,
      onExit: (_) => _hover = false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 500,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  layoutBuilder: _fill,
                  child: _HeroBackground(key: ValueKey(_index), item: item),
                ),
                // Legibility gradient (left).
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xEB07080B), Color(0x9907080B), Color(0x0007080B)],
                      stops: [0, 0.45, 0.78],
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
                    bottom: 32,
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Semantics(
                              button: true,
                              label: 'À la une ${i + 1}',
                              child: GestureDetector(
                                onTap: () => setState(() => _index = i),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: i == _index ? 28 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: i == _index ? AppColors.accent : Colors.white.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(4),
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
        decodeWidth: 1400,
        alignment: Alignment.topCenter,
        placeholder: const ColoredBox(color: Color(0xFF141A26)),
      );
    }
    // Portrait poster: blurred backdrop + the poster itself on the right.
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
          child: Opacity(
            opacity: 0.55,
            child: NetImage(item.image, decodeWidth: 300, placeholder: const ColoredBox(color: Color(0xFF141A26))),
          ),
        ),
        Align(
          alignment: const Alignment(0.86, 0),
          child: Container(
            width: 250,
            height: 375,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 20))],
            ),
            clipBehavior: Clip.antiAlias,
            child: NetImage(item.image, decodeWidth: 250),
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
    return Padding(
      padding: const EdgeInsets.all(56),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.kicker, style: labelStyle(color: AppColors.accent, size: 13)),
              const SizedBox(height: 14),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(68, weight: FontWeight.w800, height: 0.98),
              ),
              if (item.meta.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(item.meta, style: const TextStyle(fontSize: 17, color: AppColors.textSoft)),
              ],
              if (item.progress != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(width: 280, child: ProgressLine(item.progress!, height: 5)),
                    const SizedBox(width: 14),
                    Text(
                      item.progressLabel ?? '',
                      style: const TextStyle(fontSize: 14, color: AppColors.muted, fontFeatures: tabularFigures),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => item.onPrimary(context),
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: Text(item.primaryLabel),
                  ),
                  if (item.secondaryLabel != null && item.onSecondary != null)
                    OutlinedButton(onPressed: () => item.onSecondary!(context), child: Text(item.secondaryLabel!)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- quick tiles

/// Shortcut tiles under the banner: Live TV, Films, Séries, Recherche.
class _QuickTiles extends StatelessWidget {
  const _QuickTiles({required this.data, required this.onOpen});
  final _HomeData data;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Tile(
        icon: Icons.live_tv_rounded,
        cue: AppColors.cueLive,
        title: 'Live TV',
        subtitle: '${formatCount(data.liveCount)} chaînes · ${data.liveCategories} catégories',
        live: true,
        onTap: () => onOpen(ShellTab.live),
      ),
      _Tile(
        icon: Icons.movie_outlined,
        cue: AppColors.cueFilms,
        title: 'Films',
        subtitle: '${formatCount(data.movieCount)} films',
        onTap: () => onOpen(ShellTab.movies),
      ),
      _Tile(
        icon: Icons.video_library_outlined,
        cue: AppColors.cueSeries,
        title: 'Séries',
        subtitle: '${formatCount(data.seriesCount)} séries',
        onTap: () => onOpen(ShellTab.series),
      ),
      _Tile(
        icon: Icons.search_rounded,
        cue: AppColors.accent,
        title: 'Recherche',
        subtitle: 'Sans accents, mots dans le désordre',
        onTap: () => onOpen(ShellTab.search),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 18), Expanded(child: tiles[i])],
        ],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({
    required this.icon,
    required this.cue,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.live = false,
  });
  final IconData icon;
  final Color cue;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool live;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hover || _focus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: lit ? AppColors.text : AppColors.border, width: 2),
        boxShadow: lit ? [BoxShadow(color: widget.cue.withValues(alpha: 0.2), spreadRadius: 6)] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          onFocusChange: (v) => setState(() => _focus = v),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.cue.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, color: widget.cue, size: 25),
                    ),
                    const Spacer(),
                    if (widget.live)
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'EN DIRECT',
                            style: labelStyle(color: const Color(0xFFFF8A96)).copyWith(letterSpacing: 1),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(26)),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final s = AppScope.of(context);
    return SectionRow(
      title: title,
      height: 160,
      trailing: TextButton(onPressed: onGuide, child: const Text('Ouvrir le guide')),
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final c = channels[i];
        final now = s.epg.now(c);
        return HoverBuilder(
          builder: (context, hover) => GestureDetector(
            onTap: () => Launch.channel(context, c, channels),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 300,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: hover ? AppColors.text : AppColors.border, width: hover ? 2 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChannelLogo(name: c.name, url: c.logo, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              now == null ? 'En direct' : '${formatClock(now.start)} – ${formatClock(now.stop)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (c.number != null)
                        Text(
                          '${c.number}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    now?.title ?? 'Programme non disponible',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: now == null ? AppColors.muted : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProgressLine(now?.progressAt(DateTime.now()) ?? 0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
