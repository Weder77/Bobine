import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services.dart';
import '../ui/launch.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_rows.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

List<Episode> _ordered(List<Episode> eps) =>
    [...eps]..sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.episode.compareTo(b.episode));

/// Seasons of a series, in order.
List<int> tvSeasons(List<Episode> eps) => {for (final e in _ordered(eps)) e.season}.toList();

bool _done(ProgressEntry p) => p.finished || p.fraction >= 0.95;

/// The big button of a series page: the episode under way ("Reprendre"),
/// else the one after the last seen ("Lecture"), else the first one.
({Episode episode, String label}) tvSeriesPrimary(List<Episode> eps, Map<String, ProgressEntry> progress) {
  final list = _ordered(eps);
  final index = {for (final (i, e) in list.indexed) e.extId: i};
  final seen = progress.values.where((p) => index.containsKey(p.extId)).toList()
    ..sort((a, b) {
      final t = a.updatedAt.compareTo(b.updatedAt);
      return t != 0 ? t : index[a.extId]!.compareTo(index[b.extId]!);
    });
  if (seen.isNotEmpty) {
    final last = seen.last;
    final i = index[last.extId]!;
    if (!_done(last)) return (episode: list[i], label: 'Reprendre ${list[i].code}');
    if (i + 1 < list.length) return (episode: list[i + 1], label: 'Lecture ${list[i + 1].code}');
  }
  return (episode: list.first, label: 'Lecture ${list.first.code}');
}

/// Page of a series on the TV: its picture and words, Reprendre / Ma liste,
/// the seasons, then the episodes of the chosen season (big pictures).
class TvSeriesScreen extends StatefulWidget {
  const TvSeriesScreen({super.key, required this.series});
  final Series series;

  static Future<void> open(BuildContext context, Series series) async {
    if (AppScope.of(context).repo.isLocked(series.sourceId, ContentKind.series, series.extId)) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => TvSeriesScreen(series: series),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<TvSeriesScreen> createState() => _TvSeriesScreenState();
}

class _TvSeriesScreenState extends State<TvSeriesScreen> {
  final _c = TvFocusController(initial: 'play');
  List<Episode>? _eps;
  Map<String, ProgressEntry> _progress = const {};
  int? _season;

  Series get _sr => widget.series;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onFocus);
    // Down from the buttons and the seasons lands on the episode in view.
    _c.before = (from, dir) {
      String? known(String? id) => id != null && _c.isRegistered(id) ? id : null;
      final season = known('season-$_season');
      if (dir == TvDir.down && (from == 'play' || from == 'list')) return season;
      if (dir == TvDir.down && (from?.startsWith('season-') ?? false)) return known(_firstEpisodeId());
      if (dir == TvDir.up && (from?.startsWith('ep-') ?? false)) return season;
      if (dir == TvDir.up && (from?.startsWith('season-') ?? false)) return 'play';
      return null;
    };
    _load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? _firstEpisodeId() {
    final eps = _inSeason;
    if (eps.isEmpty) return null;
    final primary = _primary;
    final shown = primary != null && primary.episode.season == _season ? primary.episode : eps.first;
    return 'ep-${shown.extId}';
  }

  void _onFocus() {
    final id = _c.id;
    if (id != null && id.startsWith('season-')) {
      final n = int.tryParse(id.substring(7));
      if (n != null && n != _season) setState(() => _season = n);
    }
  }

  Future<void> _load() async {
    final s = AppScope.of(context);
    final eps = await loadEpisodes(s.repo, _sr);
    if (!mounted) return;
    _refresh(eps);
  }

  void _refresh([List<Episode>? eps]) {
    final s = AppScope.of(context);
    final list = eps ?? _eps ?? const <Episode>[];
    setState(() {
      _eps = list;
      _progress = s.repo.seriesProgress(_sr.sourceId, _sr.extId);
      if (list.isNotEmpty) _season ??= tvSeriesPrimary(list, _progress).episode.season;
    });
  }

  ({Episode episode, String label})? get _primary {
    final eps = _eps;
    return eps == null || eps.isEmpty ? null : tvSeriesPrimary(eps, _progress);
  }

  List<Episode> get _inSeason => [
    for (final e in _ordered(_eps ?? const []))
      if (e.season == _season) e,
  ];

  Future<void> _play(Episode e) async {
    await Launch.episode(context, _sr, e, _eps ?? [e]);
    if (mounted) _refresh();
  }

