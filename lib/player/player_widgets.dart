import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/format.dart';
import '../core/theme.dart';
import 'player_service.dart';

const Map<String, String> _languages = {
  'fr': 'Français',
  'fre': 'Français',
  'fra': 'Français',
  'en': 'Anglais',
  'eng': 'Anglais',
  'es': 'Espagnol',
  'spa': 'Espagnol',
  'de': 'Allemand',
  'ger': 'Allemand',
  'deu': 'Allemand',
  'it': 'Italien',
  'ita': 'Italien',
  'pt': 'Portugais',
  'por': 'Portugais',
  'ar': 'Arabe',
  'ara': 'Arabe',
  'tr': 'Turc',
  'tur': 'Turc',
  'nl': 'Néerlandais',
  'dut': 'Néerlandais',
  'nld': 'Néerlandais',
  'ja': 'Japonais',
  'jpn': 'Japonais',
  'ko': 'Coréen',
  'kor': 'Coréen',
  'zh': 'Chinois',
  'chi': 'Chinois',
  'zho': 'Chinois',
  'ru': 'Russe',
  'rus': 'Russe',
  'pl': 'Polonais',
  'pol': 'Polonais',
  'und': 'Indéterminée',
  'qaa': 'VO',
  'mul': 'Multiple',
};

String languageName(String? code) {
  if (code == null || code.isEmpty) return '';
  return _languages[code.toLowerCase()] ?? code.toUpperCase();
}

/// Main line of an audio track: "Français (VF)".
String audioTrackTitle(AudioTrack t, int index) {
  final lang = languageName(t.language);
  final title = t.title?.trim();
  if (lang.isNotEmpty && title != null && title.isNotEmpty && title.toLowerCase() != lang.toLowerCase()) {
    return '$lang ($title)';
  }
  if (lang.isNotEmpty) return lang;
  if (title != null && title.isNotEmpty) return title;
  return 'Piste ${index + 1}';
}

/// Second line of an audio track: "E-AC3 · 5.1".
String audioTrackDetail(AudioTrack t) => [
  if (t.codec != null) codecLabel(t.codec!),
  if (t.channelscount != null) channelLayoutLabel(t.channelscount!),
].join(' · ');

String subtitleTrackTitle(SubtitleTrack t, int index) {
  final lang = languageName(t.language);
  final title = t.title?.trim();
  if (lang.isNotEmpty && title != null && title.isNotEmpty && title.toLowerCase() != lang.toLowerCase()) {
    return '$lang ($title)';
  }
  if (lang.isNotEmpty) return lang;
  if (title != null && title.isNotEmpty) return title;
  return 'Sous-titres ${index + 1}';
}

String subtitleTrackDetail(SubtitleTrack t) => t.codec == null ? '' : codecLabel(t.codec!);

/// One-line labels (used by the on-screen messages).
String audioTrackLabel(AudioTrack t, int index) {
  final d = audioTrackDetail(t);
  return d.isEmpty ? audioTrackTitle(t, index) : '${audioTrackTitle(t, index)} · $d';
}

