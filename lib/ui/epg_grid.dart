import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../services.dart';
import 'widgets/common.dart';

/// Classic TV guide grid. Rows are virtualised (only visible channels are
/// built) and each row only lays out the programmes inside the visible time
/// window, so it stays smooth with thousands of channels.
class EpgGrid extends StatefulWidget {
  const EpgGrid({super.key, required this.channels, required this.onPlay});
  final List<Channel> channels;
  final ValueChanged<int> onPlay;

  @override
  State<EpgGrid> createState() => _EpgGridState();
}

class _EpgGridState extends State<EpgGrid> {
  static const _pxPerMin = 5.0;
  static const _rowH = 62.0;
  static const _nameW = 210.0;

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
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(EpgGrid old) {
    super.didUpdateWidget(old);
    if (old.channels != widget.channels) _cache.clear();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _offset.dispose();
    super.dispose();
  }

  List<Program> _programs(Channel c) => _cache.putIfAbsent(
        '${c.sourceId}:${c.extId}',
        () => _s.epg.programs(
          c,
          _origin.subtract(const Duration(hours: 6)),
          _origin.add(Duration(days: _s.settings.epgDays)),
        ),
      );

  void _scrollBy(double minutes) {
    final maxMin = _s.settings.epgDays * 24 * 60.0;
    _offset.value = (_offset.value + minutes).clamp(-6 * 60.0, maxMin);
  }

  void _toNow() => _offset.value = 0;

  void _showDetails(Channel c, Program p, int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.name} · ${formatDay(p.start)} ${formatClock(p.start)} – ${formatClock(p.stop)}',
                style: const TextStyle(color: AppColors.muted)),
            if (p.description != null) ...[
              const SizedBox(height: 12),
              Text(p.description!, style: const TextStyle(height: 1.4)),
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
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          final shift = HardwareKeyboard.instance.isShiftPressed;
          if (shift || e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs()) {
            final delta = shift ? e.scrollDelta.dy : e.scrollDelta.dx;
            _scrollBy(delta / _pxPerMin);
          }
        }
      },
      child: Column(children: [
        _header(),
        const Divider(),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final gridW = c.maxWidth - _nameW;
            return Stack(children: [
              ListView.builder(
                itemExtent: _rowH,
                itemCount: widget.channels.length,
                itemBuilder: (context, i) => _row(i, gridW),
              ),
              // "Now" marker.
              ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, off, _) {
                  final x = (DateTime.now().difference(_origin).inSeconds / 60 - off) * _pxPerMin;
                  if (x < 0 || x > gridW) return const SizedBox.shrink();
                  return Positioned(
                    left: _nameW + x - 1,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(child: Container(width: 2, color: AppColors.live)),
                  );
                },
              ),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 44,
      child: Row(children: [
        SizedBox(
          width: _nameW,
          child: Row(children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: '-2 h',
              onPressed: () => _scrollBy(-120),
              icon: const Icon(Icons.chevron_left),
            ),
            TextButton(onPressed: _toNow, child: const Text('Maintenant')),
            IconButton(
              tooltip: '+2 h',
              onPressed: () => _scrollBy(120),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => _scrollBy(-d.delta.dx / _pxPerMin),
            child: ClipRect(
              child: ValueListenableBuilder<double>(
                valueListenable: _offset,
                builder: (context, off, _) => LayoutBuilder(builder: (context, c) {
                  final first = (off / 30).floor() * 30;
                  final ticks = <Widget>[];
                  var dayShown = false;
                  for (var m = first; (m - off) * _pxPerMin < c.maxWidth; m += 30) {
                    final t = _origin.add(Duration(minutes: m));
                    final x = (m - off) * _pxPerMin;
                    // The first fully visible slot (and each midnight) carries the day.
                    final withDay = (!dayShown && x >= 0) || (t.hour == 0 && t.minute == 0);
                    if (x >= 0) dayShown = true;
                    ticks.add(Positioned(
                      left: x,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.only(left: 6),
                        decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))),
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(children: [
                            if (withDay)
                              TextSpan(
                                text: '${formatDay(t)}  ',
                                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                              ),
                            TextSpan(text: formatClock(t)),
                          ]),
                          style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ));
                  }
                  return Stack(children: [
                    ...ticks,
                  ]);
                }),
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
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        InkWell(
          onTap: () => widget.onPlay(index),
          child: SizedBox(
            width: _nameW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                ChannelLogo(name: c.name, url: c.logo, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
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
      var left = (startMin - off) * _pxPerMin;
      final right = (endMin - off) * _pxPerMin;
      final width = right - left;
      final live = p.isLiveAt(now);
      final clippedLeft = left < 0 ? 0.0 : left;
      blocks.add(Positioned(
        left: clippedLeft + 2,
        width: (right - clippedLeft - 4).clamp(2.0, double.infinity),
        top: 5,
        bottom: 5,
        child: Tooltip(
          message: '${formatClock(p.start)} – ${formatClock(p.stop)}  ${p.title}',
          waitDuration: const Duration(milliseconds: 600),
          child: Material(
            color: live ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface2,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => live ? widget.onPlay(index) : _showDetails(c, p, index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                decoration: live
                    ? BoxDecoration(
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: width < 40
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: live ? AppColors.text : const Color(0xFFCDD3DC),
                              )),
                          Text('${formatClock(p.start)} – ${formatClock(p.stop)}',
                              maxLines: 1,
                              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
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
          padding: EdgeInsets.only(left: 12),
          child: Text('Pas de programme', style: TextStyle(fontSize: 12, color: AppColors.faint)),
        ),
      );
    }
    return Stack(children: blocks);
  }
}
