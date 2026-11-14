import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/device.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/epg_cache.dart';
import '../data/models.dart';
import '../features/tmdb.dart';
import '../ui/widgets/cards.dart';
import '../ui/widgets/common.dart';
import 'player_service.dart';
import 'player_widgets.dart';

/// "1:02:03" or "52:10".
String playerTime(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

// ------------------------------------------------------------------ buttons

/// 44 px square button of the player bars (transparent, light on hover).
/// Vermilion ring around a player button while it has the remote / keyboard
/// focus (the hover tint alone is too faint on a TV across the room, and
/// white is lost on the white play button).
const focusRingSide = WidgetStateProperty<BorderSide?>.fromMap({
  WidgetState.focused: BorderSide(color: DarkColors.accent, width: 3),
  WidgetState.any: null,
});

class PlayerIconButton extends StatelessWidget {
  const PlayerIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 22});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onTap,
      iconSize: size,
      style: IconButton.styleFrom(
        foregroundColor: DarkColors.text,
        fixedSize: const Size(44, 44),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ).copyWith(overlayColor: const WidgetStatePropertyAll(Color(0x24FFFFFF)), side: focusRingSide),
      icon: Icon(icon),
    ),
  );
}

/// "Chaînes", "Mini-guide", "Audio et sous-titres": icon and label, light
/// background while its panel is open.
class PlayerTextButton extends StatelessWidget {
  const PlayerTextButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final b = TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: DarkColors.text,
        backgroundColor: active ? const Color(0x33FFFFFF) : Colors.transparent,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w600),
      ).copyWith(overlayColor: const WidgetStatePropertyAll(Color(0x24FFFFFF))),
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// Round white play / pause button (52 px).
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, required this.player, required this.onTap, this.playing, this.focusNode});
  final Player player;
  final VoidCallback onTap;

  /// Given the focus when OK of the remote shows the controls.
  final FocusNode? focusNode;

  /// State to show instead of the local player's (casting).
  final bool? playing;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: player.stream.playing,
    initialData: player.state.playing,
    builder: (context, snap) {
      final playing = this.playing ?? snap.data == true;
      return Tooltip(
        message: playing ? 'Pause (Espace)' : 'Lecture (Espace)',
        child: IconButton(
          onPressed: onTap,
          focusNode: focusNode,
          iconSize: 28,
          style:
              IconButton.styleFrom(
                backgroundColor: DarkColors.action,
                foregroundColor: DarkColors.onAction,
                fixedSize: const Size(52, 52),
                minimumSize: const Size(52, 52),
                shape: const CircleBorder(),
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.hovered) ? const Color(0xFFE9E4DE) : DarkColors.action,
                ),
                side: focusRingSide,
              ),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
      );
    },
  );
}

/// Round translucent button (back, close of the panels).
class RoundGlassButton extends StatelessWidget {
  const RoundGlassButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 48});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onTap,
      iconSize: size * 0.45,
      style:
          IconButton.styleFrom(
            foregroundColor: DarkColors.text,
            fixedSize: Size(size, size),
            minimumSize: Size(size, size),
            shape: const CircleBorder(),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
                  ? const Color(0x3DFFFFFF)
                  : (size >= 48 ? const Color(0x1FFFFFFF) : const Color(0x1AFFFFFF)),
            ),
          ),
      icon: Icon(icon),
    ),
  );
}

// ------------------------------------------------------------------- top

/// "EN DIRECT" (vermilion) or "DIFFÉRÉ −02:14" (cream), with a pulsing dot.
class LiveTag extends StatelessWidget {
  const LiveTag({super.key, this.delay});
  final Duration? delay;

