import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'live_catalog.dart';
import 'program_actions.dart';
import 'widgets/common.dart';

/// Lets the Guide toolbar drive the grid (scroll, now, day, a programme)
/// and shows which day is visible.
class EpgGridController {
  _EpgGridState? _state;

  /// Day currently in view (0 = today, -1 = yesterday).
  final ValueNotifier<int> day = ValueNotifier(0);

  void scrollBy(double minutes) => _state?._scrollBy(minutes);
  void toNow() => _state?._toNow();
  void toDay(int d) => _state?._toDay(d);

  /// Scrolls so that [program] of row [index] is in view.
  void reveal(int index, Program program) => _state?._reveal(index, program);
}

/// TV guide: channels down the left, a time line of 7 px per minute, the
/// programmes as blocks (past dimmed, live with its progress, selected in
/// vermilion) and the "now" line. Rows are virtualised and only the
/// programmes of the visible window are laid out, so thousands of channels
/// stay smooth.
class EpgGrid extends StatefulWidget {
  const EpgGrid({
    super.key,
    required this.channels,
    required this.onPlay,
    required this.onSelect,
    this.onMenu,
    this.selected,
    this.controller,
    this.epgVersion = 0,
  });
  final List<ChannelTile> channels;
  final ValueChanged<int> onPlay;
  final void Function(int index, Program program) onSelect;

  /// Right click / long press on a programme.
  final void Function(int index, Program program, Offset at)? onMenu;

  /// Selected programme: channel ext id and start.
  final (String, DateTime)? selected;
  final EpgGridController? controller;

  /// Changes when a guide import finishes: cached rows are reloaded.
  final int epgVersion;

  static const pxPerMin = 7.0;
  static const rowH = 68.0;
  static const nameW = 240.0;
  static const headerH = 40.0;

  @override
  State<EpgGrid> createState() => _EpgGridState();
}

class _EpgGridState extends State<EpgGrid> {
  static const _px = EpgGrid.pxPerMin;

  late final AppServices _s;

  /// Yesterday at midnight: minute 0 of the time line.
  late DateTime _origin;

  /// Horizontal scroll offset, in minutes from [_origin].
  final _offset = ValueNotifier<double>(0);
  final _rows = ScrollController();
  final Map<String, List<Program>> _cache = {};
  Timer? _clock;
  double _gridW = 800;

  Set<String> _reminders = const {};
  Set<String> _recordings = const {};

