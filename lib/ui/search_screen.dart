import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/search_worker.dart';
import '../services.dart';
import 'launch.dart';
import 'program_actions.dart';
import 'quick_actions.dart';
import 'shell.dart';
import 'widgets/cards.dart';
import 'widgets/common.dart';
import 'widgets/rows.dart';

/// Search layer under the header (its field is the header's): recent
/// searches and trends while empty, then films and series first, channels,
/// and the first TV programmes (the others on demand).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.controller, required this.onClose});
  final TextEditingController controller;
  final VoidCallback onClose;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final AppServices _s = AppScope.of(context);
  Timer? _debounce;
  SearchResults? _results;
  List<ProgramHit> _programs = const [];
  String _query = '';

  /// Query waiting for the search in progress to end (the latest wins).
  String? _pending;
  bool _searching = false;

  /// "Tendances" of the empty page, worked out once (it reads the catalogue).
  List<Object>? _trends;

  /// What the results were made for: when it changes (an import, another
  /// source, categories locked again, another profile), they are made
  /// again. Results locked since, or of another source, stayed on screen.
  (int, int?, bool, int)? _madeFor;
  (int, int?, bool, int) get _context =>
      (_s.library.content, _s.activeSource?.id, _s.repo.hideLocked, _s.repo.profileId);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _s.library.addListener(_onLibrary);
    _madeFor = _context;
    _run(widget.controller.text);
  }

  void _onLibrary() {
    if (!mounted || _context == _madeFor) return;
    _madeFor = _context;
    _trends = null;
    _run(widget.controller.text);
  }

  @override
  void dispose() {
    _s.library.removeListener(_onLibrary);
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(widget.controller.text));
  }

  /// Searches [q]. The database is read on another isolate, one search at a
  /// time: what is typed meanwhile replaces the query that waits.
  void _run(String q) {
    if (!mounted) return;
    final src = _s.activeSource;
    final t = q.trim();
    if (src == null || t.length < 2) {
      _pending = null;
      setState(() {
        _query = t;
        _results = null;
        _programs = const [];
      });
      return;
    }
    _pending = t;
    if (!_searching) unawaited(_drain());
  }

  Future<void> _drain() async {
    _searching = true;
    try {
      while (mounted) {
        final t = _pending;
        final src = _s.activeSource;
        if (t == null || src == null) break;
        _pending = null;
        SearchOutcome out;
        try {
          out = await searchInBackground(
            _s.dbPath,
            sourceId: src.id,
            query: t,
            profileId: _s.repo.profileId,
            hideLocked: _s.repo.hideLocked,
          );
        } catch (e) {
          // No second connection (unusual): search here.
          debugPrint('Recherche en arrière-plan impossible : $e');
          out = runSearch(_s.repo, src.id, t);
        }
        // Something else was typed, or the field was emptied, meanwhile.
        if (!mounted || _pending != null || widget.controller.text.trim() != t) continue;
        setState(() {
          _query = t;
          _results = out.results;
          _programs = out.programs;
        });
      }
    } finally {
      _searching = false;
    }
  }

  /// Opening a result remembers the query.
  void _remember() => _s.repo.addRecentSearch(_query);

  @override
  Widget build(BuildContext context) {
    final r = _results;
    final total = (r?.channels.length ?? 0) + _programs.length + (r?.movies.length ?? 0) + (r?.series.length ?? 0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 96),
      children: [if (r == null) ..._empty() else if (total == 0) _none() else ..._found(r, total)],
    );
  }

  // ---------------------------------------------------------------- empty

  List<Widget> _empty() {
    final src = _s.activeSource;
    final recent = _s.repo.recentSearches();
    final trends = src == null ? const <Object>[] : (_trends ??= _s.repo.trending(src.id));
    return [
      if (recent.isNotEmpty) ...[
        Text('RECHERCHES RÉCENTES', style: monoStyle(13, color: AppColors.faint).copyWith(letterSpacing: 0.8)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in recent)
              _Chip(
                label: q,
                onTap: () {
                  widget.controller.text = q;
                  widget.controller.selection = TextSelection.collapsed(offset: q.length);
                },
              ),
          ],
        ),
        const SizedBox(height: 44),
      ],
      if (trends.isNotEmpty) ...[
        Text('TENDANCES', style: posterStyle(34, height: 1)),
        const SizedBox(height: 14),
        AutoGrid(
          minWidth: 320,
          spacing: 32,
          runSpacing: 4,
          children: [for (var i = 0; i < trends.length; i++) _TrendRow(rank: i + 1, item: trends[i])],
        ),
      ],
    ];
  }

  // ---------------------------------------------------------------- results

  Widget _none() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 96),
    child: Column(
      children: [
        Text(
          'AUCUN RÉSULTAT POUR « ${_query.toUpperCase()} »',
          textAlign: TextAlign.center,
          style: posterStyle(40, height: 1),
        ),
        const SizedBox(height: 12),
        Text(
          'Essaie un titre, une chaîne ou un programme TV.',
          style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.faint),
        ),
      ],
    ),
  );

  List<Widget> _found(SearchResults r, int total) {
    final now = DateTime.now();
    return [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 16,
        children: [
          Text('« ${_query.toUpperCase()} »', style: posterStyle(56, height: 0.9)),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('$total résultat${total > 1 ? 's' : ''}', style: monoStyle(15)),
          ),
        ],
      ),
      if (r.movies.isNotEmpty) ...[
        const SizedBox(height: 44),
        _title('Films'),
        const SizedBox(height: 16),
        AutoGrid(
          minWidth: 160,
          children: [
            for (final m in r.movies.take(60))
              PosterTile(
                title: m.name,
                image: m.poster,
                year: m.year,
                rating: m.rating,
                // The detail first (as everywhere else): the film did not
                // start at once from a search result.
                onTap: () {
                  _remember();
                  Launch.openMovie(context, m);
                },
                onContextMenu: (at) => showMovieActions(context, m, at),
              ),
          ],
        ),
      ],
      if (r.series.isNotEmpty) ...[
        const SizedBox(height: 44),
        _title('Séries'),
        const SizedBox(height: 16),
        AutoGrid(
          minWidth: 160,
          children: [
            for (final sr in r.series.take(60))
              PosterTile(
                title: sr.name,
                image: sr.poster,
                year: sr.year,
                rating: sr.rating,
                onTap: () {
                  _remember();
                  Launch.openSeries(context, sr);
                },
                onContextMenu: (at) => showSeriesActions(context, sr, at),
              ),
          ],
        ),
      ],
      if (r.channels.isNotEmpty) ...[
        const SizedBox(height: 44),
        _title('Chaînes'),
        const SizedBox(height: 14),
        AutoGrid(
          minWidth: 280,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in r.channels.take(24))
              _ChannelResult(
                channel: c,
                onTap: () {
                  _remember();
                  Launch.channel(context, c, r.channels);
                },
              ),
          ],
        ),
      ],
      if (_programs.isNotEmpty) ...[
        const SizedBox(height: 44),
        _title('Programmes TV'),
        const SizedBox(height: 14),
        // Five first: films and series matter more, and the guide can hold
        // dozens of airings of a title.
        FoldedList(
          key: ValueKey(_query),
          moreLabel: 'Tout voir · ${_programs.length} programmes',
          children: [for (final h in _programs) _ProgramRow(hit: h, now: now, onOpen: () => _openProgram(h, now))],
        ),
      ],
    ];
  }

  Widget _title(String t) => Text(t, style: displayStyle(20, weight: FontWeight.w600, height: 1));

  /// On air: watch. Past with replay: watch again. Otherwise: the guide,
  /// positioned on the programme.
  void _openProgram(ProgramHit h, DateTime now) {
    _remember();
    final c = h.channel;
    final p = h.program;
    if (p.isLiveAt(now)) {
      Launch.channel(context, c, [c]);
    } else if (canReplay(c, p, now)) {
      Launch.replay(context, c, p);
    } else {
      _s.guideFocus.value = (c, p);
      widget.onClose();
      ShellNavigation.of(context)?.goTo(ShellTab.guide);
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 999,
    builder: (context, hover) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: hover ? AppColors.text : AppColors.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: hover ? AppColors.text : AppColors.textSoft),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, height: 1, color: hover ? AppColors.text : AppColors.textSoft)),
          ],
        ),
      ),
    ),
  );
}

