import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services.dart';
import '../ui/launch.dart';
import '../ui/live_catalog.dart';
import 'tv_cards.dart';
import 'tv_focus.dart';
import 'tv_rows.dart';
import 'tv_theme.dart';

/// "En cours · reste 28 min", "Dans 1 h 18" or "Terminé".
String tvProgramStatus(Program p, DateTime now) {
  if (p.isLiveAt(now)) return 'En cours · reste ${tvDuration(p.stop.difference(now))}';
  if (now.isBefore(p.start)) return 'Dans ${tvDuration(p.start.difference(now))}';
  return 'Terminé';
}

/// What OK does on a programme of the guide.
String tvProgramAction(Program p, DateTime now, {required bool reminded}) {
  if (p.isLiveAt(now)) return 'Regarder';
  if (now.isBefore(p.start)) return reminded ? 'Retirer le rappel' : 'Me le rappeler';
  return 'Voir la chaîne';
}

/// Start of the guide: half an hour before now, on a half hour.
DateTime tvGuideStart(DateTime now) {
  final t = now.subtract(const Duration(minutes: 30));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);
}

const _px = 12.0; // per minute
const _hours = 5;
const _chCol = 300.0;
const _rowH = 104.0;
const _viewW = 1728.0 - _chCol;

/// Guide TV: the programme selected at the top (with what OK does), the
/// grid of the evening below; OK watches what is on, or sets a reminder.
class TvGuidePage extends StatefulWidget {
  const TvGuidePage({super.key, required this.setEntry});
  final void Function(String? Function()) setEntry;

  @override
  State<TvGuidePage> createState() => _TvGuidePageState();
}

class _TvGuidePageState extends State<TvGuidePage> {
  TvFocusController? _c;
  List<ChannelTile> _tiles = const [];
  late DateTime _now;
  late DateTime _r0;
  double _hx = 0;
  Timer? _tick;
  final _rows = ScrollController();

  /// Focus id → channel and programme (null: no guide for the channel).
  final Map<String, (ChannelTile, Program?)> _cells = {};