  static String _mark(String channelExt, DateTime start) => '$channelExt|${start.millisecondsSinceEpoch ~/ 60000}';

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    final now = DateTime.now();
    _origin = DateTime(now.year, now.month, now.day - 1);
    widget.controller?._state = this;
    _offset.value = _nowOffset();
    _offset.addListener(_updateDay);
    // The toolbar above is already built: tell it the day after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateDay();
    });
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(EpgGrid old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.channels != widget.channels || old.epgVersion != widget.epgVersion) _cache.clear();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _clock?.cancel();
    _offset.dispose();
    _rows.dispose();
    super.dispose();
  }

  double get _maxMinutes => (1 + _s.settings.epgDays) * 24 * 60.0 - _gridW / _px;

  /// "Now" 160 px from the left edge of the time line.
  double _nowOffset() => DateTime.now().difference(_origin).inSeconds / 60 - 160 / _px;

  void _set(double minutes) => _offset.value = minutes.clamp(0.0, math.max(0.0, _maxMinutes));

  void _scrollBy(double minutes) => _set(_offset.value + minutes);
  void _toNow() => _set(_nowOffset());

  /// Today: now. Other days: the evening (from 19:30).
  void _toDay(int d) {
    if (d == 0) return _toNow();
    final n = DateTime.now();
    _set(DateTime(n.year, n.month, n.day + d, 19, 30).difference(_origin).inMinutes.toDouble());
  }

  void _reveal(int index, Program p) {
    final start = p.start.difference(_origin).inSeconds / 60;
    final end = p.stop.difference(_origin).inSeconds / 60;
    final visible = _gridW / _px;
    if (start < _offset.value || end > _offset.value + visible) _set(start - 160 / _px);
    if (_rows.hasClients) {
      final top = index * EpgGrid.rowH;
      final pos = _rows.position;
      if (top < pos.pixels || top + EpgGrid.rowH > pos.pixels + pos.viewportDimension) {
        _rows.jumpTo((top - EpgGrid.rowH * 2).clamp(0.0, pos.maxScrollExtent));
      }
    }
  }

  /// Time 160 px into the time line (where "now" sits): its day is the
  /// day in view.
  DateTime get _anchor => _origin.add(Duration(minutes: (_offset.value + 160 / _px).round()));

  void _updateDay() {
    final today = DateTime.now();
    final v = _anchor;
    widget.controller?.day.value = DateTime(
      v.year,
      v.month,
      v.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  List<Program> _programs(Channel c) => _cache.putIfAbsent(
    '${c.sourceId}:${c.extId}',
    () => _s.epg.programs(c, _origin, _origin.add(Duration(days: 1 + _s.settings.epgDays))),
  );

  @override
  Widget build(BuildContext context) {
    _reminders = {for (final r in _s.repo.reminders()) _mark(r.channelExt, r.start)};
    _recordings = {
      for (final r in _s.repo.recordings())
        if (r.status == RecordingStatus.scheduled || r.status == RecordingStatus.recording)
          _mark(r.channelExt, r.start.add(const Duration(minutes: 1))),
    };
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          final shift = HardwareKeyboard.instance.isShiftPressed;
          if (shift || e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
            _scrollBy((shift ? e.scrollDelta.dy : e.scrollDelta.dx) / _px);
          }
        }
      },
      child: LayoutBuilder(
        builder: (context, box) {
          _gridW = box.maxWidth - EpgGrid.nameW;
          return Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSoft)),
            ),
            child: Stack(
              children: [
                // Half-hour lines behind the rows.
                Positioned(
                  left: EpgGrid.nameW,
                  right: 0,
                  top: EpgGrid.headerH,
                  bottom: 0,
                  child: CustomPaint(painter: _LinesPainter(_offset)),
                ),
                Column(
                  children: [
                    _header(),
                    Expanded(
                      child: ListView.builder(
                        controller: _rows,
                        itemExtent: EpgGrid.rowH,
                        itemCount: widget.channels.length,
                        itemBuilder: (context, i) => _row(i),
                      ),
                    ),
                  ],
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (context, off, _) {
                    final now = DateTime.now();
                    final x = (now.difference(_origin).inSeconds / 60 - off) * _px;
                    if (x < 0 || x > _gridW) return const SizedBox.shrink();
                    return Positioned(
                      left: EpgGrid.nameW + x - 1,
                      top: EpgGrid.headerH,
                      bottom: 0,
                      child: IgnorePointer(child: Container(width: 2, color: AppColors.accent)),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      height: EpgGrid.headerH,
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: EpgGrid.nameW,
            child: Padding(
              padding: const EdgeInsets.only(left: 48),
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, off, _) => Text(formatShortDate(_anchor), style: monoStyle(12, height: 1)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => _scrollBy(-d.delta.dx / _px),
              child: ClipRect(
                child: ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (context, off, _) {
                    final first = (off / 30).floor() * 30;
                    final children = <Widget>[];
                    for (var m = first; (m - off) * _px < _gridW; m += 30) {
                      final t = _origin.add(Duration(minutes: m));
                      final midnight = t.hour == 0 && t.minute == 0;
                      children.add(
                        Positioned(
                          left: (m - off) * _px,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: AppColors.borderInput)),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              midnight ? '${formatDayButton(t)} · 00:00' : formatClock(t),
                              style: monoStyle(12, height: 1, color: midnight ? AppColors.accent : AppColors.faint),
                            ),
                          ),
                        ),
                      );
                    }
                    final now = DateTime.now();
                    final x = (now.difference(_origin).inSeconds / 60 - off) * _px;
                    if (x >= 0 && x <= _gridW) {
                      children.add(
                        Positioned(
                          left: x - 26,
                          top: 9,
                          width: 52,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              formatClock(now),
                              style: monoStyle(12, weight: FontWeight.w600, color: AppColors.onAccent, height: 1),
                            ),
                          ),
                        ),
                      );
                    }
                    return Stack(clipBehavior: Clip.none, children: children);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(int index) {
    final t = widget.channels[index];
    final c = t.channel;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderFaint)),
      ),
      child: Row(
        children: [
          HoverBuilder(
            onActivate: () => widget.onPlay(index),
            builder: (context, hover) => GestureDetector(
              onTap: () => widget.onPlay(index),
              child: Container(
                width: EpgGrid.nameW,
                color: AppColors.bg,
                padding: const EdgeInsets.fromLTRB(48, 0, 16, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${c.number ?? index + 1}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: monoStyle(12, height: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ChannelLogo(name: t.name, url: c.logo, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          decoration: hover ? TextDecoration.underline : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => _scrollBy(-d.delta.dx / _px),
              child: ClipRect(
                child: ValueListenableBuilder<double>(
                  valueListenable: _offset,
                  builder: (context, off, _) => _blocks(t, index, off),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocks(ChannelTile t, int index, double off) {
    final c = t.channel;
    final programs = _programs(c);
    final now = DateTime.now();
    final windowStart = _origin.add(Duration(minutes: off.floor()));
    final windowEnd = windowStart.add(Duration(minutes: (_gridW / _px).ceil()));
    final sel = widget.selected;
    final blocks = <Widget>[];
    for (final p in programs) {
      if (!p.stop.isAfter(windowStart) || !p.start.isBefore(windowEnd)) continue;
      final left = (p.start.difference(_origin).inSeconds / 60 - off) * _px;
      final right = (p.stop.difference(_origin).inSeconds / 60 - off) * _px;
      final x = math.max(0.0, left);
      final w = right - x - 4;
      if (w < 2) continue;
      blocks.add(
        Positioned(
          left: x,
          width: w,
          top: 5,
          bottom: 5,
          child: _Block(
            program: p,
            width: w,
            now: now,
            selected: sel != null && sel.$1 == c.extId && sel.$2 == p.start,
            replay: canReplay(c, p, now),
            reminder: _reminders.contains(_mark(c.extId, p.start)),
            recording: _recordings.contains(_mark(c.extId, p.start)),
            onTap: () => widget.onSelect(index, p),
            onDoubleTap: p.isLiveAt(now) ? () => widget.onPlay(index) : null,
            onMenu: widget.onMenu == null ? null : (at) => widget.onMenu!(index, p, at),
            onFocus: () {
              widget.onSelect(index, p);
              if (right > _gridW) {
                _scrollBy((right - _gridW) / _px + 15);
              } else if (left < 0) {
                _scrollBy(left / _px - 15);
              }
            },
          ),
        ),
      );
    }
    if (blocks.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text('Pas de programme', style: monoStyle(12, color: AppColors.disabled2)),
        ),
      );
    }
    return Stack(children: blocks);
  }
}

class _Block extends StatefulWidget {
  const _Block({
    required this.program,
    required this.width,
    required this.now,
    required this.selected,
    required this.replay,
    required this.reminder,
    required this.recording,
    required this.onTap,
    required this.onFocus,
    this.onDoubleTap,
    this.onMenu,
  });
  final Program program;
  final double width;
  final DateTime now;
  final bool selected;
  final bool replay;
  final bool reminder;
  final bool recording;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onMenu;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  bool _hover = false;
  bool _focus = false;

  static Color _brighten(Color c) => Color.fromARGB(
    (c.a * 255).round(),
    math.min(255, (c.r * 255 * 1.3).round()),
    math.min(255, (c.g * 255 * 1.3).round()),
    math.min(255, (c.b * 255 * 1.3).round()),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final live = p.isLiveAt(widget.now);
    final past = !p.stop.isAfter(widget.now);
    final on = widget.selected;
    var bg = on
        ? AppColors.accentSelected
        : live
        ? AppColors.surface3
        : past
        ? AppColors.borderFaint
        : AppColors.surface;
    final border = on
        ? AppColors.accent
        : live
        ? AppColors.borderStrong
        : past
        ? AppColors.surface
        : AppColors.border;
    if (_hover || _focus) bg = _brighten(bg);
    final dim = past && !widget.replay;
    return FocusableActionDetector(
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) {
        setState(() => _focus = v);
        if (v) widget.onFocus();
      },
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            (widget.onDoubleTap ?? widget.onTap)();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: widget.onMenu == null ? null : (d) => widget.onMenu!(d.globalPosition),
        onLongPressStart: widget.onMenu == null ? null : (d) => widget.onMenu!(d.globalPosition),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _focus ? AppColors.text : border, width: _focus ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.width >= 44)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (past && widget.replay) ...[
                            Icon(Icons.replay_rounded, size: 13, color: AppColors.textSoft),
                            const SizedBox(width: 5),
                          ],
                          if (widget.recording) ...[
                            Icon(Icons.fiber_manual_record_rounded, size: 10, color: AppColors.accent),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: dim ? AppColors.disabled : AppColors.text,
                              ),
                            ),
                          ),
                          if (widget.reminder) const SizedBox(width: 16),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatClock(p.start)} – ${formatClock(p.stop)}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: monoStyle(12, color: dim ? AppColors.disabled2 : AppColors.faint, height: 1),
                      ),
                    ],
                  ),
                ),
              if (widget.reminder)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(Icons.notifications_rounded, size: 13, color: AppColors.accent),
                ),
              if (live)
                Positioned(
                  left: 0,
                  bottom: 0,
                  height: 3,
                  width: widget.width * p.progressAt(widget.now),
                  child: ColoredBox(color: AppColors.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vertical half-hour lines of the time line, following the scroll.
class _LinesPainter extends CustomPainter {
  _LinesPainter(this.offset) : super(repaint: offset);
  final ValueNotifier<double> offset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.surface
      ..strokeWidth = 1;
    const step = 30 * EpgGrid.pxPerMin;
    final off = offset.value * EpgGrid.pxPerMin;
    for (var x = -(off % step); x < size.width; x += step) {
      if (x < 0) continue;
      canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.offset != offset;
}