/// One of the ten trends: outlined rank, small poster, title, kind · year.
class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.rank, required this.item});
  final int rank;
  final Object item;

  @override
  Widget build(BuildContext context) {
    final m = item is Movie ? item as Movie : null;
    final sr = item is Series ? item as Series : null;
    final title = m?.name ?? sr!.name;
    final year = m?.year ?? sr?.year;
    void open() => m != null ? Launch.openMovie(context, m) : Launch.openSeries(context, sr!);
    return HoverBuilder(
      onActivate: open,
      onContextMenu: (at) => m != null ? showMovieActions(context, m, at) : showSeriesActions(context, sr!, at),
      builder: (context, hover) => GestureDetector(
        onTap: open,
        onSecondaryTapUp: (d) => m != null
            ? showMovieActions(context, m, d.globalPosition)
            : showSeriesActions(context, sr!, d.globalPosition),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: hover ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(width: 44, child: Center(child: OutlinedDigits('$rank', size: 40))),
              const SizedBox(width: 14),
              Container(
                width: 52,
                height: 78,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(6)),
                clipBehavior: Clip.antiAlias,
                child: Artwork(url: m?.poster ?? sr?.poster, label: '', decodeWidth: 104),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 7),
                    Text([m != null ? 'Film' : 'Série', if (year != null) '$year'].join(' · '), style: monoStyle(12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Number drawn as an outline (Top 10, trends): the fill is the background.
class OutlinedDigits extends StatelessWidget {
  const OutlinedDigits(this.text, {super.key, required this.size, this.stroke = 1.5, this.color});
  final String text;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Text(
        text,
        style: posterStyle(size, height: 1).copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2
            ..color = color ?? AppColors.placeholder,
        ),
      ),
      Text(text, style: posterStyle(size, height: 1, color: AppColors.bg)),
    ],
  );
}

/// Channel found: badge, name, number and times, "● DIRECT", programme.
class _ChannelResult extends StatelessWidget {
  const _ChannelResult({required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = channel;
    final p = s.epg.now(c);
    final now = DateTime.now();
    return HoverBuilder(
      onActivate: onTap,
      onContextMenu: (at) => showChannelActions(context, c, [c], at),
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (d) => showChannelActions(context, c, [c], d.globalPosition),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hover ? AppColors.accent : AppColors.borderInput),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ChannelLogo(name: AppScope.of(context).channelName(c), url: c.logo, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppScope.of(context).channelName(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [
                            if (c.number != null) 'Chaîne ${c.number}',
                            if (p != null) '${formatClock(p.start)} – ${formatClock(p.stop)}',
                          ].join(' · '),
                          maxLines: 1,
                          style: monoStyle(12),
                        ),
                      ],
                    ),
                  ),
                  const LiveDot(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                p?.title ?? 'Pas de programme',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: p == null ? AppColors.faint : AppColors.text,
                ),
              ),
              const SizedBox(height: 12),
              ProgressLine(p?.progressAt(now) ?? 0, height: 3, track: AppColors.ink.withAlpha(0x24)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "● DIRECT" with a pulsing dot.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.label = 'DIRECT'});
  final String label;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value < 0.5 ? _c.value * 2 : (1 - _c.value) * 2;
          return Opacity(
            opacity: 1 - 0.65 * t,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            ),
          );
        },
      ),
      const SizedBox(width: 6),
      Text(
        widget.label,
        style: monoStyle(11, weight: FontWeight.w600, color: AppColors.accent),
      ),
    ],
  );
}

