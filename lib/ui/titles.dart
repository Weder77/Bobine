import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../data/models.dart';
import '../features/tmdb.dart';
import '../services.dart';
import 'launch.dart';
import 'quick_actions.dart';
import 'widgets/billboard.dart';
import 'widgets/rows.dart';

/// Key of a favourite in [TitleCards.favorites].
String favKey(ContentKind kind, String extId) => '${kind.db}:$extId';

/// Builds the billboard entries, posters and Top 10 items of films and
/// series the same way on the home, films and series pages.
class TitleCards {
  TitleCards(this.context, this.s, this.favorites);
  final BuildContext context;
  final AppServices s;

  /// [favKey]s of the profile's favourites.
  final Set<String> favorites;

  static Set<String> loadFavorites(AppServices s, int sourceId) => {
    for (final m in s.repo.favoriteMovies(sourceId)) favKey(ContentKind.movie, m.extId),
    for (final sr in s.repo.favoriteSeries(sourceId)) favKey(ContentKind.series, sr.extId),
  };

  HeroEntry movieHero(Movie m, String kicker) {
    final t = s.tmdb.cachedMovie(m);
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
      favorite: favorites.contains(favKey(ContentKind.movie, m.extId)),
      onFavorite: () => s.toggleFavorite(ContentKind.movie, m.extId, m.sourceId),
    );
  }

  HeroEntry seriesHero(Series sr, String kicker) {
    final t = s.tmdb.cachedSeries(sr);
    final started = s.repo.lastEpisodeProgress(sr.sourceId, sr.extId) != null;
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
      favorite: favorites.contains(favKey(ContentKind.series, sr.extId)),
      onFavorite: () => s.toggleFavorite(ContentKind.series, sr.extId, sr.sourceId),
    );
  }

  /// A title in progress, with its progress bar and "Reprendre" (or the
  /// next episode of a series, from its start).
  HeroEntry resumeHero(ProgressEntry p) {
    final episode = p.kind == ContentKind.episode;
    final movie = episode ? null : s.repo.movieByExt(p.sourceId, p.extId);
    final series = episode && p.seriesExt != null ? s.repo.seriesByExt(p.sourceId, p.seriesExt!) : null;
    final code = p.subtitle?.split(' · ').first;
    final base = movie != null
        ? movieHero(movie, 'Film · Reprendre')
        : series != null
        ? seriesHero(series, p.upNext ? 'Série · Épisode suivant' : 'Série · Tu en es à ${code ?? "l'épisode"}')
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
      progress: p.upNext ? null : p.fraction,
      progressLabel: p.upNext ? null : (episode && code != null ? '$code · $left' : left),
      primaryLabel: '${p.upNext ? 'Lecture' : 'Reprendre'}${episode && code != null ? ' $code' : ''}',
      onPrimary: () => Launch.resume(context, p),
      onInfo: base?.onInfo,
      favorite: base?.favorite ?? false,
      onFavorite: base?.onFavorite,
    );
  }

  PosterItem moviePoster(Movie m, {String? badge}) {
    final t = s.tmdb.cachedMovie(m);
    return PosterItem(
      key: 'm${m.extId}',
      title: displayTitle(m.name),
      poster: m.poster ?? t?.poster,
      year: m.year ?? cleanTitle(m.name).$2 ?? t?.year,
      rating: m.rating ?? t?.rating,
      genre: t?.genres.firstOrNull,
      badge: badge,
      favorite: favorites.contains(favKey(ContentKind.movie, m.extId)),
      onPlay: () => Launch.movie(context, m),
      onInfo: () => Launch.openMovie(context, m),
      onFavorite: () => s.toggleFavorite(ContentKind.movie, m.extId, m.sourceId),
      onContextMenu: (at) => showMovieActions(context, m, at),
    );
  }

  PosterItem seriesPoster(Series sr, {String? badge}) {
    final t = s.tmdb.cachedSeries(sr);
    return PosterItem(
      key: 's${sr.extId}',
      title: displayTitle(sr.name),
      poster: sr.poster ?? t?.poster,
      year: sr.year ?? t?.year,
      rating: sr.rating ?? t?.rating,
      genre: sr.genre?.split(RegExp(r'[,/]')).first.trim() ?? t?.genres.firstOrNull,
      badge: badge,
      favorite: favorites.contains(favKey(ContentKind.series, sr.extId)),
      onPlay: () => playSeries(context, sr),
      onInfo: () => Launch.openSeries(context, sr),
      onFavorite: () => s.toggleFavorite(ContentKind.series, sr.extId, sr.sourceId),
      onContextMenu: (at) => showSeriesActions(context, sr, at),
    );
  }

  PosterItem poster(Object o) => o is Movie ? moviePoster(o) : seriesPoster(o as Series);

  TopItem top(Object o) {
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

  /// Fetches the TMDB details of [titles] once (tracked in [asked]), then
  /// calls [done].
  static void prefetch(AppServices s, Iterable<Object> titles, Set<String> asked, VoidCallback done) {
    if (!s.tmdb.enabled) return;
    for (final t in titles) {
      if (t is Movie && asked.add('m:${t.sourceId}:${t.extId}')) {
        s.tmdb.movie(t).then((info) => info != null ? done() : null);
      } else if (t is Series && asked.add('s:${t.sourceId}:${t.extId}')) {
        s.tmdb.series(t).then((info) => info != null ? done() : null);
      }
    }
  }
}
