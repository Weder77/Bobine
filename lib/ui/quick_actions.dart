import 'package:flutter/material.dart';

import '../core/device.dart';
import '../core/format.dart';
import '../core/open_url.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../player/player_screen.dart';
import '../services.dart';
import 'launch.dart';
import 'multi_view_screen.dart';

/// One line of a quick actions menu; null draws a separator.
class QuickAction {
  const QuickAction(this.label, this.icon, this.onTap, {this.danger = false});
  const QuickAction.header(this.label) : icon = null, onTap = null, danger = false;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;
  bool get isHeader => onTap == null;
}

/// Shows [actions] as a menu at [at] (right click, long press, menu key).
Future<void> showQuickActions(BuildContext context, Offset at, List<QuickAction?> actions) async {
  final size = MediaQuery.sizeOf(context);
  final items = <PopupMenuEntry<int>>[];
  for (var i = 0; i < actions.length; i++) {
    final a = actions[i];
    if (a == null) {
      if (items.isNotEmpty && items.last is! PopupMenuDivider) items.add(const PopupMenuDivider());
    } else if (a.isHeader) {
      items.add(
        PopupMenuItem<int>(
          enabled: false,
          height: 30,
          child: Text(a.label, style: labelStyle(color: AppColors.faint, size: 11)),
        ),
      );
    } else {
      final color = a.danger ? AppColors.live : AppColors.text;
      items.add(
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(a.icon, size: 20, color: a.danger ? AppColors.live : AppColors.textSoft),
              const SizedBox(width: 14),
              Flexible(
                child: Text(a.label, style: TextStyle(color: color)),
              ),
            ],
          ),
        ),
      );
    }
  }
  final chosen = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
    items: items,
  );
  if (chosen != null) actions[chosen]?.onTap?.call();
}

void _toast(BuildContext context, String text, {SnackBarAction? action}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action));
}

QuickAction _favorite(AppServices s, ContentKind kind, int sourceId, String extId) {
  final fav = s.repo.isFavorite(sourceId, kind, extId);
  return QuickAction(
    fav ? 'Retirer des favoris' : 'Ajouter aux favoris',
    fav ? Icons.heart_broken_outlined : Icons.favorite_border_rounded,
    () => s.toggleFavorite(kind, extId, sourceId),
  );
}

// ------------------------------------------------------------------- films

/// Right click on a film: play / resume, from the start, details, favourite,
/// seen, trailer.
Future<void> showMovieActions(BuildContext context, Movie m, Offset at) {
  final s = AppScope.of(context);
  final p = s.repo.progress(m.sourceId, ContentKind.movie, m.extId);
  final resumable = p != null && p.resumable;
  final seen = p != null && p.finished;
  final trailer = s.tmdb.cachedMovie(m)?.trailer;
  return showQuickActions(context, at, [
    QuickAction.header(m.name.toUpperCase()),
    QuickAction(
      resumable ? 'Reprendre à ${formatDuration(p.position)}' : 'Lecture',
      Icons.play_arrow_rounded,
      () => Launch.movie(context, m),
    ),
    if (resumable) QuickAction('Depuis le début', Icons.replay_rounded, () => Launch.movie(context, m, restart: true)),
    QuickAction("Plus d'infos", Icons.info_outline_rounded, () => Launch.openMovie(context, m)),
    null,
    _favorite(s, ContentKind.movie, m.sourceId, m.extId),
    QuickAction(
      seen ? 'Marquer comme non vu' : 'Marquer comme vu',
      seen ? Icons.visibility_off_outlined : Icons.check_rounded,
      () {
        s.repo.setWatched(m.sourceId, ContentKind.movie, m.extId, seen: !seen, title: m.name, image: m.poster);
        s.library.userChanged();
      },
    ),
    if (trailer != null) QuickAction('Bande-annonce', Icons.smart_display_outlined, () => openExternal(trailer)),
  ]);
}

// ------------------------------------------------------------------ séries

/// Episode to start with: the one in progress, the next unwatched, or the
/// first. The bool says whether it resumes.
(Episode, bool)? seriesTarget(List<Episode> episodes, ProgressEntry? last) {
  if (episodes.isEmpty) return null;
  if (last != null) {
    final i = episodes.indexWhere((e) => e.extId == last.extId);
    if (i >= 0) {
      // Taken out of "Reprendre" (no position kept): it starts again.
      if (!last.finished) return (episodes[i], last.resumable);
      if (i + 1 < episodes.length) return (episodes[i + 1], false);
    }
  }
  return (episodes.first, false);
}

