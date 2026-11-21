import 'package:bobine/tv/tv_actions.dart';
import 'package:bobine/tv/tv_rows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TvItem item(TvItemKind kind, {double? progress}) =>
      TvItem(kind: kind, key: 'k', title: 'T', kicker: '', meta: '', ref: 'x', progress: progress);

  test('une chaîne : regarder, et l’ajouter ou la retirer des favoris', () {
    expect(tvItemActions(item(TvItemKind.live), favorite: false), [TvItemAction.watch, TvItemAction.addFavorite]);
    expect(tvItemActions(item(TvItemKind.live), favorite: true), [TvItemAction.watch, TvItemAction.removeFavorite]);
  });

  test('un film, une série : Ma liste', () {
    expect(tvItemActions(item(TvItemKind.movie), favorite: false), [TvItemAction.watch, TvItemAction.addList]);
    expect(tvItemActions(item(TvItemKind.series), favorite: true), [TvItemAction.openSeries, TvItemAction.removeList]);
  });

  test('une reprise : reprendre, depuis le début si commencée, vu, retirer', () {
    expect(tvItemActions(item(TvItemKind.resume, progress: 0.4), favorite: false), [
      TvItemAction.resume,
      TvItemAction.fromStart,
      TvItemAction.seen,
      TvItemAction.removeResume,
    ]);
    expect(tvItemActions(item(TvItemKind.resume), favorite: false), [
      TvItemAction.resume,
      TvItemAction.seen,
      TvItemAction.removeResume,
    ]);
  });

  test('les libellés', () {
    expect(tvItemActionLabel(TvItemAction.addFavorite), 'Ajouter aux favoris');
    expect(tvItemActionLabel(TvItemAction.removeResume), 'Retirer de Reprendre');
    expect(tvItemActionLabel(TvItemAction.addList), 'Ajouter à Ma liste');
  });
}
