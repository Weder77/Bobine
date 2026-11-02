import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
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
      if (mounted && _episodes.isEmpty) setState(() => _error = e.toString());
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
    final seasons = _episodes.map((e) => e.season).toSet().toList()..sort();
    final target = _target();
    final meta = <String>[
      if (_sr.year != null) '${_sr.year}',
      if (seasons.isNotEmpty) '${seasons.length} saison${seasons.length > 1 ? 's' : ''}',
      if ((d?.genre ?? _sr.genre) != null) (d?.genre ?? _sr.genre)!,
    ];
    final plot = d?.plot ?? _sr.plot;

    return DetailLayout(
      backdrop: d?.backdrop ?? _sr.backdrop,
      poster: _sr.poster ?? d?.poster,
      title: _sr.name,
      rating: d?.rating ?? _sr.rating,
      meta: meta,
      loading: _loading,
      actions: [
        if (target != null)
          FilledButton.icon(
            onPressed: () => Launch.episode(context, _sr, target.$1, _episodes),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('${target.$2 ? 'Reprendre' : 'Lecture'} ${target.$1.code}'),
          ),
        OutlinedButton.icon(
          onPressed: () => _s.toggleFavorite(ContentKind.series, _sr.extId, _sr.sourceId),
          icon: Icon(_fav ? Icons.favorite : Icons.favorite_border, color: _fav ? AppColors.accent2 : null),
          label: Text(_fav ? 'Dans mes favoris' : 'Favori'),
        ),
      ],
      bottom: _episodes.isEmpty
          ? (_loading
              ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              : null)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in seasons)
                    ChoiceChip(
                      label: Text('Saison $s'),
                      selected: s == _season,
                      onSelected: (_) => setState(() => _season = s),
                    ),
                ]),
                const SizedBox(height: 16),
                for (final e in _episodes.where((e) => e.season == _season))
                  _EpisodeTile(
                    episode: e,
                    progress: _progress[e.extId],
                    fallbackImage: d?.backdrop ?? _sr.backdrop ?? _sr.poster,
                    onTap: () => Launch.episode(context, _sr, e, _episodes),
                  ),
              ]),
            ),
      children: [
        if (plot != null) DetailParagraph(plot),
        if (d?.cast != null) DetailField('Avec', d!.cast!),
        if (_error != null)
          Text('Impossible de charger les épisodes : $_error', style: const TextStyle(color: AppColors.live)),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.progress, required this.onTap, this.fallbackImage});
  final Episode episode;
  final ProgressEntry? progress;
  final String? fallbackImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final p = progress;
    return HoverBuilder(builder: (context, hover) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hover ? AppColors.surface2 : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hover ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 210,
                height: 118,
                child: Stack(fit: StackFit.expand, children: [
                  NetImage(e.image ?? fallbackImage, decodeWidth: 210),
                  if (hover)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Icon(Icons.play_circle_fill_rounded, size: 44, color: AppColors.accent),
                    ),
                  if (p != null)
                    Positioned(left: 8, right: 8, bottom: 8, child: ProgressLine(p.finished ? 1 : p.fraction)),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
                Row(children: [
                  Text('${e.episode}. ',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
                  Expanded(
                    child: Text(e.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  if (p != null && p.finished)
                    const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                  if (e.durationSec != null) ...[
                    const SizedBox(width: 10),
                    Text(formatRuntime(e.durationSec), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ]),
                const SizedBox(height: 6),
                if (e.plot != null)
                  Text(e.plot!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 13)),
                if (p != null && !p.finished && p.position.inSeconds > 30)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Arrêté à ${formatDuration(p.position)}',
                        style: const TextStyle(color: AppColors.accent, fontSize: 12.5)),
                  ),
              ]),
            ),
          ]),
        ),
      );
    });
  }
}