/// Episodes of [sr]: from the cache, else asked to the Xtream server.
Future<List<Episode>> _loadEpisodes(AppServices s, Series sr) => loadEpisodes(s.repo, sr);

bool _seriesStarting = false;

/// Plays a series where the profile left it (or its first episode),
/// loading the episodes from the server when needed.
Future<void> playSeries(BuildContext context, Series sr) async {
  // The episodes may take a few seconds to come: a second click meanwhile
  // opened a second player on the same engine.
  if (_seriesStarting) return;
  final s = AppScope.of(context);
  final opened = PlayerScreen.opened;
  final route = ModalRoute.of(context);
  final List<Episode> all;
  _seriesStarting = true;
  try {
    all = await _loadEpisodes(s, sr);
  } finally {
    _seriesStarting = false;
  }
  final t = seriesTarget(all, s.repo.lastEpisodeProgress(sr.sourceId, sr.extId));
  // Something else was opened while they loaded, or the screen changed:
  // the episode is not pushed over it.
  if (!context.mounted || PlayerScreen.opened != opened || !(route?.isCurrent ?? true)) return;
  if (t == null) return Launch.openSeries(context, sr);
  await Launch.episode(context, sr, t.$1, all);
}

/// Right click on a series: resume or next episode, start a season, details,
/// favourite, trailer.
Future<void> showSeriesActions(BuildContext context, Series sr, Offset at) async {
  final s = AppScope.of(context);
  final episodes = s.repo.episodes(sr.sourceId, sr.extId);
  final last = s.repo.lastEpisodeProgress(sr.sourceId, sr.extId);
  final target = seriesTarget(episodes, last);
  final seasons = episodes.map((e) => e.season).toSet().toList()..sort();
  final trailer = s.tmdb.cachedSeries(sr)?.trailer;

  Future<void> playSeason(int season, List<Episode> all) async {
    final first = all.where((e) => e.season == season).firstOrNull;
    if (first != null && context.mounted) await Launch.episode(context, sr, first, all, restart: true);
  }

  Future<void> chooseSeason() async {
    final all = await _loadEpisodes(s, sr);
    if (!context.mounted) return;
    final list = all.map((e) => e.season).toSet().toList()..sort();
    if (list.isEmpty) return _toast(context, 'Aucun épisode trouvé pour cette série.');
    await showQuickActions(context, at, [
      const QuickAction.header('LANCER DEPUIS'),
      for (final n in list)
        QuickAction(
          'Saison $n · ${all.where((e) => e.season == n).length} épisodes',
          Icons.playlist_play_rounded,
          () => playSeason(n, all),
        ),
    ]);
  }

  return showQuickActions(context, at, [
    QuickAction.header(sr.name.toUpperCase()),
    if (target != null)
      QuickAction(
        '${target.$2 ? 'Reprendre' : 'Lecture'} ${target.$1.code}',
        Icons.play_arrow_rounded,
        () => Launch.episode(context, sr, target.$1, episodes),
      )
    else
      QuickAction('Lecture', Icons.play_arrow_rounded, () async {
        final all = await _loadEpisodes(s, sr);
        final t = seriesTarget(all, last);
        if (!context.mounted) return;
        if (t == null) return _toast(context, 'Aucun épisode trouvé pour cette série.');
        await Launch.episode(context, sr, t.$1, all);
      }),
    // A few seasons are listed directly, more open a second menu.
    if (seasons.length > 1 && seasons.length <= 6) ...[
      null,
      const QuickAction.header('LANCER DEPUIS'),
      for (final n in seasons)
        QuickAction(
          'Saison $n · ${episodes.where((e) => e.season == n).length} épisodes',
          Icons.playlist_play_rounded,
          () => playSeason(n, episodes),
        ),
      null,
    ] else if (seasons.length != 1)
      QuickAction('Lancer une saison…', Icons.playlist_play_rounded, chooseSeason),
    QuickAction("Plus d'infos", Icons.info_outline_rounded, () => Launch.openSeries(context, sr)),
    null,
    _favorite(s, ContentKind.series, sr.sourceId, sr.extId),
    if (trailer != null) QuickAction('Bande-annonce', Icons.smart_display_outlined, () => openExternal(trailer)),
  ]);
}

// --------------------------------------------------------------- reprendre