  Widget _button(String id, IconData icon, String label, VoidCallback onOk, {bool strong = false}) => TvFocusable(
    id: id,
    onOk: onOk,
    builder: (context, on) => AnimatedScale(
      scale: on ? 1.05 : 1,
      duration: const Duration(milliseconds: 150),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 76,
        padding: EdgeInsets.only(left: strong ? 32 : 28, right: strong ? 42 : 36),
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0x29FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: on ? TvColors.bg : Colors.white),
            const SizedBox(width: 14),
            Text(
              label,
              style: tvText(
                30,
                weight: strong ? FontWeight.w700 : FontWeight.w600,
                height: 1,
                color: on ? TvColors.bg : Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _seasonPill(int n) => TvFocusable(
    id: 'season-$n',
    onOk: () => _c.focus(_firstEpisodeId(), dir: TvDir.down),
    revealAxes: const {Axis.horizontal},
    builder: (context, on) {
      final current = n == _season;
      return AnimatedScale(
        scale: on ? 1.05 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? Colors.white
                : current
                ? const Color(0x24FFFFFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: on || current ? Colors.transparent : TvColors.border, width: 2),
          ),
          child: Text(
            'Saison $n',
            style: tvText(
              24,
              weight: FontWeight.w600,
              height: 1,
              color: on
                  ? TvColors.bg
                  : current
                  ? Colors.white
                  : TvColors.muted,
            ),
          ),
        ),
      );
    },
  );

  Widget _episode(Episode e) {
    final p = _progress[e.extId];
    final seen = p != null && _done(p);
    final dur = e.durationSec == null ? null : tvDuration(Duration(seconds: e.durationSec!));
    final item = TvItem(
      kind: TvItemKind.resume,
      key: 'e-${e.extId}',
      title: 'E${e.episode.toString().padLeft(2, '0')} · ${e.title ?? 'Épisode ${e.episode}'}',
      kicker: '',
      meta: '',
      image: e.image ?? _sr.backdrop ?? _sr.poster,
      progress: p == null || seen ? null : p.fraction,
      ref: e,
    );
    return TvFocusable(
      id: 'ep-${e.extId}',
      onOk: () => _play(e),
      revealAxes: const {Axis.horizontal},
      builder: (context, on) => Stack(
        clipBehavior: Clip.none,
        children: [
          TvWideCard(item: item, on: on),
          Positioned(
            right: 14,
            top: 14,
            child: Row(
              children: [
                if (dur != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xCC0D0C0B), borderRadius: BorderRadius.circular(8)),
                    child: Text(dur, style: tvMono(22)),
                  ),
                if (seen) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: TvColors.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 22, color: TvColors.accentInk),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final eps = _eps;
    final primary = _primary;
    final inList = s.repo.isFavorite(_sr.sourceId, ContentKind.series, _sr.extId);
    final seasons = eps == null ? const <int>[] : tvSeasons(eps);
    final meta = [
      if ((_sr.rating ?? 0) > 0) '★ ${_sr.rating!.toStringAsFixed(1).replaceAll('.', ',')}',
      ?_sr.year?.toString(),
      ?_sr.genre,
      if (seasons.isNotEmpty) seasons.length == 1 ? '1 saison' : '${seasons.length} saisons',
    ].join('   ·   ');
    return PopScope(
      canPop: true,
      child: TvStage(
        child: Material(
          color: TvColors.bg,
          child: TvFocusScope(
            controller: _c,
            onBack: () => Navigator.of(context).maybePop(),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 1920,
                  height: 900,
                  child: TvPicture(url: _sr.backdrop ?? _sr.poster, tintKey: 's-${_sr.extId}', decodeWidth: 1280),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D0C0B), Color(0xEB0D0C0B), Color(0x730D0C0B), Color(0x000D0C0B)],
                          stops: [0, 0.30, 0.54, 0.74],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xFF0D0C0B), Color(0xF20D0C0B), Color(0x000D0C0B)],
                          stops: [0, 0.42, 0.75],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 96,
                  bottom: 470,
                  width: 1100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('SÉRIE', style: tvKicker()),
                      const SizedBox(height: 20),
                      Text(
                        _sr.name.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tvTitle(tvTitleSize(_sr.name, 116), height: 0.88),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(meta, style: tvText(26, color: TvColors.soft)),
                      ],
                      if (_sr.plot != null && _sr.plot!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 860,
                          child: Text(
                            _sr.plot!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tvText(26, weight: FontWeight.w400, height: 1.45, color: TvColors.soft),
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          _button(
                            'play',
                            Icons.play_arrow_rounded,
                            primary?.label ?? 'Chargement…',
                            () => primary == null ? null : _play(primary.episode),
                            strong: true,
                          ),
                          const SizedBox(width: 18),
                          _button(
                            'list',
                            inList ? Icons.check_rounded : Icons.add_rounded,
                            inList ? 'Dans ma liste' : 'Ma liste',
                            () => setState(() => s.toggleFavorite(ContentKind.series, _sr.extId, _sr.sourceId)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 640,
                  height: 64,
                  child: eps == null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 96),
                          child: Text('Chargement des épisodes…', style: tvText(26, color: TvColors.muted)),
                        )
                      : eps.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 96),
                          child: Text('Aucun épisode chez le fournisseur.', style: tvText(26, color: TvColors.muted)),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 96),
                          itemCount: seasons.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => Center(child: _seasonPill(seasons[i])),
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 720,
                  height: 300,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(96, 22, 96, 30),
                    itemCount: _inSeason.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 24),
                    itemBuilder: (context, i) => _episode(_inSeason[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
