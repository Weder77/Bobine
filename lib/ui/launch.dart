import 'dart:io';

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
  /// Whether the parental control keeps this item away now (the user is
  /// told). Lists already leave locked items out; this covers what is
  /// reached by its id: "Reprendre", reminders, recordings, quick actions.
  static bool _locked(BuildContext context, int sourceId, ContentKind kind, String extId, {String? seriesExt}) {
    if (!AppScope.of(context).repo.isLocked(sourceId, kind, extId, seriesExt: seriesExt)) return false;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Contenu verrouillé par le contrôle parental.')));
    return true;
  }

  static Future<void> channel(BuildContext context, Channel c, List<Channel> list, {bool keepAlive = false}) async {
    final s = AppScope.of(context);
    final source = s.repo.source(c.sourceId);
    if (source == null) return;
    if (_locked(context, c.sourceId, ContentKind.live, c.extId)) return;
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
    if (_locked(context, m.sourceId, ContentKind.movie, m.extId)) return;
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
    if (_locked(context, e.sourceId, ContentKind.episode, e.extId, seriesExt: e.seriesExt)) return;
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

  /// Plays a past programme of a live channel (replay), seekable.
  static Future<void> replay(BuildContext context, Channel c, Program p) async {
    final s = AppScope.of(context);
    final source = s.repo.source(c.sourceId);
    if (source == null) return;
    if (_locked(context, c.sourceId, ContentKind.live, c.extId)) return;
    final item = replayItem(source, c, p);
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pas de replay pour cette chaîne.")));
      return;
    }
    await PlayerScreen.open(context, PlayerSession(item: item));
  }

  /// Plays a finished recording.
  static Future<void> recording(BuildContext context, Recording r) async {
    if (_locked(context, r.sourceId, ContentKind.live, r.channelExt)) return;
    if (r.path == null || !File(r.path!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fichier introuvable.')));
      return;
    }
    await PlayerScreen.open(context, PlayerSession(item: recordingItem(r)));
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

  static Future<void> openMovie(BuildContext context, Movie m) async {
    if (_locked(context, m.sourceId, ContentKind.movie, m.extId)) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: m)));
  }

  static Future<void> openSeries(BuildContext context, Series sr) async {
    if (_locked(context, sr.sourceId, ContentKind.series, sr.extId)) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: sr)));
  }
}
