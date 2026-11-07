import 'package:flutter/material.dart';

import '../data/models.dart';
import '../player/play_items.dart';
import '../player/player_screen.dart';
import '../player/player_session.dart';
import '../services.dart';
import 'movie_detail_screen.dart';
import 'series_detail_screen.dart';

/// Entry points used by every screen to start playback or open details.
class Launch {
  static Future<void> channel(BuildContext context, Channel c, List<Channel> list, {bool keepAlive = false}) async {
    final s = AppScope.of(context);
    final source = s.repo.source(c.sourceId);
    if (source == null) return;
    var index = list.indexWhere((x) => x.extId == c.extId);
    final channels = index < 0 ? [c] : list;
    if (index < 0) index = 0;
    await PlayerScreen.open(
      context,
      PlayerSession(item: channelItem(source, c), channels: channels, channelIndex: index, keepAlive: keepAlive),
    );
  }

  static Future<void> movie(BuildContext context, Movie m, {bool restart = false, String? image}) async {
    final s = AppScope.of(context);
    final source = s.repo.source(m.sourceId);
    if (source == null) return;
    final p = s.repo.progress(m.sourceId, ContentKind.movie, m.extId);
    await PlayerScreen.open(
      context,
      PlayerSession(
        item: movieItem(source, m, image: image),
        start: (!restart && p != null && p.resumable) ? p.position : null,
      ),
    );
  }

  static Future<void> episode(
    BuildContext context,
    Series? series,
    Episode e,
    List<Episode> all, {
    bool restart = false,
  }) async {
    final s = AppScope.of(context);
    final source = s.repo.source(e.sourceId);
    if (source == null) return;
    final p = s.repo.progress(e.sourceId, ContentKind.episode, e.extId);
    await PlayerScreen.open(
      context,
      PlayerSession(
        item: episodeItem(source, series, e),
        start: (!restart && p != null && p.resumable) ? p.position : null,
        episodes: all,
        series: series,
      ),
    );
  }

  /// Resumes an entry of "Continuer à regarder".
  static Future<void> resume(BuildContext context, ProgressEntry p) async {
    final s = AppScope.of(context);
    if (p.kind == ContentKind.movie) {
      final m = s.repo.movieByExt(p.sourceId, p.extId);
      if (m != null) return movie(context, m, image: p.image);
    } else if (p.kind == ContentKind.episode && p.seriesExt != null) {
      final series = s.repo.seriesByExt(p.sourceId, p.seriesExt!);
      final all = s.repo.episodes(p.sourceId, p.seriesExt!);
      final e = all.where((x) => x.extId == p.extId).firstOrNull;
      if (e != null) return episode(context, series, e, all);
      if (series != null && context.mounted) return openSeries(context, series);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Ce contenu n'est plus disponible chez le fournisseur.")));
    }
  }

  static Future<void> openMovie(BuildContext context, Movie m) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: m)));

  static Future<void> openSeries(BuildContext context, Series sr) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: sr)));
}