  @override
  Widget build(BuildContext context) {
    final delayed = delay != null;
    final ink = delayed ? DarkColors.onAction : DarkColors.onAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: delayed ? DarkColors.cream : DarkColors.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            delayed ? 'DIFFÉRÉ −${playerTime(delay!)}' : 'EN DIRECT',
            style: darkMono(12, weight: FontWeight.w700, color: ink, height: 1).copyWith(letterSpacing: 12 * 0.06),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- live info

/// Programme on air, large, with its progress and what comes next.
class LiveProgramInfo extends StatelessWidget {
  const LiveProgramInfo({super.key, required this.now, required this.next, required this.fallbackTitle});
  final Program? now;
  final Program? next;
  final String fallbackTitle;

  @override
  Widget build(BuildContext context) {
    final p = now;
    final t = DateTime.now();
    final size = (MediaQuery.sizeOf(context).width * 0.044).clamp(40.0, 64.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p?.category != null) ...[
            Text(p!.category!.toUpperCase(), style: darkLabel(color: DarkColors.accent, size: 12)),
            const SizedBox(height: 12),
          ],
          Text(
            (p?.title ?? fallbackTitle).toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: darkPoster(size, height: 0.9),
          ),
          if (p != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(formatClock(p.start), style: darkMono(13, color: DarkColors.textSoft, height: 1)),
                const SizedBox(width: 14),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ProgressLine(p.progressAt(t), track: const Color(0x38FFFFFF)),
                  ),
                ),
                const SizedBox(width: 14),
                Text(formatClock(p.stop), style: darkMono(13, color: DarkColors.textSoft, height: 1)),
                const SizedBox(width: 14),
                Text('reste ${formatSpan(p.stop.difference(t))}', style: darkMono(13, height: 1)),
              ],
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                text: 'Ensuite ${formatClock(next!.start)} · ',
                children: [
                  TextSpan(
                    text: next!.title,
                    style: const TextStyle(color: DarkColors.text),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1, color: DarkColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- seek

/// Seek line of films and episodes: elapsed, bar (downloaded part lighter,
/// vermilion knob) and remaining time.
class VodSeekRow extends StatefulWidget {
  const VodSeekRow({
    super.key,
    required this.position,
    required this.duration,
    required this.ranges,
    required this.onSeek,
    this.onInteraction,
    this.onPoint,
    this.preview,
    this.previewWidth = 0,
  });
  final Duration position;
  final Duration duration;
  final List<CachedRange> ranges;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onInteraction;

  /// The instant under the pointer (hovering or dragging), null once it left.
  final ValueChanged<Duration?>? onPoint;

  /// The picture of that instant, [previewWidth] wide, shown above its time.
  final Widget? preview;
  final double previewWidth;

  @override
  State<VodSeekRow> createState() => _VodSeekRowState();
}

class _VodSeekRowState extends State<VodSeekRow> {
  double? _drag;
  double? _hover;

  /// The pointer is over the bar (it may leave it during a drag).
  bool _inside = false;

  double get _total => widget.duration.inMilliseconds.toDouble();
  Duration _at(double f) => Duration(milliseconds: (f.clamp(0.0, 1.0) * _total).round());

  /// Tells who shows the picture where the pointer is.
  void _point() {
    final at = _drag ?? _hover;
    widget.onPoint?.call(at == null || _total <= 0 ? null : _at(at));
  }

  @override
  void dispose() {
    // Left with the pointer still on the bar (the controls hid, the film ended).
    if (_drag != null || _hover != null) widget.onPoint?.call(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _drag ?? (_total <= 0 ? 0.0 : widget.position.inMilliseconds / _total);
    final pos = _drag != null ? _at(_drag!) : widget.position;
    final style = darkMono(14, color: DarkColors.text, height: 1);
    return Row(
      children: [
        SizedBox(width: 64, child: Text(playerTime(pos), style: style)),
        const SizedBox(width: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              double frac(double dx) => (dx / w).clamp(0.0, 1.0);
              final tip = _drag ?? _hover;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => _inside = true,
                onHover: (e) {
                  setState(() => _hover = frac(e.localPosition.dx));
                  _point();
                },
                onExit: (_) {
                  _inside = false;
                  setState(() => _hover = null);
                  _point();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Length not known yet (a replay, some films): every
                  // place on the bar was 0:00, and a click started over.
                  onTapUp: (d) {
                    if (_total <= 0) return;
                    widget.onInteraction?.call();
                    widget.onSeek(_at(frac(d.localPosition.dx)));
                  },
                  onHorizontalDragStart: (d) {
                    if (_total <= 0) return;
                    setState(() => _drag = frac(d.localPosition.dx));
                    _point();
                  },
                  onHorizontalDragUpdate: (d) {
                    if (_total <= 0) return;
                    widget.onInteraction?.call();
                    setState(() => _drag = frac(d.localPosition.dx));
                    _point();
                  },
                  onHorizontalDragEnd: (_) {
                    if (_drag != null) widget.onSeek(_at(_drag!));
                    // No hover is reported while a button is down: without
                    // this the time (and its picture) jumped back to where
                    // the pointer was before the drag.
                    setState(() {
                      _hover = _inside ? _drag : null;
                      _drag = null;
                    });
                    _point();
                  },
                  child: SizedBox(
                    height: 22,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _SeekPainter(played: shown, ranges: widget.ranges, total: _total, hover: _hover),
                          ),
                        ),
                        if (tip != null && _total > 0)
                          Positioned(
                            left: (tip * w - 32).clamp(0.0, math.max(0.0, w - 64)),
                            top: -30,
                            child: Container(
                              width: 64,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              decoration: BoxDecoration(
                                color: DarkColors.surface3,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(playerTime(_at(tip)), style: darkMono(12, color: DarkColors.text, height: 1)),
                            ),
                          ),
                        if (tip != null && _total > 0 && widget.preview != null)
                          Positioned(
                            // Centred on the pointer, kept within the bar.
                            left: (tip * w - widget.previewWidth / 2).clamp(
                              0.0,
                              math.max(0.0, w - widget.previewWidth),
                            ),
                            // Above the time (22 high, 8 above the bar).
                            bottom: 22 + 30 + 6,
                            child: IgnorePointer(child: widget.preview!),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 72,
          child: Text(
            _total <= 0 || pos > widget.duration ? '' : '−${playerTime(widget.duration - pos)}',
            textAlign: TextAlign.right,
            style: darkMono(14, color: DarkColors.textSoft, height: 1),
          ),
        ),
      ],
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({required this.played, required this.ranges, required this.total, this.hover});
  final double played;
  final List<CachedRange> ranges;
  final double total;
  final double? hover;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 4.0;
    final y = size.height / 2;
    const r = Radius.circular(2);
    RRect bar(double a, double b) => RRect.fromLTRBR(a * size.width, y - h / 2, b * size.width, y + h / 2, r);
    canvas.drawRRect(bar(0, 1), Paint()..color = const Color(0x38FFFFFF));
    if (total > 0) {
      final cached = Paint()..color = const Color(0x59FFFFFF);
      for (final c in ranges) {
        final a = (c.start.inMilliseconds / total).clamp(0.0, 1.0);
        final b = (c.end.inMilliseconds / total).clamp(0.0, 1.0);
        if (b > a) canvas.drawRRect(bar(a, b), cached);
      }
    }
    if (hover != null) canvas.drawRRect(bar(0, hover!), Paint()..color = const Color(0x26FFFFFF));
    final p = played.clamp(0.0, 1.0);
    canvas.drawRRect(bar(0, p), Paint()..color = DarkColors.accent);
    canvas.drawCircle(Offset(p * size.width, y), 7, Paint()..color = DarkColors.accent);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.played != played || old.ranges != ranges || old.total != total || old.hover != hover;
}

// ----------------------------------------------------------------- panels

/// Full-height panel over the video, on the left or the right.
class PlayerSidePanel extends StatelessWidget {
  const PlayerSidePanel({
    super.key,
    required this.right,
    required this.width,
    required this.title,
    required this.onClose,
    required this.child,
    this.kicker,
    this.footer,
  });
  final bool right;
  final double width;
  final String title;
  final String? kicker;
  final VoidCallback onClose;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    bottom: 0,
    left: right ? null : 0,
    right: right ? 0 : null,
    width: width,
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF20D0C0B),
            border: Border(
              left: right ? const BorderSide(color: Color(0x14FFFFFF)) : BorderSide.none,
              right: right ? BorderSide.none : const BorderSide(color: Color(0x14FFFFFF)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (kicker != null) ...[
                            Text(kicker!, maxLines: 1, overflow: TextOverflow.ellipsis, style: darkMono(13, height: 1)),
                            const SizedBox(height: 8),
                          ],
                          Text(title.toUpperCase(), style: darkPoster(34, height: 1)),
                        ],
                      ),
                    ),
                    RoundGlassButton(icon: Icons.close_rounded, tooltip: 'Fermer (Échap)', onTap: onClose, size: 40),
                  ],
                ),
              ),
              Expanded(child: _FocusFirst(child: child)),
              ?footer,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Gives the focus to the first item of [child] when it appears, so a TV
/// remote can move in a panel just opened (not to the close button above).
class _FocusFirst extends StatefulWidget {
  const _FocusFirst({required this.child});
  final Widget child;

  @override
  State<_FocusFirst> createState() => _FocusFirstState();
}

class _FocusFirstState extends State<_FocusFirst> {
  final _scope = FocusScopeNode(debugLabel: 'panel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scope.focusedChild != null) return;
      _scope.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(node: _scope, child: widget.child);
}

/// "Chaînes": the programme of every channel, the current one in vermilion.
class ChannelListPanel extends StatelessWidget {
  const ChannelListPanel({
    super.key,
    required this.channels,
    required this.names,
    required this.selected,
    required this.epg,
    required this.scroll,
    required this.onPick,
    required this.onClose,
  });
  final List<Channel> channels;
  final String Function(Channel) names;
  final int selected;
  final EpgCache epg;
  final ScrollController scroll;
  final ValueChanged<int> onPick;
  final VoidCallback onClose;

  static const rowExtent = 66.0;

  @override
  Widget build(BuildContext context) => PlayerSidePanel(
    right: false,
    width: 420,
    title: 'Chaînes',
    onClose: onClose,
    footer: Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Text('↑ ↓ pour zapper · ${Device.backKey} pour fermer', style: darkMono(12, height: 1)),
    ),
    child: ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemExtent: rowExtent,
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final c = channels[i];
        final on = i == selected;
        final now = epg.now(c);
        final t = DateTime.now();
        return HoverBuilder(
          onActivate: () => onPick(i),
          focusRingRadius: 8,
          builder: (context, hover) => GestureDetector(
            onTap: () => onPick(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: on ? const Color(0x29FF5A36) : (hover ? const Color(0x0FFFFFFF) : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${c.number ?? i + 1}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: darkMono(
                        13,
                        weight: FontWeight.w600,
                        color: on ? DarkColors.accent : DarkColors.faint,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ChannelLogo(name: names(c), url: c.logo, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                now?.title ?? names(c),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.15),
                              ),
                            ),
                            if (now != null) ...[
                              const SizedBox(width: 8),
                              Text(formatClock(now.stop), style: darkMono(12, height: 1)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          names(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1, color: DarkColors.faint),
                        ),
                        if (now != null) ...[
                          const SizedBox(height: 6),
                          ProgressLine(now.progressAt(t), height: 3, track: const Color(0x1FFFFFFF)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// "Mini-guide": what plays now on this channel and the next three.
class MiniGuide extends StatelessWidget {
  const MiniGuide({super.key, required this.programs});
  final List<Program> programs;

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now();
    return Positioned(
      left: 48,
      right: 48,
      bottom: 300,
      child: programs.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: _glass(
                const Text('Pas de programme pour cette chaîne.', style: TextStyle(color: DarkColors.textSoft)),
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                const gap = 12.0;
                final cols = math.min(programs.length, math.max(1, ((box.maxWidth + gap) / (200 + gap)).floor()));
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cols; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: w,
                        child: _glass(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    switch (i) {
                                      0 => programs[0].isLiveAt(t) ? 'MAINTENANT' : 'ENSUITE',
                                      1 => 'ENSUITE',
                                      _ => 'PLUS TARD',
                                    },
                                    style: darkMono(
                                      12,
                                      weight: FontWeight.w600,
                                      color: i == 0 && programs[0].isLiveAt(t) ? DarkColors.accent : DarkColors.faint,
                                      height: 1,
                                    ).copyWith(letterSpacing: 12 * 0.04),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${formatClock(programs[i].start)} – ${formatClock(programs[i].stop)}',
                                    style: darkMono(12, weight: FontWeight.w600, height: 1),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 9),
                              SizedBox(
                                height: 40,
                                child: Text(
                                  programs[i].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25),
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                programs[i].category ?? ' ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, height: 1, color: DarkColors.faint),
                              ),
                              const SizedBox(height: 9),
                              ProgressLine(
                                programs[i].isLiveAt(t) ? programs[i].progressAt(t) : 0,
                                height: 3,
                                track: const Color(0x1FFFFFFF),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  static Widget _glass(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xCC0D0C0B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: child,
      ),
    ),
  );
}

/// One choice of a panel list: check mark when chosen.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.detail});
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 8,
    builder: (context, hover) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: hover ? const Color(0x0FFFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: selected ? const Icon(Icons.check_rounded, size: 18, color: DarkColors.accent) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: selected ? DarkColors.text : DarkColors.muted,
                ),
              ),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(detail!, style: darkMono(12, height: 1)),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _section(String title, List<Widget> children) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title.toUpperCase(), style: darkLabel(color: DarkColors.faint, size: 12)),
    ),
    ...children,
  ],
);

/// Dark segmented choice (subtitle size, speed, picture format).
class PanelSegments<T> extends StatelessWidget {
  const PanelSegments({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: DarkColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: DarkColors.borderInput),
    ),
    child: Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final (v, label) in options)
          HoverBuilder(
            onActivate: () => onChanged(v),
            focusRingRadius: 4,
            builder: (context, hover) => GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: v == value ? DarkColors.action : (hover ? const Color(0x14FFFFFF) : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: v == value ? DarkColors.onAction : DarkColors.textSoft,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// "Audio et sous-titres", plus subtitle size, speed and picture format.
class TracksSidePanel extends StatelessWidget {
  const TracksSidePanel({
    super.key,
    required this.tracks,
    required this.audioId,
    required this.subtitleId,
    required this.onAudio,
    required this.onSubtitle,
    required this.subtitleScale,
    required this.onSubtitleScale,
    required this.onClose,
    this.extra = const [],
  });
  final Tracks tracks;
  final String audioId;
  final String subtitleId;
  final ValueChanged<AudioTrack> onAudio;
  final ValueChanged<SubtitleTrack> onSubtitle;
  final double subtitleScale;
  final ValueChanged<double> onSubtitleScale;
  final VoidCallback onClose;

  /// More sections (speed, picture format).
  final List<Widget> extra;

  static const scales = [(0.75, 'Petite'), (1.0, 'Moyenne'), (1.35, 'Grande')];

  @override
  Widget build(BuildContext context) {
    final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final noSub = !subs.any((t) => t.id == subtitleId);
    final scale = scales
        .map((s) => s.$1)
        .reduce((a, b) => (a - subtitleScale).abs() < (b - subtitleScale).abs() ? a : b);
    return PlayerSidePanel(
      right: true,
      width: 420,
      title: 'Audio et sous-titres',
      onClose: onClose,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        children: [
          _section('Audio', [
            if (audio.isEmpty) const _Choice(label: 'Piste unique', selected: true, onTap: _noop),
            for (var i = 0; i < audio.length; i++)
              _Choice(
                label: audioTrackTitle(audio[i], i),
                detail: audioTrackDetail(audio[i]),
                selected: audio[i].id == audioId || (audio.length == 1),
                onTap: () => onAudio(audio[i]),
              ),
          ]),
          const SizedBox(height: 26),
          _section('Sous-titres', [
            _Choice(label: 'Désactivés', selected: noSub, onTap: () => onSubtitle(SubtitleTrack.no())),
            for (var i = 0; i < subs.length; i++)
              _Choice(
                label: subtitleTrackTitle(subs[i], i),
                detail: subtitleTrackDetail(subs[i]),
                selected: subs[i].id == subtitleId,
                onTap: () => onSubtitle(subs[i]),
              ),
          ]),
          const SizedBox(height: 26),
          _section('Taille des sous-titres', [
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: PanelSegments<double>(value: scale, options: scales, onChanged: onSubtitleScale),
            ),
          ]),
          for (final w in extra) ...[const SizedBox(height: 26), w],
        ],
      ),
    );
  }
}

void _noop() {}

/// Section of [TracksSidePanel] with segments.
Widget panelSegmentsSection<T>(String title, T value, List<(T, String)> options, ValueChanged<T> onChanged) =>
    _section(title, [
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: PanelSegments<T>(value: value, options: options, onChanged: onChanged),
      ),
    ]);

/// "Épisodes": the episodes of the season being watched.
class EpisodesPanel extends StatelessWidget {
  const EpisodesPanel({
    super.key,
    required this.seriesTitle,
    required this.episodes,
    required this.current,
    required this.progressOf,
    required this.onPick,
    required this.onClose,
    required this.season,
    required this.seasons,
    required this.onSeason,
  });
  final String seriesTitle;
  final List<Episode> episodes;
  final String current;
  final double Function(Episode) progressOf;
  final ValueChanged<Episode> onPick;
  final VoidCallback onClose;
  final int season;
  final List<int> seasons;
  final ValueChanged<int> onSeason;

  @override
  Widget build(BuildContext context) {
    final list = episodes.where((e) => e.season == season).toList();
    return PlayerSidePanel(
      right: true,
      width: 460,
      kicker: seriesTitle,
      title: 'Saison $season',
      onClose: onClose,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (seasons.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: PanelSegments<int>(
                  value: season,
                  options: [for (final n in seasons) (n, 'S$n')],
                  onChanged: onSeason,
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final e = list[i];
                final on = e.extId == current;
                return HoverBuilder(
                  onActivate: () => onPick(e),
                  focusRingRadius: 10,
                  builder: (context, hover) => GestureDetector(
                    onTap: () => onPick(e),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: on ? const Color(0x14FFFFFF) : (hover ? const Color(0x0FFFFFFF) : Colors.transparent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 136,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Artwork(url: e.image, label: '', decodeWidth: 280),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: ProgressLine(progressOf(e), height: 3, track: const Color(0x33FFFFFF)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    e.code,
                                    if (e.durationSec != null) formatSpan(Duration(seconds: e.durationSec!)),
                                  ].join(' · '),
                                  style: darkMono(12, height: 1),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  e.displayTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                                ),
                                if (on) ...[
                                  const SizedBox(height: 7),
                                  Text('EN COURS', style: darkLabel(color: DarkColors.accent, size: 12)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ pause

/// What a paused film or episode is: big title, synopsis and cast.
class PauseInfo extends StatelessWidget {
  const PauseInfo({
    super.key,
    required this.kicker,
    required this.title,
    required this.meta,
    this.synopsis,
    this.people = const [],
  });
  final String kicker;
  final String title;
  final String meta;
  final String? synopsis;
  final List<CastMember> people;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final titleSize = math.min(size.width * 0.07, size.height * 0.09).clamp(40.0, 104.0);
    final gap = (size.height * 0.02).clamp(10.0, 18.0);
    final showSyn = synopsis != null && synopsis!.isNotEmpty && size.height >= 640;
    final showCast = people.isNotEmpty && size.height >= (showSyn ? 820 : 640);
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xE6000000), Color(0x99000000), Color(0x40000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 48,
            top: 112,
            bottom: 180,
            width: math.min(660, size.width * 0.55),
            child: ClipRect(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EN PAUSE · ${kicker.toUpperCase()}',
                    style: darkLabel(color: DarkColors.accent, size: 13).copyWith(letterSpacing: 13 * 0.18),
                  ),
                  SizedBox(height: gap),
                  Text(title.toUpperCase(), maxLines: 3, overflow: TextOverflow.ellipsis, style: darkPoster(titleSize)),
                  if (meta.isNotEmpty) ...[
                    SizedBox(height: gap),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        color: DarkColors.textSoft,
                      ),
                    ),
                  ],
                  if (showSyn) ...[
                    SizedBox(height: gap),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Text(
                        synopsis!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, height: 1.5, color: DarkColors.textSoft),
                      ),
                    ),
                  ],
                  if (showCast) ...[
                    SizedBox(height: gap + 10),
                    Text('DISTRIBUTION', style: darkLabel(color: DarkColors.faint, size: 12)),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, box) {
                        final w = (box.maxWidth - 24) / 2;
                        return Wrap(
                          spacing: 24,
                          runSpacing: 14,
                          children: [
                            for (final p in people.take(4))
                              SizedBox(
                                width: w,
                                child: CastChip(member: p),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round portrait (or initials), name and part.
class CastChip extends StatelessWidget {
  const CastChip({super.key, required this.member, this.size = 48});
  final CastMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = member.name.split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    return Row(
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: DarkColors.borderInput, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: member.photo == null
              ? Text(
                  initials,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: DarkColors.muted),
                )
              : Image.network(
                  member.photo!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 2).round(),
                  errorBuilder: (_, _, _) => Text(
                    initials,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: DarkColors.muted),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.1),
              ),
              if (member.role != null) ...[
                const SizedBox(height: 5),
                Text(
                  member.role!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.1, color: DarkColors.muted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Live paused: the stream goes on in the cache.
class LivePausedBadge extends StatelessWidget {
  const LivePausedBadge({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: const Alignment(0, -0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 88,
                height: 88,
                color: const Color(0x990D0C0B),
                child: const Icon(Icons.pause_rounded, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Le direct continue · tu reprendras en différé',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: DarkColors.textSoft),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------- floating

/// "Épisode suivant" card in the last seconds of an episode.
class NextEpisodePrompt extends StatelessWidget {
  const NextEpisodePrompt({
    super.key,
    required this.episode,
    required this.secondsLeft,
    required this.auto,
    required this.onPlay,
    required this.onCancel,
  });
  final Episode episode;
  final int secondsLeft;
  final bool auto;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 380,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF2141210),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Artwork(url: episode.image, label: '', decodeWidth: 300),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ÉPISODE SUIVANT', style: darkLabel(color: DarkColors.accent, size: 12)),
                          const SizedBox(height: 7),
                          Text(
                            '${episode.code} · ${episode.displayTitle}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.2),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            auto ? 'Lecture dans ${math.max(0, secondsLeft)} s' : 'Prêt à démarrer',
                            style: darkMono(13, height: 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onPlay,
                        style: FilledButton.styleFrom(
                          backgroundColor: DarkColors.action,
                          foregroundColor: DarkColors.onAction,
                          minimumSize: const Size(0, 42),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          textStyle: const TextStyle(
                            fontFamily: AppFonts.body,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Lecture'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: onCancel,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0x1FFFFFFF),
                        foregroundColor: DarkColors.text,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        textStyle: const TextStyle(
                          fontFamily: AppFonts.body,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 3,
                child: ProgressLine(
                  ((20 - secondsLeft.clamp(0, 20)) / 20).toDouble(),
                  height: 3,
                  track: const Color(0x1FFFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Technical figures of the stream (key I).
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.stats, required this.onClose});
  final List<(String, String)> stats;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 48,
    top: 100,
    width: 300,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xD60D0C0B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'STATISTIQUES',
                    style: darkMono(
                      12,
                      weight: FontWeight.w600,
                      color: DarkColors.accent,
                      height: 1,
                    ).copyWith(letterSpacing: 12 * 0.08),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onClose,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('✕', style: darkMono(12, color: DarkColors.textSoft, height: 1)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final (k, v) in stats)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k, style: darkMono(12, height: 1.2)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          v.isEmpty ? 'inconnu' : v,
                          textAlign: TextAlign.right,
                          style: darkMono(12, color: DarkColors.text, height: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Quality of the stream ("FHD"): cycles through the qualities of a live
/// channel when it has several.
class QualityButton extends StatelessWidget {
  const QualityButton({super.key, required this.label, this.onTap, this.tooltip});
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? 'Qualité du flux',
    child: HoverBuilder(
      onActivate: onTap,
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: hover && onTap != null ? DarkColors.text : const Color(0x66FFFFFF)),
          ),
          child: Text(
            label,
            style: darkMono(12, weight: FontWeight.w600, color: DarkColors.text, height: 1),
          ),
        ),
      ),
    ),
  );
}

/// Label of a video size ("4K", "FHD", "HD", "SD").
String resolutionLabel(int? height) {
  if (height == null || height <= 0) return 'Auto';
  if (height >= 2000) return '4K';
  if (height >= 1000) return 'FHD';
  if (height >= 700) return 'HD';
  return 'SD';
}

/// Volume: mute button, slider shown on hover.
class VolumeControl extends StatefulWidget {
  const VolumeControl({super.key, required this.service, required this.onMute, required this.onChanged, this.remote});
  final PlayerService service;
  final VoidCallback onMute;
  final ValueChanged<double> onChanged;

  /// Volume of the TV (0 to 100) shown instead of the local one while casting.
  final double? remote;

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: StreamBuilder<double>(
      stream: widget.service.player.stream.volume,
      initialData: widget.service.player.state.volume,
      builder: (context, snap) {
        final v = widget.remote ?? snap.data ?? 100;
        final max = widget.remote != null ? 100.0 : 150.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerIconButton(
              icon: v == 0 ? Icons.volume_off_rounded : (v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              tooltip: 'Son (M)',
              onTap: widget.onMute,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _hover ? 110 : 0,
              height: 44,
              child: ClipRect(
                child: OverflowBox(
                  minWidth: 110,
                  maxWidth: 110,
                  minHeight: 44,
                  maxHeight: 44,
                  alignment: Alignment.centerLeft,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: DarkColors.text,
                      inactiveTrackColor: const Color(0x38FFFFFF),
                      thumbColor: DarkColors.text,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    // Hidden until hovered: out of the remote's way meanwhile
                    // (an invisible stop between the buttons).
                    child: ExcludeFocus(
                      excluding: !_hover,
                      child: Slider(value: v.clamp(0, max), max: max, onChanged: widget.onChanged),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
