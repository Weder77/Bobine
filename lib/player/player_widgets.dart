import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/format.dart';
import '../core/theme.dart';
import 'player_service.dart';

const Map<String, String> _languages = {
  'fr': 'Français', 'fre': 'Français', 'fra': 'Français',
  'en': 'Anglais', 'eng': 'Anglais',
  'es': 'Espagnol', 'spa': 'Espagnol',
  'de': 'Allemand', 'ger': 'Allemand', 'deu': 'Allemand',
  'it': 'Italien', 'ita': 'Italien',
  'pt': 'Portugais', 'por': 'Portugais',
  'ar': 'Arabe', 'ara': 'Arabe',
  'tr': 'Turc', 'tur': 'Turc',
  'nl': 'Néerlandais', 'dut': 'Néerlandais', 'nld': 'Néerlandais',
  'ja': 'Japonais', 'jpn': 'Japonais',
  'ko': 'Coréen', 'kor': 'Coréen',
  'zh': 'Chinois', 'chi': 'Chinois', 'zho': 'Chinois',
  'ru': 'Russe', 'rus': 'Russe',
  'pl': 'Polonais', 'pol': 'Polonais',
  'und': 'Indéterminée', 'qaa': 'VO', 'mul': 'Multiple',
};

String languageName(String? code) {
  if (code == null || code.isEmpty) return '';
  return _languages[code.toLowerCase()] ?? code.toUpperCase();
}

String channelLayout(int n) => switch (n) {
      1 => 'Mono',
      2 => 'Stéréo',
      6 => '5.1',
      8 => '7.1',
      _ => '$n canaux',
    };

String audioTrackLabel(AudioTrack t, int index) {
  if (t.id == 'auto') return 'Automatique';
  if (t.id == 'no') return 'Désactivé';
  final parts = <String>[
    if (t.title != null && t.title!.isNotEmpty) t.title!,
    if (languageName(t.language).isNotEmpty) languageName(t.language),
    if (t.codec != null) t.codec!.toUpperCase(),
    if (t.channelscount != null) channelLayout(t.channelscount!),
  ];
  return parts.isEmpty ? 'Piste ${index + 1}' : parts.toSet().join(' · ');
}

String subtitleTrackLabel(SubtitleTrack t, int index) {
  if (t.id == 'auto') return 'Automatique';
  if (t.id == 'no') return 'Désactivés';
  final parts = <String>[
    if (t.title != null && t.title!.isNotEmpty) t.title!,
    if (languageName(t.language).isNotEmpty) languageName(t.language),
    if (t.codec != null) t.codec!.toUpperCase(),
  ];
  return parts.isEmpty ? 'Sous-titres ${index + 1}' : parts.toSet().join(' · ');
}

/// Seek bar that shows every cached range (what can be reached instantly).
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.ranges,
    required this.onSeek,
    this.onInteraction,
  });

  final Duration position;
  final Duration duration;
  final List<CachedRange> ranges;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onInteraction;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;
  double? _hover;

  double get _total => widget.duration.inMilliseconds.toDouble();

  Duration _at(double fraction) =>
      Duration(milliseconds: (fraction.clamp(0.0, 1.0) * _total).round());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      double frac(double dx) => (dx / w).clamp(0.0, 1.0);
      final shown = _drag ?? (_total <= 0 ? 0.0 : widget.position.inMilliseconds / _total);
      final active = _drag != null || _hover != null;
      final tip = _drag ?? _hover;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (e) => setState(() => _hover = frac(e.localPosition.dx)),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            widget.onInteraction?.call();
            widget.onSeek(_at(frac(d.localPosition.dx)));
          },
          onHorizontalDragStart: (d) => setState(() => _drag = frac(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) {
            widget.onInteraction?.call();
            setState(() => _drag = frac(d.localPosition.dx));
          },
          onHorizontalDragEnd: (_) {
            if (_drag != null) widget.onSeek(_at(_drag!));
            setState(() => _drag = null);
          },
          child: SizedBox(
            height: 34,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SeekPainter(
                    played: shown.toDouble(),
                    ranges: widget.ranges,
                    total: _total,
                    thick: active,
                  ),
                ),
              ),
              if (tip != null && _total > 0)
                Positioned(
                  left: (tip * w - 32).clamp(0.0, w - 64),
                  top: -26,
                  child: Container(
                    width: 64,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(formatDuration(_at(tip)),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({required this.played, required this.ranges, required this.total, required this.thick});
  final double played;
  final List<CachedRange> ranges;
  final double total;
  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final h = thick ? 6.0 : 4.0;
    final y = size.height / 2;
    final r = Radius.circular(h / 2);
    RRect bar(double from, double to) =>
        RRect.fromLTRBR(from * size.width, y - h / 2, to * size.width, y + h / 2, r);

    canvas.drawRRect(bar(0, 1), Paint()..color = const Color(0x33FFFFFF));
    if (total > 0) {
      final cached = Paint()..color = const Color(0x66FFFFFF);
      for (final c in ranges) {
        final a = (c.start.inMilliseconds / total).clamp(0.0, 1.0);
        final b = (c.end.inMilliseconds / total).clamp(0.0, 1.0);
        if (b > a) canvas.drawRRect(bar(a, b), cached);
      }
    }
    canvas.drawRRect(bar(0, played.clamp(0.0, 1.0)), Paint()..color = AppColors.accent);
    canvas.drawCircle(Offset(played.clamp(0.0, 1.0) * size.width, y), thick ? 8 : 6,
        Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.played != played || old.ranges != ranges || old.total != total || old.thick != thick;
}

/// Round translucent icon button used on the video.
class OverlayButton extends StatelessWidget {
  const OverlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 24,
    this.big = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      iconSize: big ? 34 : size,
      padding: EdgeInsets.all(big ? 10 : 8),
      color: Colors.white,
      disabledColor: Colors.white24,
      style: IconButton.styleFrom(
        backgroundColor: big ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
      ),
      icon: Icon(icon),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Popup menu with a check mark on the selected entry.
class ChoiceMenu<T> extends StatelessWidget {
  const ChoiceMenu({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.items,
    required this.onSelected,
    this.onOpened,
    this.onClosed,
  });
  final IconData icon;
  final String tooltip;
  final List<(T value, String label, bool selected)> Function() items;
  final ValueChanged<T> onSelected;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white),
      position: PopupMenuPosition.over,
      onOpened: onOpened,
      onCanceled: onClosed,
      onSelected: (v) {
        onClosed?.call();
        onSelected(v);
      },
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 420, maxHeight: 460),
      itemBuilder: (context) {
        final list = items();
        if (list.isEmpty) {
          return [
            const PopupMenuItem(enabled: false, child: Text('Aucune piste disponible')),
          ];
        }
        return [
          PopupMenuItem<T>(enabled: false, height: 32, child: Text(tooltip,
              style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700))),
          for (final (value, label, selected) in list)
            PopupMenuItem<T>(
              value: value,
              height: 40,
              child: Row(children: [
                SizedBox(
                  width: 26,
                  child: selected ? const Icon(Icons.check, size: 18, color: AppColors.accent) : null,
                ),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? AppColors.accent : AppColors.text)),
                ),
              ]),
            ),
        ];
      },
    );
  }
}
