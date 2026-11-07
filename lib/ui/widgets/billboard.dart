import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'brand.dart';
import 'cards.dart';
import 'net_image.dart';

/// One title of the billboard.
class HeroEntry {
  const HeroEntry({
    required this.key,
    required this.kicker,
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
    this.rating,
    this.year,
    this.genre,
    this.duration,
    this.quality,
    this.synopsis,
    this.backdrop,
    this.poster,
    this.progress,
    this.progressLabel,
    this.onInfo,
    this.favorite = false,
    this.onFavorite,
  });

  /// Identity of the title (hue of the tint when there is no image).
  final String key;
  final String kicker;
  final String title;
  final double? rating;
  final String? year;
  final String? genre;
  final String? duration;
  final String? quality;
  final String? synopsis;
  final String? backdrop;
  final String? poster;
  final double? progress;
  final String? progressLabel;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onInfo;
  final bool favorite;
  final VoidCallback? onFavorite;
}

/// Full-width billboard: titles cross-fade (1 s) with a slow Ken Burns zoom
/// (1.08 → 1 over 9 s), progress bars on the right advance every
/// [interval]; clicking a bar jumps to its title.
class Billboard extends StatefulWidget {
  const Billboard({
    super.key,
    required this.entries,
    this.minHeight = 640,
    this.maxHeight = 820,
    this.heightFactor = 0.88,
    this.bottomPadding = 270,
    this.controlsBottom = 290,
    this.topPadding = 112,
    this.autoplay = true,
    this.interval = const Duration(seconds: 7),
  });
  final List<HeroEntry> entries;
  final double minHeight;
  final double maxHeight;
  final double heightFactor;
  final double bottomPadding;
  final double controlsBottom;
  final double topPadding;
  final bool autoplay;
  final Duration interval;

  /// Height of the billboard for a window of [size] (CSS clamp(min, f·vh, max)).
  static double heightFor(Size size, double min, double max, double factor) => (size.height * factor).clamp(min, max);

  @override
  State<Billboard> createState() => _BillboardState();
}

class _BillboardState extends State<Billboard> with TickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _bar = AnimationController(vsync: this, duration: widget.interval)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go(_index + 1);
    });

  /// Ken Burns of each title (1.08 → 1 over 9 s), restarted when it shows.
  final List<AnimationController> _zoom = [];

  @override
  void initState() {
    super.initState();
    _syncZoom();
    _zoom.firstOrNull?.forward(from: 0);
    _restart();
  }

  void _syncZoom() {
    while (_zoom.length < widget.entries.length) {
      _zoom.add(AnimationController(vsync: this, duration: const Duration(seconds: 9)));
    }
    while (_zoom.length > widget.entries.length) {
      _zoom.removeLast().dispose();
    }
  }

  @override
  void didUpdateWidget(Billboard old) {
    super.didUpdateWidget(old);
    _syncZoom();
    if (_index >= widget.entries.length) _index = 0;
    if (old.autoplay != widget.autoplay || old.interval != widget.interval) {
      _bar.duration = widget.interval;
      _restart();
    }
  }

  @override
  void dispose() {
    _bar.dispose();
    for (final z in _zoom) {
      z.dispose();
    }
    super.dispose();
  }

  void _restart() {
    _bar.stop();
    _bar.value = 0;
    if (widget.autoplay && widget.entries.length > 1) _bar.forward();
  }

  void _go(int i) {
    if (widget.entries.isEmpty || !mounted) return;
    setState(() => _index = i % widget.entries.length);
    if (_index < _zoom.length) _zoom[_index].forward(from: 0);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final height = Billboard.heightFor(size, widget.minHeight, widget.maxHeight, widget.heightFactor);
    final e = entries[_index];
    final titleSize = math.min(size.width * 0.076, size.height * 0.11).clamp(56.0, 116.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.bg),
          for (var i = 0; i < entries.length; i++)
            AnimatedOpacity(
              opacity: i == _index ? 1 : 0,
              duration: const Duration(seconds: 1),
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _zoom[i],
                  builder: (context, child) => Transform.scale(scale: 1.08 - 0.08 * _zoom[i].value, child: child),
                  child: _Art(entry: entries[i], top: widget.topPadding, bottom: widget.controlsBottom + 40),
                ),
              ),
            ),
          // Left and bottom fades, as in the design.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xF00D0C0B), Color(0x9E0D0C0B), Color(0x000D0C0B)],
                  stops: [0, 0.34, 0.62],
                ),
              ),
            ),
          ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppColors.bg, Color(0xE00D0C0B), Color(0x000D0C0B)],
                  stops: [0, 0.24, 0.52],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(48, widget.topPadding, 48, widget.bottomPadding),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(
                width: math.min(740, size.width * 0.62),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                  child: _Content(key: ValueKey(e.key), entry: e, titleSize: titleSize),
                ),
              ),
            ),
          ),
          if (entries.length > 1)
            Positioned(
              right: 48,
              bottom: widget.controlsBottom,
              child: Row(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Semantics(
                      button: true,
                      label: 'À la une ${i + 1}',
                      child: GestureDetector(
                        onTap: () => _go(i),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: _Bar(
                              animation: _bar,
                              state: i < _index ? 1 : (i == _index ? (widget.autoplay ? null : 1) : 0),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 40 × 3 bar: full, empty, or filling with [animation] (state null).
class _Bar extends StatelessWidget {
  const _Bar({required this.animation, required this.state});
  final Animation<double> animation;
  final double? state;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 3,
    decoration: BoxDecoration(color: const Color(0x47FFFFFF), borderRadius: BorderRadius.circular(2)),
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.centerLeft,
    child: state != null
        ? FractionallySizedBox(
            widthFactor: state,
            heightFactor: 1,
            child: const ColoredBox(color: AppColors.text),
          )
        : AnimatedBuilder(
            animation: animation,
            builder: (context, _) => FractionallySizedBox(
              widthFactor: animation.value,
              heightFactor: 1,
              child: const ColoredBox(color: AppColors.text),
            ),
          ),
  );
}

/// Backdrop, else the poster blurred over the title's tint with the poster
/// itself on the right.
class _Art extends StatelessWidget {
  const _Art({required this.entry, required this.top, required this.bottom});
  final HeroEntry entry;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final tint = DecoratedBox(decoration: BoxDecoration(gradient: AppColors.placeholderGradient(hueOf(entry.key))));
    if (entry.backdrop != null) {
      return NetImage(entry.backdrop, decodeWidth: 1920, alignment: const Alignment(0.4, -0.4), placeholder: tint);
    }
    if (entry.poster == null) return tint;
    final width = MediaQuery.sizeOf(context).width;
    return Stack(
      fit: StackFit.expand,
      children: [
        tint,
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
          child: Opacity(opacity: 0.55, child: NetImage(entry.poster, decodeWidth: 320)),
        ),
        if (width >= 1000)
          Positioned(
            right: math.max(64, width * 0.1),
            top: top,
            bottom: bottom,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 50, offset: Offset(0, 24))],
                ),
                clipBehavior: Clip.antiAlias,
                child: NetImage(entry.poster, decodeWidth: 400),
              ),
            ),
          ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({super.key, required this.entry, required this.titleSize});
  final HeroEntry entry;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    const dot = Text('•', style: TextStyle(color: AppColors.placeholder, fontSize: 15));
    final meta = <Widget>[
      if (e.rating != null && e.rating! > 0) ...[
        const Icon(Icons.star_rounded, size: 17, color: AppColors.accent),
        Text(
          e.rating!.toStringAsFixed(1).replaceAll('.', ','),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
      for (final m in [e.year, e.genre, e.duration])
        if (m != null && m.isNotEmpty) ...[
          dot,
          Text(m, style: const TextStyle(fontSize: 15, color: AppColors.textSoft)),
        ],
      if (e.quality != null) QualityBadge(e.quality!),
    ];
    // The first element must not start with a dot.
    if (meta.isNotEmpty && meta.first == dot) meta.removeAt(0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const BobineReel(height: 16),
            const SizedBox(width: 10),
            Flexible(
              child: Text(e.kicker.toUpperCase(), style: labelStyle(color: AppColors.accent, size: 13)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          e.title.toUpperCase(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: posterStyle(
            titleSize,
            shadows: const [Shadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 6))],
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
        ],
        if (e.progress != null) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: e.progress,
                    minHeight: 4,
                    backgroundColor: const Color(0x38FFFFFF),
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(e.progressLabel ?? '', style: const TextStyle(fontSize: 14, color: AppColors.textSoft)),
            ],
          ),
        ],
        if (e.synopsis != null && e.synopsis!.isNotEmpty) ...[
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              e.synopsis!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.textSoft),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            HeroButton.primary(label: e.primaryLabel, icon: Icons.play_arrow_rounded, onTap: e.onPrimary),
            if (e.onInfo != null)
              HeroButton.secondary(label: "Plus d'infos", icon: Icons.info_outline_rounded, onTap: e.onInfo!),
            if (e.onFavorite != null)
              RoundOutlineButton(
                icon: e.favorite ? Icons.check_rounded : Icons.add_rounded,
                tooltip: e.favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
                onTap: e.onFavorite!,
              ),
          ],
        ),
      ],
    );
  }
}

