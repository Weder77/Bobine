import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services.dart';
import '../ui/launch.dart';
import 'tv_browse.dart';
import 'tv_rows.dart';
import 'tv_sheet.dart';

/// What OK held on an item offers.
enum TvItemAction {
  watch,
  resume,
  fromStart,
  seen,
  removeResume,
  addFavorite,
  removeFavorite,
  addList,
  removeList,
  openSeries,
}

/// The choices for [it]: a channel goes to the favourites, a film or a
/// series to Ma liste, a "Reprendre" card can be seen or taken out.
List<TvItemAction> tvItemActions(TvItem it, {required bool favorite}) => switch (it.kind) {
  TvItemKind.live => [TvItemAction.watch, favorite ? TvItemAction.removeFavorite : TvItemAction.addFavorite],
  TvItemKind.movie => [TvItemAction.watch, favorite ? TvItemAction.removeList : TvItemAction.addList],
  TvItemKind.series => [TvItemAction.openSeries, favorite ? TvItemAction.removeList : TvItemAction.addList],
  TvItemKind.resume => [
    TvItemAction.resume,
    if ((it.progress ?? 0) > 0) TvItemAction.fromStart,
    TvItemAction.seen,
    TvItemAction.removeResume,
  ],
};

String tvItemActionLabel(TvItemAction a) => switch (a) {
  TvItemAction.watch => 'Regarder',
  TvItemAction.resume => 'Reprendre',
  TvItemAction.fromStart => 'Depuis le début',
  TvItemAction.seen => 'Marquer comme vu',
  TvItemAction.removeResume => 'Retirer de Reprendre',
  TvItemAction.addFavorite => 'Ajouter aux favoris',
  TvItemAction.removeFavorite => 'Retirer des favoris',
  TvItemAction.addList => 'Ajouter à Ma liste',
  TvItemAction.removeList => 'Retirer de Ma liste',
  TvItemAction.openSeries => 'Voir la série',
};

IconData _icon(TvItemAction a) => switch (a) {
  TvItemAction.watch || TvItemAction.resume => Icons.play_arrow_rounded,
  TvItemAction.fromStart => Icons.replay_rounded,
  TvItemAction.seen => Icons.check_rounded,
  TvItemAction.removeResume => Icons.close_rounded,
  TvItemAction.addFavorite => Icons.favorite_border_rounded,
  TvItemAction.removeFavorite => Icons.favorite_rounded,
  TvItemAction.addList => Icons.add_rounded,
  TvItemAction.removeList => Icons.check_rounded,
  TvItemAction.openSeries => Icons.info_outline_rounded,
};

/// The favourite (channel) or Ma liste (film, series) state of [it].
(ContentKind, int, String)? _favoriteKey(TvItem it) => switch (it.ref) {
  final Channel c => (ContentKind.live, c.sourceId, c.extId),
  final Movie m => (ContentKind.movie, m.sourceId, m.extId),
  final Series sr => (ContentKind.series, sr.sourceId, sr.extId),
  _ => null,
};

/// OK held on [it]: its choices in a sheet, then what was chosen.
Future<void> showTvItemActions(BuildContext context, TvItem it) async {
  final s = AppScope.of(context);
  final key = _favoriteKey(it);
  final favorite = key != null && s.repo.isFavorite(key.$2, key.$1, key.$3);
  await showTvSheet(
    context,
    // A channel by its name (its card shows the programme on air).
    title: it.kind == TvItemKind.live ? (it.channelName ?? it.title) : it.title,
    subtitle: it.kind == TvItemKind.live ? it.title : (it.meta.isEmpty ? null : it.meta),
    sections: [
      TvSheetSection(null, [
        for (final a in tvItemActions(it, favorite: favorite))
          TvSheetOption(tvItemActionLabel(a), icon: _icon(a), onPick: () => _run(context, s, it, a)),
      ]),
    ],
  );
}

Future<void> _run(BuildContext context, AppServices s, TvItem it, TvItemAction a) async {
  final key = _favoriteKey(it);
  switch (a) {
    case TvItemAction.watch || TvItemAction.resume || TvItemAction.openSeries:
      await tvOpen(context, it);
    case TvItemAction.addFavorite || TvItemAction.removeFavorite || TvItemAction.addList || TvItemAction.removeList:
      if (key != null) s.toggleFavorite(key.$1, key.$3, key.$2);
    case TvItemAction.removeResume:
      if (it.ref case final ProgressEntry p) {
        s.repo.removeFromResume(p);
        s.library.userChanged();
      }
    case TvItemAction.seen:
      if (it.ref case final ProgressEntry p) {
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
      }
    case TvItemAction.fromStart:
      if (it.ref case final ProgressEntry p) await _fromStart(context, s, p);
  }
}

Future<void> _fromStart(BuildContext context, AppServices s, ProgressEntry p) async {
  if (p.kind != ContentKind.episode) {
    final m = s.repo.movieByExt(p.sourceId, p.extId);
    if (m != null) await Launch.movie(context, m, restart: true, image: p.image);
    return;
  }
  final series = p.seriesExt == null ? null : s.repo.seriesByExt(p.sourceId, p.seriesExt!);
  if (series == null) return;
  final all = await loadEpisodes(s.repo, series);
  final e = all.where((x) => x.extId == p.extId).firstOrNull;
  if (e != null && context.mounted) await Launch.episode(context, series, e, all, restart: true);
}