/// TV programme found: times, channel, title, status and action.
class _ProgramRow extends StatelessWidget {
  const _ProgramRow({required this.hit, required this.now, required this.onOpen});
  final ProgramHit hit;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = hit.channel;
    final p = hit.program;
    final live = p.isLiveAt(now);
    final past = !p.stop.isAfter(now);
    final replay = past && canReplay(c, p, now);
    final sameDay = p.start.year == now.year && p.start.month == now.month && p.start.day == now.day;
    final (label, ink) = live
        ? ('EN COURS', AppColors.accent)
        : past
        ? ('TERMINÉ', AppColors.faint)
        : sameDay
        ? (p.start.hour >= 18 ? 'CE SOIR' : 'AUJOURD\'HUI', AppColors.faint)
        : (formatDay(p.start).toUpperCase(), AppColors.faint);
    final action = live ? 'Regarder' : (replay ? 'Revoir' : 'Voir dans le guide');
    return HoverBuilder(
      onActivate: onOpen,
      builder: (context, hover) => GestureDetector(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: hover ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  '${formatClock(p.start)} – ${formatClock(p.stop)}',
                  style: monoStyle(13, color: AppColors.textSoft),
                ),
              ),
              const SizedBox(width: 16),
              ChannelLogo(name: AppScope.of(context).channelName(c), url: c.logo, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [AppScope.of(context).channelName(c), if (p.category != null) p.category!].join(' · '),
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, height: 1, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: monoStyle(12, weight: FontWeight.w600, color: ink).copyWith(letterSpacing: 0.5),
              ),
              const SizedBox(width: 16),
              Text('$action →', style: TextStyle(fontSize: 14, color: AppColors.textSoft)),
            ],
          ),
        ),
      ),
    );
  }
}
