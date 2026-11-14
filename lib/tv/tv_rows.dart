import '../data/epg_cache.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'tv_shell.dart';

/// What an item of a row is, for what OK does.
enum TvItemKind { live, movie, series, resume }

/// One picture of a row, with what the top of the page shows when it is
/// selected.
class TvItem {
  const TvItem({
    required this.kind,
    required this.key,
    required this.title,
    required this.kicker,
    required this.meta,
    required this.ref,
    this.image,
    this.backdrop,
    this.synopsis,
    this.progress,
    this.progressLabel,
    this.number,
    this.end,
    this.channelName,
    this.channelNumber,
    this.channels,
  });

  final TvItemKind kind;

  /// Stable key of the content (pictures, colours).
  final String key;
  final String title;
  final String kicker;
  final String meta;
  final String? image;
  final String? backdrop;
  final String? synopsis;

  /// Watched part (0 → 1) or part of the programme gone (live).
  final double? progress;
  final String? progressLabel;

  /// Rank in a Top 10 ("1"…"10").
  final String? number;

  /// Live: end of the programme on air ("23:00").
  final String? end;
  final String? channelName;
  final int? channelNumber;

  /// Live: the channels to zap through from this one.
  final List<Channel>? channels;

  /// The [Movie], [Series], [Channel] or [ProgressEntry] behind it.
  final Object ref;
}

enum TvRowStyle { live, wide, top, poster }

class TvRow {
  const TvRow(this.title, this.style, this.items, {this.all});
  final String title;
  final TvRowStyle style;
  final List<TvItem> items;

  /// The row shows only the first items: all of them ("Voir tout").
  final List<TvItem> Function()? all;
}

/// A pill above Films or Séries: À la une (the rows), Tout, a category.
class TvPill {
  const TvPill(this.id, this.label);
  final String id;
  final String label;
}

/// À la une, Tout, then the provider's categories (those the parental
/// control hides are left out, as everywhere on the TV).
List<TvPill> tvCatalogPills(Repository repo, int sourceId, TvTab tab) {
  final kind = switch (tab) {
    TvTab.films => ContentKind.movie,
    TvTab.series => ContentKind.series,
    _ => null,
  };
  if (kind == null) return const [];
  return [
    const TvPill('une', 'À la une'),
    const TvPill('all', 'Tout'),
    for (final c in repo.categories(sourceId, kind)) TvPill('c:${c.id}', c.name),
  ];
}

/// Everything a pill holds: all the films or series, or a category's.
List<TvItem> tvCatalogItems(Repository repo, int sourceId, TvTab tab, String pill) {
  final category = pill.startsWith('c:') ? int.tryParse(pill.substring(2)) : null;
  final label = category == null ? null : repo.categoryName(category);
  if (tab == TvTab.series) {
    return [for (final x in repo.series(sourceId, categoryId: category)) tvSeries(x, 'Série · ${label ?? 'Tout'}')];
  }
  return [for (final m in repo.movies(sourceId, categoryId: category)) tvMovie(m, 'Film · ${label ?? 'Tout'}')];
}

/// "1 h 10" or "25 min" (design's durations).
String tvDuration(Duration d) {
  final m = d.inMinutes < 0 ? 0 : d.inMinutes;
  return m >= 60 ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}' : '$m min';
}

String tvClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _rating(double? r) => r == null || r <= 0 ? '' : '★ ${r.toStringAsFixed(1).replaceAll('.', ',')}';

String _meta(List<String?> parts) => parts.where((p) => p != null && p.isNotEmpty).join('   ·   ');

TvItem tvMovie(Movie m, String kicker, {String? number}) => TvItem(
  kind: TvItemKind.movie,
  key: 'm-${m.extId}',
  title: m.name,
  kicker: kicker,
  meta: _meta([_rating(m.rating), m.year?.toString()]),
  image: m.poster,
  backdrop: m.poster,
  number: number,
  ref: m,
);

TvItem tvSeries(Series s, String kicker, {String? number}) => TvItem(
  kind: TvItemKind.series,
  key: 's-${s.extId}',
  title: s.name,
  kicker: kicker,
  meta: _meta([_rating(s.rating), s.year?.toString(), s.genre]),
  image: s.poster,
  backdrop: s.backdrop ?? s.poster,
  synopsis: s.plot,
  number: number,
  ref: s,
);

TvItem tvChannel(Channel c, EpgCache epg, String name, DateTime now, List<Channel> list) {
  final p = epg.now(c);
  final left = p?.stop.difference(now);
  return TvItem(
    kind: TvItemKind.live,
    key: 'c-${c.extId}',
    title: p?.title ?? name,
    kicker: 'En direct · $name',
    meta: _meta([p?.category, if (p != null) '${tvClock(p.start)} – ${tvClock(p.stop)}']),
    synopsis: p?.description,
    image: c.logo,
    progress: p?.progressAt(now),
    progressLabel: left == null ? null : 'reste ${tvDuration(left)}',
    end: p == null ? null : tvClock(p.stop),
    channelName: name,
    channelNumber: c.number,
    channels: list,
    ref: c,
  );
}