/// Right click on a "Reprendre" card.
Future<void> showProgressActions(BuildContext context, ProgressEntry p, Offset at) {
  final s = AppScope.of(context);
  final episode = p.kind == ContentKind.episode;
  final series = episode && p.seriesExt != null ? s.repo.seriesByExt(p.sourceId, p.seriesExt!) : null;
  final movie = episode ? null : s.repo.movieByExt(p.sourceId, p.extId);

  Future<void> restart() async {
    if (movie != null) return Launch.movie(context, movie, restart: true, image: p.image);
    if (series == null) return;
    final all = await loadEpisodes(s.repo, series);
    final e = all.where((x) => x.extId == p.extId).firstOrNull;
    if (!context.mounted) return;
    if (e != null) return Launch.episode(context, series, e, all, restart: true);
    _toast(context, 'Cet épisode n’est plus proposé par la source.');
  }

  return showQuickActions(context, at, [
    QuickAction.header(p.title.toUpperCase()),
    if (p.upNext)
      QuickAction(
        'Lecture ${p.subtitle?.split(' · ').first ?? ''}'.trim(),
        Icons.play_arrow_rounded,
        () => Launch.resume(context, p),
      )
    else ...[
      QuickAction(
        'Reprendre à ${formatDuration(p.position)}',
        Icons.play_arrow_rounded,
        () => Launch.resume(context, p),
      ),
      QuickAction('Depuis le début', Icons.replay_rounded, restart),
    ],
    if (movie != null)
      QuickAction("Plus d'infos", Icons.info_outline_rounded, () => Launch.openMovie(context, movie))
    else if (series != null)
      QuickAction('Voir la série', Icons.info_outline_rounded, () => Launch.openSeries(context, series)),
    null,
    QuickAction(episode ? "Marquer l'épisode comme vu" : 'Marquer comme vu', Icons.check_rounded, () {
      // The next episode may have no row yet: it must join its series.
      s.repo.setWatched(
        p.sourceId,
        p.kind,
        p.extId,
        seen: true,
        title: p.title,
        subtitle: p.subtitle,
        image: p.image,
        seriesExt: p.seriesExt,
      );
      s.library.userChanged();
    }),
    QuickAction('Retirer de Reprendre', Icons.close_rounded, () => takeOutOfResume(context, p), danger: true),
  ]);
}

/// Takes [p] out of "Reprendre" (right click or the cross of its card), with
/// "Annuler" for a click made too fast.
void takeOutOfResume(BuildContext context, ProgressEntry p) {
  final s = AppScope.of(context);
  s.repo.removeFromResume(p);
  s.library.userChanged();
  _toast(
    context,
    '« ${p.title} » retiré de Reprendre',
    action: SnackBarAction(
      label: 'Annuler',
      onPressed: () {
        // The next episode had no position: the series is back where it was.
        if (p.upNext) {
          s.repo.removeProgress(p.sourceId, p.kind, p.extId);
        } else {
          s.repo.saveProgress(
            sourceId: p.sourceId,
            kind: p.kind,
            extId: p.extId,
            position: p.position,
            duration: p.duration,
            title: p.title,
            subtitle: p.subtitle,
            image: p.image,
            seriesExt: p.seriesExt,
          );
        }
        s.library.userChanged();
      },
    ),
  );
}

// ----------------------------------------------------------------- chaînes

/// Right click on a channel: watch, favourite, record, hide.
Future<void> showChannelActions(
  BuildContext context,
  Channel c,
  List<Channel> channels,
  Offset at, {
  VoidCallback? onPlay,
}) {
  final s = AppScope.of(context);
  final now = s.epg.now(c);
  return showQuickActions(context, at, [
    QuickAction.header(s.channelName(c).toUpperCase()),
    QuickAction(
      'Regarder en plein écran',
      Icons.play_arrow_rounded,
      onPlay ?? () => Launch.channel(context, c, channels),
    ),
    QuickAction('Ajouter au multi-écran', Icons.grid_view_rounded, () => MultiViewScreen.open(context, add: c)),
    _favorite(s, ContentKind.live, c.sourceId, c.extId),
    null,
    if (Device.canRecord)
      QuickAction(
        now == null ? 'Enregistrer maintenant' : 'Enregistrer « ${now.title} »',
        Icons.fiber_manual_record_rounded,
        () {
          s.recordings.recordNow(c, current: now);
          _toast(context, 'Enregistrement de « ${now?.title ?? s.channelName(c)} » démarré');
        },
      ),
    QuickAction('Masquer la chaîne', Icons.visibility_off_outlined, () {
      s.repo.setChannelHidden(c.sourceId, c.extId, true);
      s.visibilityChanged();
      _toast(
        context,
        '« ${s.channelName(c)} » est masquée. Réglages → Catégories et chaînes pour la retrouver.',
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            s.repo.setChannelHidden(c.sourceId, c.extId, false);
            s.visibilityChanged();
          },
        ),
      );
    }, danger: true),
  ]);
}