String subtitleTrackLabel(SubtitleTrack t, int index) {
  if (t.id == 'no') return 'Désactivés';
  final d = subtitleTrackDetail(t);
  return d.isEmpty ? subtitleTrackTitle(t, index) : '${subtitleTrackTitle(t, index)} · $d';
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

  Duration _at(double fraction) => Duration(milliseconds: (fraction.clamp(0.0, 1.0) * _total).round());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
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
                      left: (tip * w - 34).clamp(0.0, w - 68),
                      top: -28,
                      child: Container(
                        width: 68,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF20242E),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          formatDuration(_at(tip)),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    final h = thick ? 7.0 : 6.0;
    final y = size.height / 2;
    final r = Radius.circular(h / 2);
    RRect bar(double from, double to) => RRect.fromLTRBR(from * size.width, y - h / 2, to * size.width, y + h / 2, r);

    canvas.drawRRect(bar(0, 1), Paint()..color = const Color(0x40FFFFFF));
    if (total > 0) {
      final cached = Paint()..color = const Color(0x80FFFFFF);
      for (final c in ranges) {
        final a = (c.start.inMilliseconds / total).clamp(0.0, 1.0);
        final b = (c.end.inMilliseconds / total).clamp(0.0, 1.0);
        if (b > a) canvas.drawRRect(bar(a, b), cached);
      }
    }
    final p = played.clamp(0.0, 1.0);
    canvas.drawRRect(bar(0, p), Paint()..color = AppColors.accent);
    final cx = p * size.width;
    canvas.drawCircle(Offset(cx, y), thick ? 13 : 11, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.played != played || old.ranges != ranges || old.total != total || old.thick != thick;
}

/// Icon button used on the video (48 px; [big] = round accent play button).
class OverlayButton extends StatelessWidget {
  const OverlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.big = false,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool big;

  /// Pressed / open state (light background).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      iconSize: big ? 44 : 30,
      style: IconButton.styleFrom(
        foregroundColor: AppColors.text,
        disabledForegroundColor: Colors.white24,
        backgroundColor: active ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
        fixedSize: Size.square(big ? 60 : 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// One entry of a [ChoiceMenu].
class ChoiceItem<T> {
  const ChoiceItem(this.value, this.title, {this.detail, this.selected = false});
  final T value;
  final String title;
  final String? detail;
  final bool selected;
}

/// Popup menu of choices (tracks, speed, format): two-line entries, the
/// selected one highlighted with a check.
class ChoiceMenu<T> extends StatefulWidget {
  const ChoiceMenu({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.header,
    required this.items,
    required this.onSelected,
    this.onOpened,
    this.onClosed,
  });
  final IconData icon;
  final String tooltip;

  /// Upper-case header ("PISTE AUDIO · A").
  final String header;
  final List<ChoiceItem<T>> Function() items;
  final ValueChanged<T> onSelected;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  @override
  State<ChoiceMenu<T>> createState() => _ChoiceMenuState<T>();
}

class _ChoiceMenuState<T> extends State<ChoiceMenu<T>> {
  bool _open = false;

  static const _headerHeight = 34.0;
  static const _maxHeight = 480.0;

  static double _itemHeight(ChoiceItem item) => (item.detail?.isNotEmpty ?? false) ? 60 : 46;

  /// Opens the menu just above the button, right-aligned with it.
  Future<void> _show() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final list = widget.items();
    final content = list.isEmpty ? 48.0 : list.fold(0.0, (sum, i) => sum + _itemHeight(i));
    final height = math.min(_maxHeight, 16 + _headerHeight + content);
    final top = math.max(8.0, rect.top - 10 - height);

    setState(() => _open = true);
    widget.onOpened?.call();
    final value = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(rect.left, top, overlay.size.width - rect.right, overlay.size.height - top),
      color: AppColors.surface2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      menuPadding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 420, maxHeight: _maxHeight),
      items: _entries(list),
    );
    if (mounted) setState(() => _open = false);
    widget.onClosed?.call();
    if (value != null) widget.onSelected(value);
  }

  List<PopupMenuEntry<T>> _entries(List<ChoiceItem<T>> list) => [
    PopupMenuItem<T>(
      enabled: false,
      height: _headerHeight,
      child: Text(widget.header, style: labelStyle()),
    ),
    if (list.isEmpty) const PopupMenuItem(enabled: false, child: Text('Aucune piste disponible')),
    for (final item in list)
      PopupMenuItem<T>(
        value: item.value,
        padding: EdgeInsets.zero,
        height: _itemHeight(item),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: item.selected ? const Color(0x1FFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: item.selected ? const Icon(Icons.check_rounded, size: 20, color: AppColors.text) : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: item.selected ? FontWeight.w700 : FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    if (item.detail?.isNotEmpty ?? false)
                      Text(item.detail!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) =>
      OverlayButton(icon: widget.icon, tooltip: widget.tooltip, active: _open, onPressed: _show);
}
