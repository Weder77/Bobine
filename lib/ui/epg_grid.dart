import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'widgets/common.dart';

/// Lets the Guide toolbar drive the grid (scroll, now, day) and shows which
/// day is visible.
class EpgGridController {
  _EpgGridState? _state;

  /// Day currently in view (0 = today).
  final ValueNotifier<int> day = ValueNotifier(0);

  void scrollBy(double minutes) => _state?._scrollBy(minutes);
  void toNow() => _state?._toNow();
  void toDay(int d) => _state?._toDay(d);
}

/// Classic TV guide grid. Rows are virtualised (only visible channels are
/// built) and each row only lays out the programmes inside the visible time
/// window, so it stays smooth with thousands of channels.
class EpgGrid extends StatefulWidget {
  const EpgGrid({
    super.key,
    required this.channels,
    required this.onPlay,
    this.controller,
    this.epgVersion = 0,
  });
  final List<Channel> channels;
  final ValueChanged<int> onPlay;
  final EpgGridController? controller;

  /// Changes when a guide import finishes: cached rows are reloaded.
  final int epgVersion;

  @override
  State<EpgGrid> createState() => _EpgGridState();
}

class _EpgGridState extends State<EpgGrid> {
  static const _pxPerMin = 5.0;
  static const _rowH = 74.0;
  static const _nameW = 230.0;
  static const _headerH = 52.0;

  late final AppServices _s;
  late DateTime _origin;