TvItem tvResume(ProgressEntry p) {
  final total = p.duration.inSeconds;
  final fraction = total <= 0 ? 0.0 : (p.position.inSeconds / total).clamp(0.0, 1.0);
  final episode = p.kind == ContentKind.episode;
  return TvItem(
    kind: TvItemKind.resume,
    key: episode ? 's-${p.seriesExt}' : 'm-${p.extId}',
    title: p.title,
    kicker: 'Reprendre · ${episode ? (p.subtitle ?? 'Épisode') : 'Film'}',
    meta: '',
    image: p.image,
    backdrop: p.image,
    progress: fraction,
    progressLabel: 'reste ${tvDuration(p.duration - p.position)}',
    ref: p,
  );
}

/// The rows of Accueil, Films or Séries: only what is there (an empty row
/// is left out), only what the parental control lets through (the lists
/// of [repo] already leave locked categories out).
List<TvRow> tvRows({
  required Repository repo,
  required EpgCache epg,
  required int sourceId,
  required TvTab tab,
  required String Function(Channel) name,
  DateTime? now,
  int rowLimit = 20,
}) {
  final t = now ?? DateTime.now();
  final rows = <TvRow>[];
  void add(String title, TvRowStyle style, List<TvItem> items) {
    if (items.isNotEmpty) rows.add(TvRow(title, style, items));
  }

  // A row of the first [rowLimit] only, and all of them behind "Voir tout"
  // when there are more ([load] gets the limit, or null for all).
  void addCut(String title, List<TvItem> Function(int? limit) load) {
    final items = load(rowLimit + 1);
    if (items.isEmpty) return;
    final cut = items.length > rowLimit;
    rows.add(
      TvRow(title, TvRowStyle.poster, cut ? items.take(rowLimit).toList() : items, all: cut ? () => load(null) : null),
    );
  }

  List<T> top10<T>(List<T> recent, double? Function(T) rating) {
    final sorted = [...recent]..sort((a, b) => (rating(b) ?? 0).compareTo(rating(a) ?? 0));
    return sorted.take(10).toList();
  }

  switch (tab) {
    case TvTab.home:
      final favs = repo.favoriteChannels(sourceId);
      final live = favs.isNotEmpty ? favs : repo.channels(sourceId, limit: 12);
      add('En direct maintenant', TvRowStyle.live, [for (final c in live) tvChannel(c, epg, name(c), t, live)]);
      add('Reprendre', TvRowStyle.wide, [for (final p in repo.continueWatching(sourceId, limit: 12)) tvResume(p)]);
      final trending = repo.trending(sourceId);
      add('Top 10 aujourd’hui', TvRowStyle.top, [
        for (final (i, x) in trending.indexed)
          if (x is Movie)
            tvMovie(x, 'N° ${i + 1} · Top 10 aujourd’hui', number: '${i + 1}')
          else if (x is Series)
            tvSeries(x, 'N° ${i + 1} · Top 10 aujourd’hui', number: '${i + 1}'),
      ]);
      addCut(
        'Ajoutés récemment',
        (n) => [
          for (final m in repo.movies(sourceId, sort: CatalogSort.added, limit: n)) tvMovie(m, 'Film · Nouveauté'),
        ],
      );
    case TvTab.films:
      addCut(
        'Nouveautés',
        (n) => [
          for (final m in repo.movies(sourceId, sort: CatalogSort.added, limit: n)) tvMovie(m, 'Film · Nouveauté'),
        ],
      );
      add('Ma liste', TvRowStyle.poster, [
        for (final m in repo.favoriteMovies(sourceId)) tvMovie(m, 'Film · Ma liste'),
      ]);
      final top = top10(repo.movies(sourceId, sort: CatalogSort.added, limit: 160), (Movie m) => m.rating);
      add('Top 10 des films', TvRowStyle.top, [
        for (final (i, m) in top.indexed) tvMovie(m, 'N° ${i + 1} · Top 10 des films', number: '${i + 1}'),
      ]);
      for (final c in repo.categories(sourceId, ContentKind.movie).take(4)) {
        addCut(
          c.name,
          (n) => [for (final m in repo.movies(sourceId, categoryId: c.id, limit: n)) tvMovie(m, 'Film · ${c.name}')],
        );
      }
      addCut(
        'Les mieux notés',
        (n) => [
          for (final m in repo.movies(sourceId, sort: CatalogSort.rating, limit: n))
            if ((m.rating ?? 0) > 0) tvMovie(m, 'Film · Les mieux notés'),
        ],
      );
    case TvTab.series:
      add('Reprendre tes séries', TvRowStyle.wide, [
        for (final p in repo.continueWatching(sourceId, limit: 12, kind: ContentKind.episode)) tvResume(p),
      ]);
      addCut(
        'Nouveautés',
        (n) => [
          for (final s in repo.series(sourceId, sort: CatalogSort.added, limit: n)) tvSeries(s, 'Série · Nouveauté'),
        ],
      );
      add('Ma liste', TvRowStyle.poster, [
        for (final s in repo.favoriteSeries(sourceId)) tvSeries(s, 'Série · Ma liste'),
      ]);
      final top = top10(repo.series(sourceId, sort: CatalogSort.added, limit: 80), (Series s) => s.rating);
      add('Top 10 des séries', TvRowStyle.top, [
        for (final (i, s) in top.indexed) tvSeries(s, 'N° ${i + 1} · Top 10 des séries', number: '${i + 1}'),
      ]);
      for (final c in repo.categories(sourceId, ContentKind.series).take(4)) {
        addCut(
          c.name,
          (n) => [for (final s in repo.series(sourceId, categoryId: c.id, limit: n)) tvSeries(s, 'Série · ${c.name}')],
        );
      }
    default:
      break;
  }
  return rows;
}