/// "FHD" outlined badge (mono 11).
class QualityBadge extends StatelessWidget {
  const QualityBadge(this.label, {super.key, this.strong = false});
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: strong ? AppColors.text : const Color(0x59FFFFFF)),
    ),
    child: Text(
      label,
      style: monoStyle(11, weight: FontWeight.w600, color: AppColors.text, height: 1),
    ),
  );
}

/// Hero buttons: white "Lecture" and warm translucent "Plus d'infos"
/// (52 px, rounded 8, 17 px).
class HeroButton extends StatelessWidget {
  const HeroButton._({required this.label, required this.icon, required this.onTap, required this.primary});
  const HeroButton.primary({Key? key, required String label, required IconData icon, required VoidCallback onTap})
    : this._(label: label, icon: icon, onTap: onTap, primary: true);
  const HeroButton.secondary({Key? key, required String label, required IconData icon, required VoidCallback onTap})
    : this._(label: label, icon: icon, onTap: onTap, primary: false);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: AppColors.action,
            foregroundColor: AppColors.onAction,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.fromLTRB(22, 0, 28, 0),
            textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w700),
          )
        : FilledButton.styleFrom(
            backgroundColor: AppColors.frosted,
            foregroundColor: AppColors.text,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.fromLTRB(20, 0, 24, 0),
            textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w600),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) ? AppColors.frostedHover : AppColors.frosted,
            ),
          );
    return FilledButton.icon(onPressed: onTap, style: style, icon: Icon(icon, size: 24), label: Text(label));
  }
}

/// Round outlined button ("+", sound): 52 px, white border on hover.
class RoundOutlineButton extends StatelessWidget {
  const RoundOutlineButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 52});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onTap,
      iconSize: 22,
      style:
          IconButton.styleFrom(
            fixedSize: Size(size, size),
            backgroundColor: const Color(0x4D0D0C0B),
            foregroundColor: AppColors.text,
            shape: const CircleBorder(),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
                    ? AppColors.text
                    : const Color(0x80FFFFFF),
                width: 1.5,
              ),
            ),
          ),
      icon: Icon(icon),
    ),
  );
}