  /// Horizontal scroll offset, in minutes from [_origin].
  final _offset = ValueNotifier<double>(0);
  final Map<String, List<Program>> _cache = {};
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    final now = DateTime.now();
    _origin = DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30)
        .subtract(const Duration(minutes: 30));
    widget.controller?._state = this;
    _offset.addListener(_updateDay);
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
    if (old.channels != widget.channels || old.epgVersion != widget.epgVersion) {
      _cache.clear();
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _clock?.cancel();
    _offset.dispose();
    super.dispose();
  }

  DateTime get _viewStart => _origin.add(Duration(minutes: _offset.value.round()));

  void _updateDay() {
    final today = DateTime.now();
    final v = _viewStart.add(const Duration(minutes: 60));
    final d = DateTime(v.year, v.month, v.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    widget.controller?.day.value = d < 0 ? 0 : d;
  }

  List<Program> _programs(Channel c) => _cache.putIfAbsent(
        '${c.sourceId}:${c.extId}',
        () => _s.epg.programs(
          c,
          _origin.subtract(const Duration(hours: 6)),
          _origin.add(Duration(days: _s.settings.epgDays)),
        ),
      );

  double get _maxMinutes => _s.settings.epgDays * 24 * 60.0;

  void _scrollBy(double minutes) {
    _offset.value = (_offset.value + minutes).clamp(-6 * 60.0, _maxMinutes);
  }

  /// Puts "now" 30 min from the left edge (the grid may stay open for hours).
  void _toNow() {
    final minutes = DateTime.now().difference(_origin).inSeconds / 60 - 30;
    _offset.value = minutes.clamp(-6 * 60.0, _maxMinutes);
  }

  /// Today: now. Other days: the evening (19:30 onwards).
  void _toDay(int d) {
    if (d == 0) return _toNow();
    final n = DateTime.now();
    final target = DateTime(n.year, n.month, n.day + d, 19, 30);
    _offset.value = (target.difference(_origin).inMinutes.toDouble()).clamp(-6 * 60.0, _maxMinutes);
  }

  void _showDetails(Channel c, Program p, int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.title, style: displayStyle(22)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.name} · ${formatDay(p.start)} ${formatClock(p.start)} – ${formatClock(p.stop)}',
                style: const TextStyle(color: AppColors.muted)),
            if (p.description != null) ...[
              const SizedBox(height: 12),
              Text(p.description!, style: const TextStyle(height: 1.5)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onPlay(index);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Regarder la chaîne'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0E13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            final shift = HardwareKeyboard.instance.isShiftPressed;
            if (shift || e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
              final delta = shift ? e.scrollDelta.dy : e.scrollDelta.dx;
              _scrollBy(delta / _pxPerMin);
            }
          }
        },
        child: LayoutBuilder(builder: (context, c) {
          final gridW = c.maxWidth - _nameW;
          return Stack(children: [
            Column(children: [
              _header(gridW),
              Expanded(
                child: ListView.builder(
                  itemExtent: _rowH,
                  itemCount: widget.channels.length,
                  itemBuilder: (context, i) => _row(i, gridW),
                ),
              ),
            ]),
            // "Now" marker with the time.
            ValueListenableBuilder<double>(
              valueListenable: _offset,
              builder: (context, off, _) {
                final now = DateTime.now();
                final x = (now.difference(_origin).inSeconds / 60 - off) * _pxPerMin;
                if (x < 0 || x > gridW) return const SizedBox.shrink();
                return Positioned(
                  left: _nameW + x - 1,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(child: Container(width: 2, color: AppColors.live)),
                );
              },
            ),
            ValueListenableBuilder<double>(
              valueListenable: _offset,
              builder: (context, off, _) {
                final now = DateTime.now();
                final x = (now.difference(_origin).inSeconds / 60 - off) * _pxPerMin;
                if (x < 0 || x > gridW) return const SizedBox.shrink();
                return Positioned(
                  left: _nameW + x - 27,
                  top: 13,
                  child: IgnorePointer(
                    child: Container(
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.live, borderRadius: BorderRadius.circular(6)),
                      child: Text(formatClock(now),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, fontFeatures: tabularFigures)),
                    ),
                  ),
                );
              },
            ),
          ]);
        }),
      ),
    );
  }

  Widget _header(double gridW) {
    return Container(
      height: _headerH,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        SizedBox(
          width: _nameW,
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: ValueListenableBuilder<double>(
              valueListenable: _offset,
              builder: (context, off, _) => Text(formatDay(_viewStart.add(const Duration(minutes: 60))),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent)),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => _scrollBy(-d.delta.dx / _pxPerMin),
            child: ClipRect(
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, off, _) {
                  final first = (off / 30).floor() * 30;
                  final ticks = <Widget>[];
                  for (var m = first; (m - off) * _pxPerMin < gridW; m += 30) {
                    final t = _origin.add(Duration(minutes: m));
                    final midnight = t.hour == 0 && t.minute == 0;
                    ticks.add(Positioned(
                      left: (m - off) * _pxPerMin,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.only(left: 10),
                        decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          midnight ? '${formatDay(t)}  ${formatClock(t)}' : formatClock(t),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: midnight ? AppColors.accent : AppColors.muted,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                    ));
                  }
                  return Stack(children: ticks);
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _row(int index, double gridW) {
    final c = widget.channels[index];
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF16191F)))),
      child: Row(children: [
        InkWell(
          onTap: () => widget.onPlay(index),
          child: SizedBox(
            width: _nameW,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 12),
              child: Row(children: [
                ChannelLogo(name: c.name, url: c.logo, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('Chaîne ${c.number ?? index + 1}',
                        style: const TextStyle(fontSize: 12, color: AppColors.faint)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => _scrollBy(-d.delta.dx / _pxPerMin),
            child: ClipRect(
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, off, _) => _programBlocks(c, index, off, gridW),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _programBlocks(Channel c, int index, double off, double gridW) {
    final programs = _programs(c);
    final now = DateTime.now();
    final windowStart = _origin.add(Duration(minutes: off.floor()));
    final windowEnd = windowStart.add(Duration(minutes: (gridW / _pxPerMin).ceil()));
    final blocks = <Widget>[];
    for (final p in programs) {
      if (!p.stop.isAfter(windowStart) || !p.start.isBefore(windowEnd)) continue;
      final startMin = p.start.difference(_origin).inSeconds / 60;
      final endMin = p.stop.difference(_origin).inSeconds / 60;
      final left = (startMin - off) * _pxPerMin;
      final right = (endMin - off) * _pxPerMin;
      final live = p.isLiveAt(now);
      final past = !p.stop.isAfter(now);
      final clippedLeft = left < 0 ? 0.0 : left;
      final width = right - clippedLeft;
      blocks.add(Positioned(
        left: clippedLeft + 3,
        width: (width - 6).clamp(2.0, double.infinity),
        top: 7,
        bottom: 7,
        child: Tooltip(
          message: '${formatClock(p.start)} – ${formatClock(p.stop)}  ${p.title}',
          waitDuration: const Duration(milliseconds: 600),
          child: Material(
            color: live ? AppColors.accentTint : (past ? AppColors.field : AppColors.surface2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: live ? AppColors.accent : (past ? const Color(0xFF16191F) : const Color(0xFF20242E)),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => live ? widget.onPlay(index) : _showDetails(c, p, index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: width < 44
                    ? const SizedBox.expand()
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: past ? AppColors.faint : AppColors.text,
                              )),
                          const SizedBox(height: 2),
                          Text('${formatClock(p.start)} – ${formatClock(p.stop)}',
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12, color: AppColors.faint, fontFeatures: tabularFigures)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ));
    }
    if (blocks.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(left: 14),
          child: Text('Pas de programme', style: TextStyle(fontSize: 13, color: AppColors.faint)),
        ),
      );
    }
    return Stack(children: blocks);
  }
}
