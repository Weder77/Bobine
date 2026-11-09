import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/open_url.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../features/tmdb.dart';
import '../services.dart';
import 'launch.dart';
import 'widgets/common.dart';
import 'widgets/detail_layout.dart';
import 'widgets/net_image.dart';

class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});
  final Series series;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late final AppServices _s;
  SeriesDetails? _details;
  TmdbInfo? _tmdb;
  List<Episode> _episodes = const [];
  Map<String, ProgressEntry> _progress = const {};
  ProgressEntry? _last;
  bool _fav = false;
  bool _loading = false;
  String? _error;
  int? _season;

  Series get _sr => widget.series;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_refreshUser);
    // Show cached episodes instantly, then refresh from the server.
    _episodes = _s.repo.episodes(_sr.sourceId, _sr.extId);
    _refreshUser();
    _load();
    _tmdb = _s.tmdb.cachedSeries(_sr);
    _loadTmdb();
  }

  Future<void> _loadTmdb() async {
    final info = await _s.tmdb.series(_sr);
    if (mounted && info != null) setState(() => _tmdb = info);
  }

  @override
  void dispose() {
    _s.library.removeListener(_refreshUser);
    super.dispose();
  }

  void _refreshUser() {
    setState(() {
      _progress = _s.repo.seriesProgress(_sr.sourceId, _sr.extId);
      _last = _s.repo.lastEpisodeProgress(_sr.sourceId, _sr.extId);
      _fav = _s.repo.isFavorite(_sr.sourceId, ContentKind.series, _sr.extId);
      _season ??= _defaultSeason();
    });
  }

  int? _defaultSeason() {
    if (_episodes.isEmpty) return null;
    final last = _last;
    if (last != null) {
      final e = _episodes.where((e) => e.extId == last.extId).firstOrNull;
      if (e != null) return e.season;
    }
    return _episodes.first.season;
  }

  Future<void> _load() async {
    final src = _s.repo.source(_sr.sourceId);
    if (src == null || !src.isXtream) return;
    setState(() => _loading = true);
    final api = XtreamApi.forSource(src);
    try {
      final d = await api.seriesInfo(_sr.sourceId, _sr.extId);
      if (!mounted) return;
      _s.repo.replaceEpisodes(_sr.sourceId, _sr.extId, d.episodes);
      setState(() {
        _details = d;
        _episodes = d.episodes;
        _error = null;
        if (_season == null || !_episodes.any((e) => e.season == _season)) _season = _defaultSeason();
      });
    } catch (e) {
      if (mounted && _episodes.isEmpty) setState(() => _error = redactCredentials(e.toString()));
    } finally {
      api.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Episode to start with: the one in progress, the next unwatched, or the first.
  (Episode, bool)? _target() {
    if (_episodes.isEmpty) return null;
    final last = _last;
    if (last != null) {
      final i = _episodes.indexWhere((e) => e.extId == last.extId);
      if (i >= 0) {
        if (!last.finished) return (_episodes[i], true);
        if (i + 1 < _episodes.length) return (_episodes[i + 1], false);
      }
    }
    return (_episodes.first, false);
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    final t = _tmdb;
    final seasons = _episodes.map((e) => e.season).toSet().toList()..sort();
    final target = _target();
    final year = _sr.year ?? t?.year;
    final meta = <String>[
      if (year != null) '$year',
      if (seasons.isNotEmpty) '${seasons.length} saison${seasons.length > 1 ? 's' : ''}',
    ];
    final genre = t != null && t.genres.isNotEmpty ? t.genres.join(', ') : (d?.genre ?? _sr.genre);
    final plot = t?.overview ?? d?.plot ?? _sr.plot;
    final cast = d?.cast ?? (t == null || t.cast.isEmpty ? null : t.cast.join(', '));
    final backdrop = t?.backdrop ?? d?.backdrop ?? _sr.backdrop;
    final trailer = trailerUrl(t?.trailer);

    final category = _s.repo.categoryName(_sr.categoryId);
    final lastProgress = target != null && target.$2 ? _progress[target.$1.extId] : null;
    return DetailLayout(
      breadcrumb: category == null ? 'Séries' : 'Séries · $category',
      progress: lastProgress?.fraction,
      progressLabel: lastProgress == null
          ? null
          : '${target!.$1.code} · reste ${formatRuntime((lastProgress.duration - lastProgress.position).inSeconds)}',
      backdrop: backdrop,
      poster: _sr.poster ?? d?.poster ?? t?.poster,
      title: displayTitle(_sr.name),
      rating: d?.rating ?? _sr.rating ?? t?.rating,
      meta: meta,
      loading: _loading,
      fields: [
        if (cast != null) ('Distribution', cast),
        if (t?.director != null) ('Création', t!.director!),
        if (genre != null) ('Genres', genre),
        if (category != null) ('Catégorie', category),
      ],
      actions: [
        if (target != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
            onPressed: () => Launch.episode(context, _sr, target.$1, _episodes),
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: Text('${target.$2 ? 'Reprendre' : 'Lecture'} ${target.$1.code}'),
          ),
        RoundAction(
          icon: _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          tooltip: _fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
          color: _fav ? AppColors.cueSeries : null,
          onPressed: () => _s.toggleFavorite(ContentKind.series, _sr.extId, _sr.sourceId),
        ),
        if (_episodes.isNotEmpty && target != null && target.$1.extId != _episodes.first.extId)
          RoundAction(
            icon: Icons.replay_rounded,
            tooltip: 'Recommencer depuis ${_episodes.first.code}',
            onPressed: () => Launch.episode(context, _sr, _episodes.first, _episodes),
          ),
        if (trailer != null)
          RoundAction(
            icon: Icons.smart_display_outlined,
            tooltip: 'Bande-annonce',
            onPressed: () => openExternal(trailer),
          ),
      ],
      bottom: _episodes.isEmpty
          ? (_loading
                ? Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: AppColors.text)),
                  )
                : null)
          : Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1196),
                child: DetailSection(
                  title: 'Épisodes',
                  trailing: seasons.length < 2 ? null : _seasonMenu(seasons),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in _episodes.where((e) => e.season == _season))
                        _EpisodeTile(
                          episode: e,
                          progress: _progress[e.extId],
                          current: target != null && target.$1.extId == e.extId,
                          fallbackImage: backdrop ?? _sr.poster,
                          onTap: () => Launch.episode(context, _sr, e, _episodes),
                        ),
                    ],
                  ),
                ),
              ),
            ),
      children: [
        if (plot != null) DetailParagraph(plot),
        if (_error != null)
          Text('Impossible de charger les épisodes : $_error', style: TextStyle(color: AppColors.live)),
      ],
    );
  }

  /// "Saison 1 (6 épisodes) ▾" selector.
  Widget _seasonMenu(List<int> seasons) {
    int count(int s) => _episodes.where((e) => e.season == s).length;
    String label(int s) => 'Saison $s (${count(s)} épisode${count(s) > 1 ? 's' : ''})';
    return PopupMenuButton<int>(
      tooltip: 'Choisir la saison',
      position: PopupMenuPosition.under,
      onSelected: (s) => setState(() => _season = s),
      itemBuilder: (_) => [
        for (final s in seasons)
          PopupMenuItem(
            value: s,
            child: Text(label(s), style: TextStyle(fontWeight: s == _season ? FontWeight.w700 : FontWeight.w500)),
          ),
      ],
      // The menu button gives no way to set its cursor: the hand comes from here.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.ink.withAlpha(0x4D)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_season == null ? 'Saison' : label(_season!), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Episode row: big number, still with progress, title and duration, plot.
class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.progress,
    required this.onTap,
    this.current = false,
    this.fallbackImage,
  });
  final Episode episode;
  final ProgressEntry? progress;
  final bool current;
  final String? fallbackImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final p = progress;
    return HoverBuilder(
      onActivate: onTap,
      builder: (context, hover) {
        final lit = hover || current;
        return Semantics(
          button: true,
          label: '${e.code} ${e.displayTitle}',
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: lit ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: lit ? null : Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${e.episode}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 200,
                      height: 113,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetImage(
                            e.image ?? fallbackImage,
                            decodeWidth: 200,
                            placeholder: ColoredBox(color: AppColors.surface3),
                          ),
                          if (lit)
                            Container(
                              color: AppColors.bg.withAlpha(0x59),
                              alignment: Alignment.center,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.bg.withAlpha(0x80),
                                  border: Border.all(color: AppColors.ink, width: 2),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, size: 26),
                              ),
                            ),
                          if (p != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: ProgressLine(p.finished ? 1 : p.fraction, track: AppColors.ink.withAlpha(0x33)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                              ),
                            ),
                            if (p != null && p.finished) ...[
                              Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                              const SizedBox(width: 10),
                            ],
                            if (e.durationSec != null)
                              Text(
                                formatRuntime(e.durationSec),
                                style: TextStyle(color: AppColors.muted, fontSize: 15),
                              ),
                          ],
                        ),
                        if (e.plot != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            e.plot!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.textSoft, height: 1.5, fontSize: 14),
                          ),
                        ],
                        if (p != null && !p.finished && p.position.inSeconds > 30)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Arrêté à ${formatDuration(p.position)}',
                              style: TextStyle(color: AppColors.accent, fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
