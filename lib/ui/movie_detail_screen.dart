import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/open_url.dart';
import '../core/theme.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../features/tmdb.dart';
import '../services.dart';
import 'launch.dart';
import 'quick_actions.dart';
import 'widgets/common.dart';
import 'widgets/detail_layout.dart';

class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movie});
  final Movie movie;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  late final AppServices _s;
  VodDetails? _details;
  TmdbInfo? _tmdb;
  bool _loading = false;
  ProgressEntry? _progress;
  bool _fav = false;
  String? _category;
  List<Movie> _related = const [];
  Set<String> _favs = const {};

  Movie get _m => widget.movie;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_refreshUser);
    _category = _s.repo.categoryName(_m.categoryId);
    if (_m.categoryId != null) {
      _related = _s.repo
          .movies(_m.sourceId, categoryId: _m.categoryId, limit: 24)
          .where((x) => x.extId != _m.extId)
          .toList();
    }
    _refreshUser();
    _loadDetails();
    _tmdb = _s.tmdb.cachedMovie(_m);
    _loadTmdb();
  }

  Future<void> _loadTmdb() async {
    final info = await _s.tmdb.movie(_m);
    if (mounted && info != null) setState(() => _tmdb = info);
  }

  @override
  void dispose() {
    _s.library.removeListener(_refreshUser);
    super.dispose();
  }

  void _refreshUser() {
    setState(() {
      _progress = _s.repo.progress(_m.sourceId, ContentKind.movie, _m.extId);
      _fav = _s.repo.isFavorite(_m.sourceId, ContentKind.movie, _m.extId);
      _favs = _s.repo.favoriteKeys(_m.sourceId, ContentKind.movie);
    });
  }

  Future<void> _loadDetails() async {
    final src = _s.repo.source(_m.sourceId);
    if (src == null || !src.isXtream || _m.url != null) return;
    setState(() => _loading = true);
    final api = XtreamApi.forSource(src);
    try {
      final d = await api.vodInfo(_m.extId);
      if (mounted) setState(() => _details = d);
    } catch (_) {
      // Details are optional.
    } finally {
      api.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    final t = _tmdb;
    final p = _progress;
    final resumable = p != null && p.resumable;
    final rating = (d?.rating ?? 0) > 0 ? d!.rating : (_m.rating ?? t?.rating);
    final year =
        _m.year?.toString() ??
        ((d?.releaseDate != null && d!.releaseDate!.length >= 4) ? d.releaseDate!.substring(0, 4) : null) ??
        t?.year?.toString();
    final runtime = d?.durationSec ?? (t?.runtimeMinutes == null ? null : t!.runtimeMinutes! * 60);
    final meta = <String>['Film', ?year, if (runtime != null) formatRuntime(runtime)];
    final backdrop = t?.backdrop ?? d?.backdrop;
    final image = backdrop ?? _m.poster;
    final plot = t?.overview ?? d?.plot;
    final cast = d?.cast ?? (t == null || t.cast.isEmpty ? null : t.cast.join(', '));
    final director = d?.director ?? t?.director;
    final genres = t != null && t.genres.isNotEmpty ? t.genres.join(', ') : d?.genre;
    final trailer = trailerUrl(t?.trailer ?? d?.trailer);

    final video = <String>[
      if (d?.videoCodec != null || d?.videoHeight != null)
        [
          ?d?.videoCodec,
          if (d?.videoWidth != null && d?.videoHeight != null) '${d!.videoWidth}×${d.videoHeight}',
          ?d?.hdr,
        ].join(' · '),
      if (_m.container != null) 'Conteneur ${_m.container!.toUpperCase()}',
    ];
    final audio = <String>[
      if (d?.audioCodec != null)
        [d!.audioCodec!, if (d.audioChannels != null) channelLayoutLabel(d.audioChannels!)].join(' · '),
      'Toutes les pistes sont proposées pendant la lecture',
    ];

    return DetailLayout(
      breadcrumb: _category == null ? 'Films' : 'Films · $_category',
      backdrop: backdrop,
      poster: d?.poster ?? _m.poster ?? t?.poster,
      title: displayTitle(_m.name),
      rating: rating,
      meta: meta,
      tags: d?.qualityTags ?? const [],
      fields: [
        if (cast != null) ('Distribution', cast),
        if (director != null) ('Réalisation', director),
        if (genres != null) ('Genres', genres),
        if (_category != null) ('Catégorie', _category!),
      ],
      loading: _loading,
      progress: resumable ? p.fraction : null,
      progressLabel: resumable ? 'reste ${formatRuntime((p.duration - p.position).inSeconds)}' : null,
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
          onPressed: () => Launch.movie(context, _m, image: image),
          icon: const Icon(Icons.play_arrow_rounded, size: 26),
          label: Text(resumable ? 'Reprendre à ${formatDuration(p.position)}' : 'Lecture'),
        ),
        RoundAction(
          icon: _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          tooltip: _fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          color: _fav ? AppColors.cueSeries : null,
          onPressed: () => _s.toggleFavorite(ContentKind.movie, _m.extId, _m.sourceId),
        ),
        if (resumable)
          RoundAction(
            icon: Icons.replay_rounded,
            tooltip: 'Depuis le début',
            onPressed: () => Launch.movie(context, _m, restart: true, image: image),
          ),
        if (trailer != null)
          RoundAction(
            icon: Icons.smart_display_outlined,
            tooltip: 'Bande-annonce',
            onPressed: () => openExternal(trailer),
          ),
      ],
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d?.videoCodec != null || d?.audioCodec != null)
            DetailSection(
              title: 'Pistes et qualité',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InfoCard(label: 'VIDÉO', lines: video),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InfoCard(label: 'AUDIO', lines: audio),
                  ),
                ],
              ),
            ),
          if (_related.isNotEmpty)
            DetailSection(
              title: _category == null ? 'Dans la même catégorie' : 'Dans $_category',
              child: SizedBox(
                height: 318,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _related.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final m = _related[i];
                    return PosterCard(
                      title: m.name,
                      subtitle: m.year?.toString(),
                      image: m.poster,
                      rating: m.rating,
                      favorite: _favs.contains(m.extId),
                      onTap: () =>
                          Navigator.of(context)
                              .pushReplacement(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: m))),
                      onContextMenu: (at) => showMovieActions(context, m, at),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      children: [
        if (t?.tagline != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              t!.tagline!,
              style: const TextStyle(color: AppColors.textSoft, fontStyle: FontStyle.italic, fontSize: 16),
            ),
          ),
        if (plot != null) DetailParagraph(plot),
        if (p != null && p.finished)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Pill('Déjà vu', icon: Icons.check_rounded, color: Color(0x223DDC97), textColor: AppColors.success),
          ),
      ],
    );
  }
}
