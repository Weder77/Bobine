import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/import/xtream_api.dart';
import '../data/models.dart';
import '../services.dart';
import 'launch.dart';
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
  bool _loading = false;
  ProgressEntry? _progress;
  bool _fav = false;

  Movie get _m => widget.movie;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.library.addListener(_refreshUser);
    _refreshUser();
    _loadDetails();
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
    final p = _progress;
    final resumable = p != null && p.resumable;
    final rating = d?.rating ?? _m.rating;
    final meta = <String>[
      if (_m.year != null) '${_m.year}' else if (d?.releaseDate != null && d!.releaseDate!.length >= 4) d.releaseDate!.substring(0, 4),
      if (d?.durationSec != null) formatRuntime(d!.durationSec),
      if (d?.genre != null) d!.genre!,
      if (_m.container != null) _m.container!.toUpperCase(),
    ];

    return DetailLayout(
      backdrop: d?.backdrop,
      poster: d?.poster ?? _m.poster,
      title: _m.name,
      rating: rating,
      meta: meta,
      loading: _loading,
      actions: [
        FilledButton.icon(
          onPressed: () => Launch.movie(context, _m, image: d?.backdrop ?? _m.poster),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(resumable ? 'Reprendre à ${formatDuration(p.position)}' : 'Lecture'),
        ),
        if (resumable)
          OutlinedButton.icon(
            onPressed: () => Launch.movie(context, _m, restart: true, image: d?.backdrop ?? _m.poster),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Depuis le début'),
          ),
        OutlinedButton.icon(
          onPressed: () => _s.toggleFavorite(ContentKind.movie, _m.extId, _m.sourceId),
          icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
              color: _fav ? AppColors.accent2 : null),
          label: Text(_fav ? 'Dans mes favoris' : 'Favori'),
        ),
      ],
      progress: resumable ? p.fraction : null,
      children: [
        if (d?.plot != null) DetailParagraph(d!.plot!),
        if (d?.director != null) DetailField('Réalisation', d!.director!),
        if (d?.cast != null) DetailField('Avec', d!.cast!),
        if (p != null && p.finished)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Pill('Déjà vu', icon: Icons.check_rounded, color: Color(0x223DDC97), textColor: AppColors.success),
          ),
      ],
    );
  }
}