  @override
  void initState() {
    super.initState();
    _setNow();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(_setNow));
  }

  void _setNow() {
    _now = DateTime.now();
    _r0 = tvGuideStart(_now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    final src = s.activeSource;
    _tiles = src == null
        ? const []
        : LiveCatalog.group(
            s.repo.channels(src.id),
            clean: s.settings.cleanNames,
            merge: s.settings.groupQualities,
            preferred: s.settings.preferredQuality,
          );
    final c = TvFocusScope.maybeOf(context);
    if (c != _c) {
      _c?.removeListener(_onFocus);
      _c = c?..addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _c?.removeListener(_onFocus);
    _rows.dispose();
    super.dispose();
  }

  double _x(DateTime t) => t.difference(_r0).inSeconds / 60 * _px;
  DateTime get _r1 => _r0.add(const Duration(hours: _hours));

  /// Keeps the selected programme in view, as the design does.
  void _onFocus() {
    final cell = _cells[_c?.id];
    if (cell == null) return setState(() {});
    final p = cell.$2;
    var hx = _hx;
    if (p != null) {
      final a = _x(p.start.isBefore(_r0) ? _r0 : p.start), b = _x(p.stop.isAfter(_r1) ? _r1 : p.stop);
      if (a - hx < 44) {
        hx = a - 44;
      } else if (b - hx > _viewW - 72) {
        hx = (b - _viewW + 72).clamp(double.negativeInfinity, a - 44);
      }
    }
    setState(() => _hx = hx.clamp(0, _hours * 60 * _px - _viewW));
  }

  String _id(ChannelTile t, Program? p) =>
      'g-${t.channel.extId}-${p == null ? 'none' : p.start.millisecondsSinceEpoch}';

  void _ok(AppServices s, ChannelTile t, Program? p) {
    if (p != null && _now.isBefore(p.start)) {
      setState(() => s.repo.toggleReminder(t.channel, p));
      s.library.userChanged();
      return;
    }
    Launch.channel(context, t.channel, [for (final x in _tiles) x.channel]);
  }

  Widget _block(AppServices s, ChannelTile t, Program? p) {
    final id = _id(t, p);
    _cells[id] = (t, p);
    final live = p != null && p.isLiveAt(_now);
    final past = p != null && !p.stop.isAfter(_now);
    final reminded = p != null && s.repo.hasReminder(t.channel.sourceId, t.channel.extId, p.start);
    final a = p == null ? 0.0 : _x(p.start.isBefore(_r0) ? _r0 : p.start);
    final b = p == null ? _hours * 60 * _px : _x(p.stop.isAfter(_r1) ? _r1 : p.stop);
    return Positioned(
      left: a,
      top: 8,
      bottom: 8,
      width: (b - a - 8).clamp(8, double.infinity),
      child: TvFocusable(
        id: id,
        revealAxes: const {Axis.vertical},
        revealPadding: const EdgeInsets.only(top: 8, bottom: 8),
        onOk: () => _ok(s, t, p),
        builder: (context, on) => AnimatedScale(
          scale: on ? 1.03 : 1,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: on
                  ? Colors.white
                  : live
                  ? TvColors.surfaceLive
                  : past
                  ? TvColors.surfacePast
                  : TvColors.surfaceSoon,
              borderRadius: BorderRadius.circular(10),
              boxShadow: on ? const [BoxShadow(color: Color(0xA6000000), offset: Offset(0, 16), blurRadius: 44)] : null,
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.title ?? 'Programme non disponible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tvText(
                        26,
                        weight: FontWeight.w600,
                        height: 1.15,
                        color: on
                            ? TvColors.bg
                            : past
                            ? TvColors.dim
                            : Colors.white,
                      ),
                    ),
                    if (p != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${tvClock(p.start)} – ${tvClock(p.stop)}',
                        maxLines: 1,
                        style: tvMono(
                          24,
                          color: on
                              ? TvColors.border
                              : past
                              ? const Color(0xFF5E5852)
                              : TvColors.faint,
                        ),
                      ),
                    ],
                  ],
                ),
                if (reminded)
                  const Positioned(
                    right: -8,
                    top: 4,
                    child: Icon(Icons.notifications_rounded, size: 22, color: TvColors.accent),
                  ),
                if (live)
                  Positioned(
                    left: -20,
                    bottom: 0,
                    child: Container(width: (b - a - 8) * p.progressAt(_now), height: 5, color: TvColors.accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AppServices s, ChannelTile t) {
    final progs = s.epg.programs(t.channel, _r0, _r1);
    return SizedBox(
      height: _rowH,
      child: Row(
        children: [
          Container(
            width: _chCol,
            color: TvColors.bg,
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    '${t.channel.number ?? ''}',
                    textAlign: TextAlign.right,
                    style: tvMono(24, color: TvColors.faint),
                  ),
                ),
                const SizedBox(width: 14),
                TvChannelBadge(name: t.name, logo: t.channel.logo, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tvText(24, weight: FontWeight.w600, height: 1.15),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(-_hx, 0),
                  child: SizedBox(
                    width: _hours * 60 * _px,
                    height: _rowH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [if (progs.isEmpty) _block(s, t, null), for (final p in progs) _block(s, t, p)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticks() => SizedBox(
    height: 56,
    child: Row(
      children: [
        SizedBox(
          width: _chCol,
          child: Text(
            'Ce soir',
            style: tvText(24, weight: FontWeight.w600, color: TvColors.soft),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: Transform.translate(
                offset: Offset(-_hx, 0),
                child: SizedBox(
                  width: _hours * 60 * _px,
                  height: 56,
                  child: Stack(
                    children: [
                      for (var m = 0; m < _hours * 60; m += 30)
                        Positioned(
                          left: m * _px,
                          top: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.only(left: 12),
                            alignment: Alignment.centerLeft,
                            decoration: const BoxDecoration(
                              border: Border(left: BorderSide(color: TvColors.line, width: 2)),
                            ),
                            child: Text(
                              tvClock(_r0.add(Duration(minutes: m))),
                              style: tvMono(24, color: TvColors.faint),
                            ),
                          ),
                        ),
                      Positioned(
                        left: _x(_now) - 44,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(color: TvColors.accent, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            tvClock(_now),
                            style: tvMono(24, weight: FontWeight.w600, color: TvColors.accentInk),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _header(AppServices s) {
    final cell = _cells[_c?.id] ?? (_tiles.isEmpty ? null : (_tiles.first, s.epg.now(_tiles.first.channel)));
    if (cell == null) return const SizedBox.shrink();
    final (t, p) = cell;
    final live = p != null && p.isLiveAt(_now);
    final reminded = p != null && s.repo.hasReminder(t.channel.sourceId, t.channel.extId, p.start);
    final future = p != null && _now.isBefore(p.start);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TvChannelBadge(name: t.name, logo: t.channel.logo, size: 56),
                  const SizedBox(width: 18),
                  Text(t.name, style: tvText(28, weight: FontWeight.w600, height: 1)),
                  if (p != null) ...[
                    const SizedBox(width: 18),
                    Text('${tvClock(p.start)} – ${tvClock(p.stop)}', style: tvMono(26)),
                    const SizedBox(width: 18),
                    Text(
                      tvProgramStatus(p, _now).toUpperCase(),
                      style: tvKicker(live ? TvColors.accent : TvColors.muted).copyWith(letterSpacing: 2.4),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Text(
                (p?.title ?? t.name).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tvTitle(tvTitleSize(p?.title ?? t.name, 76), height: 0.95),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 34,
                child: Text(
                  p?.description ?? p?.category ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tvText(26, weight: FontWeight.w400, height: 1.3, color: TvColors.muted),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  TvKeyHint(
                    'OK',
                    p == null ? 'Regarder' : tvProgramAction(p, _now, reminded: reminded),
                    color: Colors.white,
                  ),
                  if (future && reminded) ...[
                    const SizedBox(width: 30),
                    const Icon(Icons.notifications_rounded, size: 24, color: TvColors.accent),
                    const SizedBox(width: 10),
                    Text('Rappel activé', style: tvText(24, color: TvColors.accent, height: 1)),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 56),
        SizedBox(
          width: 420,
          height: 236,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(decoration: BoxDecoration(gradient: tvTint('c-${t.channel.extId}'))),
                Center(
                  child: TvChannelBadge(name: t.name, logo: t.channel.logo, size: 120),
                ),
                if (live)
                  Positioned(
                    left: 16,
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: TvColors.accent, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        '● EN DIRECT',
                        style: tvMono(24, weight: FontWeight.w700, color: TvColors.accentInk),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tiles = _tiles;
    widget.setEntry(() {
      if (tiles.isEmpty) return null;
      final t = tiles.first;
      return _id(t, s.epg.now(t.channel) ?? s.epg.programs(t.channel, _r0, _r1).firstOrNull);
    });
    if (tiles.isEmpty) {
      return Center(
        child: Text('Aucune chaîne dans ta source.', style: tvText(30, color: TvColors.muted)),
      );
    }
    return Stack(
      children: [
        Positioned(left: 96, right: 96, top: 156, height: 272, child: _header(s)),
        Positioned(
          left: 96,
          right: 96,
          top: 452,
          bottom: 40,
          child: Column(
            children: [
              _ticks(),
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _rows,
                      physics: const NeverScrollableScrollPhysics(),
                      itemExtent: _rowH,
                      itemCount: tiles.length,
                      itemBuilder: (context, i) => _row(s, tiles[i]),
                    ),
                    Positioned(
                      left: _chCol + _x(_now) - _hx - 1,
                      top: 0,
                      bottom: 0,
                      width: 3,
                      child: (_x(_now) - _hx) < 0 ? const SizedBox.shrink() : const ColoredBox(color: TvColors.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
