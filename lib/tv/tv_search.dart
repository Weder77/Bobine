import 'dart:async';

import 'package:flutter/material.dart';

import '../data/epg_cache.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/search_worker.dart';
import '../services.dart';
import 'tv_actions.dart';
import 'tv_browse.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_form.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

/// Results of each kind shown by Recherche.
const _limit = 40;

/// What [query] finds: channels, films, series, each in a row (empty rows
/// left out). Under two letters, nothing: not the whole catalogue.
List<TvRow> tvSearchRows({
  required Repository repo,
  required EpgCache epg,
  required int sourceId,
  required String query,
  required String Function(Channel) name,
}) {
  if (query.trim().length < 2) return const [];
  return tvSearchRowsOf(
    repo.search(sourceId, query, limit: _limit),
    epg: epg,
    name: name,
  );
}

/// The rows of what a search found ([tvSearchRows]).
List<TvRow> tvSearchRowsOf(SearchResults r, {required EpgCache epg, required String Function(Channel) name}) {
  final now = DateTime.now();
  return [
    if (r.channels.isNotEmpty)
      TvRow('Chaînes', TvRowStyle.live, [for (final c in r.channels) tvChannel(c, epg, name(c), now, r.channels)]),
    if (r.movies.isNotEmpty) TvRow('Films', TvRowStyle.poster, [for (final m in r.movies) tvMovie(m, 'Film')]),
    if (r.series.isNotEmpty) TvRow('Séries', TvRowStyle.poster, [for (final x in r.series) tvSeries(x, 'Série')]),
  ];
}

/// Recherche: a field (OK opens the TV's keyboard, which can also listen),
/// the results as you type, in rows.
class TvSearchPage extends StatefulWidget {
  const TvSearchPage({super.key, required this.setEntry});
  final void Function(String? Function()) setEntry;

  @override
  State<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends State<TvSearchPage> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  TvFocusController? _c;
  Timer? _debounce;
  List<TvRow> _rows = const [];

  /// Last card with the remote in each row: Up and Down land there.
  final Map<String, String> _last = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = TvFocusScope.maybeOf(context);
    if (c != _c) {
      _c?.removeListener(_onFocus);
      _c = c?..addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c?.removeListener(_onFocus);
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() {
    final id = _c?.id;
    if (id == null || !id.startsWith('s:')) return;
    final title = id.substring(2, id.indexOf(':', 2));
    _last[title] = id;
  }

  /// Results a moment after the last letter (the TV's keyboard sends one
  /// letter at a time).
  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(_search()));
  }

  /// The latest search: an older one finishing after it is not shown.
  int _run = 0;

  /// Searched on another isolate: a big catalogue takes a moment, and the
  /// TV must not freeze while the letters come.
  Future<void> _search() async {
    if (!mounted) return;
    final s = AppScope.of(context);
    final source = s.activeSource;
    final query = _query.text.trim();
    final run = ++_run;
    SearchResults? found;
    if (source != null && query.length >= 2) {
      try {
        found = (await searchInBackground(
          s.dbPath,
          sourceId: source.id,
          query: query,
          profileId: s.repo.profileId,
          hideLocked: s.repo.hideLocked,
          limit: _limit,
          programs: false,
        )).results;
      } catch (e) {
        // No second connection (unusual): search here.
        debugPrint('Recherche en arrière-plan impossible : $e');
        found = s.repo.search(source.id, query, limit: _limit);
      }
    }
    if (!mounted || run != _run) return;
    setState(() {
      _rows = found == null ? const [] : tvSearchRowsOf(found, epg: s.epg, name: s.channelName);
      _last.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _id(TvRow row, TvItem it) => 's:${row.title}:${it.key}';

  String? _rowTarget(int ri) {
    final row = _rows[ri];
    final last = _last[row.title];
    if (last != null && (_c?.isRegistered(last) ?? false)) return last;
    return row.items.isEmpty ? null : _id(row, row.items.first);
  }

  String? _moveFrom(int ri, TvDir d) => switch (d) {
    TvDir.up => ri == 0 ? 'q' : _rowTarget(ri - 1),
    TvDir.down => ri + 1 < _rows.length ? _rowTarget(ri + 1) : null,
    _ => null,
  };

  Widget _card(int ri, TvRow row, TvItem it) => TvFocusable(
    id: _id(row, it),
    onOk: () => tvOpen(context, it),
    onLongOk: () => showTvItemActions(context, it),
    onMove: (d) => _moveFrom(ri, d),
    builder: (context, on) =>
        row.style == TvRowStyle.live ? TvLiveCard(item: it, on: on) : TvPosterCard(item: it, on: on),
  );

  Widget _rowView(int ri, TvRow row) => SizedBox(
    height: 30 + 22 + (row.style == TvRowStyle.live ? 225 : 300) + 30,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 96),
          child: Text(row.title, style: tvText(30, weight: FontWeight.w600, height: 1)),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(96, 22, 96, 30),
            itemCount: row.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 24),
            itemBuilder: (context, i) => _card(ri, row, row.items[i]),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    widget.setEntry(() => 'q');
    final q = _query.text.trim();
    final message = q.length < 2
        ? 'Le nom d’une chaîne, d’un film ou d’une série. OK sur le champ ouvre le clavier.'
        : _rows.isEmpty
        ? 'Rien pour « $q ».'
        : null;
    return Stack(
      children: [
        Positioned(left: 96, top: 158, child: Text('RECHERCHE', style: tvTitle(84))),
        Positioned(
          left: 96,
          top: 270,
          width: 1040,
          child: TvTextField(
            id: 'q',
            label: 'Rechercher',
            hint: 'Une chaîne, un film, une série…',
            controller: _query,
            onChanged: _changed,
            onDone: (_) => _search(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 430,
          bottom: 0,
          child: message != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(96, 10, 600, 0),
                  child: Text(message, style: tvText(28, color: TvColors.muted, height: 1.4)),
                )
              : SingleChildScrollView(
                  controller: _scroll,
                  physics: const NeverScrollableScrollPhysics(),
                  // Scrolled rows go under the field, not over it.
                  clipBehavior: Clip.hardEdge,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (ri, row) in _rows.indexed) ...[
                          if (ri > 0) const SizedBox(height: 22),
                          _rowView(ri, row),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
