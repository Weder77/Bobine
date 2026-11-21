import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'net_image.dart';

/// Rebuilds with the hover state of the mouse and, when [onActivate] is
/// given, with the keyboard / remote / gamepad focus too: the widget joins
/// the arrow-key navigation and Enter (or the gamepad's A) activates it.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
    this.onActivate,
    this.focusRingRadius,
    this.focusScale = 1,
    this.autofocus = false,
    this.onFocus,
    this.onContextMenu,
    this.onHighlight,
  });
  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;
  final VoidCallback? onActivate;

  /// Draws a white ring around the widget while it has the keyboard focus
  /// (cards draw their own ring from `hovered`).
  final double? focusRingRadius;

  /// Grows the widget slightly while focused (cards).
  final double focusScale;
  final bool autofocus;

  /// Called when the keyboard focus arrives.
  final VoidCallback? onFocus;

  /// Menu key / Maj+F10 while focused (right click is handled by the card).
  final ValueChanged<Offset>? onContextMenu;

  /// Hovered or focused changed (to lift the card above its neighbours).
  final ValueChanged<bool>? onHighlight;

  /// Holding OK this long opens the menu ([onContextMenu]): most TV remotes
  /// have no menu key.
  static const longPressDelay = Duration(milliseconds: 500);

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hover = false;
  bool _focus = false;

  void _set({bool? hover, bool? focus}) {
    final before = _hover || _focus;
    setState(() {
      _hover = hover ?? _hover;
      _focus = focus ?? _focus;
    });
    if (before != (_hover || _focus)) widget.onHighlight?.call(_hover || _focus);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onActivate == null) {
      return MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => _set(hover: true),
        onExit: (_) => _set(hover: false),
        child: widget.builder(context, _hover),
      );
    }
    var child = widget.builder(context, _hover || _focus);
    if (widget.focusRingRadius != null) {
      child = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.focusRingRadius!),
          border: Border.all(color: _focus ? AppColors.text : Colors.transparent, width: 2),
        ),
        child: child,
      );
    }
    if (widget.focusScale != 1) {
      child = AnimatedScale(
        scale: _focus ? widget.focusScale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: child,
      );
    }
    final detector = FocusableActionDetector(
      autofocus: widget.autofocus,
      shortcuts: widget.onContextMenu == null
          ? null
          : const {
              SingleActivator(LogicalKeyboardKey.contextMenu): _ContextMenuIntent(),
              SingleActivator(LogicalKeyboardKey.f10, shift: true): _ContextMenuIntent(),
            },
      mouseCursor: widget.cursor,
      onShowHoverHighlight: (v) => _set(hover: v),
      onShowFocusHighlight: (v) {
        _set(focus: v);
        if (v) widget.onFocus?.call();
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate!();
            return null;
          },
        ),
        if (widget.onContextMenu != null)
          _ContextMenuIntent: CallbackAction<_ContextMenuIntent>(
            onInvoke: (_) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) widget.onContextMenu!(box.localToGlobal(box.size.center(Offset.zero)));
              return null;
            },
          ),
      },
      child: child,
    );
    return RemoteOk(onActivate: widget.onActivate!, onMenu: widget.onContextMenu, child: detector);
  }
}

/// OK of a TV remote (and Enter, gamepad A) on the focused [child]: a short
/// press runs [onActivate] on release, holding it [HoverBuilder.longPressDelay]
/// opens the menu ([onMenu], at the centre of [child]); most remotes have no
/// menu key. Without [onMenu], [child] is returned as it is.
///
/// Put it around the widget that holds the focus: it handles the keys
/// before the app's shortcuts, which would activate on the press already.
class RemoteOk extends StatefulWidget {
  const RemoteOk({super.key, required this.onActivate, required this.onMenu, required this.child});

  final VoidCallback onActivate;
  final ValueChanged<Offset>? onMenu;
  final Widget child;

  @override
  State<RemoteOk> createState() => _RemoteOkState();
}

class _RemoteOkState extends State<RemoteOk> {
  Timer? _held;
  bool _menuShown = false;

  static final _okKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  void dispose() {
    _held?.cancel();
    super.dispose();
  }

  void _openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.attached) widget.onMenu?.call(box.localToGlobal(box.size.center(Offset.zero)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_okKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _held?.cancel();
      _menuShown = false;
      _held = Timer(HoverBuilder.longPressDelay, () {
        _menuShown = true;
        if (mounted) _openMenu();
      });
    } else if (e is KeyUpEvent) {
      final wasHeld = _held != null;
      _held?.cancel();
      _held = null;
      if (wasHeld && !_menuShown) widget.onActivate();
      _menuShown = false;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => widget.onMenu == null
      ? widget.child
      : Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: widget.child);
}

class _ContextMenuIntent extends Intent {
  const _ContextMenuIntent();
}

/// Gives the focus to the first focusable widget of [child] when it
/// appears (the main action of a page, for a TV remote). Unlike a focus
/// scope, the arrows then leave it freely.
class FocusFirstChild extends StatefulWidget {
  const FocusFirstChild({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<FocusFirstChild> createState() => _FocusFirstChildState();
}

class _FocusFirstChildState extends State<FocusFirstChild> {
  final _node = FocusNode(debugLabel: 'focus first', canRequestFocus: false, skipTraversal: true);

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}

/// White ring around [child] while something inside it has the keyboard /
/// gamepad focus (for menus and buttons whose own focus effect is hidden
/// under the glass).
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.radius = 999});
  final Widget child;
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (f) =>
        setState(() => _on = f && FocusManager.instance.highlightMode == FocusHighlightMode.traditional),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: _on ? AppColors.text : Colors.transparent, width: 2),
      ),
      child: widget.child,
    ),
  );
}

/// Thin progress bar (accent on a translucent track).
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.height = 4, this.color, this.track});
  final double value;
  final double height;
  final Color? color;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: track ?? AppColors.ink.withValues(alpha: 0.14)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: color ?? AppColors.accent),
          ),
        ],
      ),
    ),
  );
}

/// Focus / hover ring used by cards: a white outline and a deep shadow.
BoxDecoration focusRing({required bool on, double radius = 12, Color? halo}) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: on ? AppColors.text : Colors.transparent, width: 2),
  boxShadow: on
      ? [BoxShadow(color: halo ?? AppColors.shadow(0x99), blurRadius: 28, offset: const Offset(0, 12))]
      : null,
);

/// Saturation matrix for the glass effect.
List<double> _saturation(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// "Liquid glass" surface: blurs and saturates what is behind it, with a
/// light rim on the top edge and a soft drop shadow.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    this.height,
    this.strong = false,
    this.shadow = true,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? height;

  /// Brighter glass (selected tab inside a glass bar).
  final bool strong;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? [BoxShadow(color: AppColors.shadow(0x59), blurRadius: 32, offset: Offset(0, 12))] : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: ColorFilter.matrix(_saturation(1.8)),
            inner: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          ),
          child: CustomPaint(
            foregroundPainter: _GlassRim(radius: radius, strong: strong),
            child: Container(
              height: height,
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: strong
                      ? [AppColors.ink.withAlpha(0x61), AppColors.ink.withAlpha(0x29)]
                      : [AppColors.ink.withAlpha(0x38), AppColors.ink.withAlpha(0x12)],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassRim extends CustomPainter {
  _GlassRim({required this.radius, required this.strong});
  final double radius;
  final bool strong;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius.clamp(0, size.height / 2)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: strong
            ? [AppColors.ink.withAlpha(0xB3), AppColors.ink.withAlpha(0x33), AppColors.ink.withAlpha(0x1A)]
            : [AppColors.ink.withAlpha(0x99), AppColors.ink.withAlpha(0x26), AppColors.ink.withAlpha(0x1F)],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(_GlassRim old) => old.radius != radius || old.strong != strong;
}

/// Round outlined icon action ("Ma liste", "Recommencer").
class RoundAction extends StatelessWidget {
  const RoundAction({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 24,
    style:
        IconButton.styleFrom(
          fixedSize: const Size(54, 54),
          backgroundColor: AppColors.bg.withAlpha(0x66),
          shape: const CircleBorder(),
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused)
                ? BorderSide(color: AppColors.accent, width: 2.5)
                : BorderSide(color: AppColors.ink.withAlpha(0x8C), width: 2),
          ),
        ),
    icon: Icon(icon, color: color ?? AppColors.text),
  );
}

/// Poster (2:3) card for movies and series.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.subtitle,
    this.rating,
    this.progress,
    this.favorite = false,
    this.width = 168,
    this.onContextMenu,
  });

  final String title;
  final String? image;
  final String? subtitle;
  final double? rating;
  final double? progress;
  final bool favorite;
  final double width;
  final VoidCallback onTap;

  /// Right click / long press / menu key: quick actions at that position.
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: HoverBuilder(
        onActivate: onTap,
        onContextMenu: onContextMenu,
        focusScale: 1.04,
        builder: (context, hover) {
          return Semantics(
            button: true,
            label: title,
            child: GestureDetector(
              onTap: onTap,
              onSecondaryTapUp: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
              onLongPressStart: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: focusRing(on: hover, radius: 12),
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              NetImage(image, decodeWidth: width, placeholder: _TitlePlaceholder(title)),
                              if (rating != null && rating! > 0)
                                Positioned(top: 8, left: 8, child: RatingBadge(rating!)),
                              if (favorite)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: AppColors.bg.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.favorite_rounded, color: AppColors.cueSeries, size: 15),
                                  ),
                                ),
                              if (progress != null && progress! > 0)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: ProgressLine(progress!, track: AppColors.ink.withAlpha(0x40)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
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
}

class _TitlePlaceholder extends StatelessWidget {
  const _TitlePlaceholder(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surface3,
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(title, maxLines: 4, overflow: TextOverflow.ellipsis, style: posterStyle(34)),
      ),
    ),
  );
}

class RatingBadge extends StatelessWidget {
  const RatingBadge(this.rating, {super.key});
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: AppColors.bg.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(7)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
        const SizedBox(width: 3),
        Text(
          rating.toStringAsFixed(1).replaceAll('.', ','),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Square channel logo with initials fallback.
/// Channel badge: a cream tile with the playlist logo, or the channel's
/// initials in Big Shoulders ("TF1", "F2", "M6") when there is none.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.name, required this.url, this.size = 44});
  final String name;
  final String? url;
  final double size;

  static String initials(String name) {
    final clean = name
        .replaceAll(RegExp(r'^\s*(\|[A-Z]{2,4}\||[A-Z]{2,3}\s*[:|-])\s*'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ+ ]'), ' ')
        .replaceAll(RegExp(r'\b(hd|fhd|uhd|4k|sd|hevc)\b', caseSensitive: false), ' ')
        .trim();
    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.length <= 4 ? words.first : words.first.substring(0, 3);
    if (RegExp(r'^\d+$').hasMatch(words[1])) return '${words[0][0]}${words[1]}'.toUpperCase();
    return '${words[0].characters.first}${words[1].characters.first}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials(name),
          maxLines: 1,
          style: posterStyle(size * 0.42, color: DarkColors.onAction, height: 1),
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(size * 0.24),
        // On the light theme the cream badge needs an edge.
        border: AppColors.isLight ? Border.all(color: AppColors.borderInput) : null,
      ),
      child: NetImage(url, fit: BoxFit.contain, decodeWidth: size, placeholder: placeholder),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 34, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: displayStyle(22)),
          if (message != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}

/// Entry of a category rail.
class CategoryEntry {
  const CategoryEntry({required this.id, required this.label, this.count, this.icon, this.locked = false});
  final String id;
  final String label;
  final int? count;
  final IconData? icon;

  /// Behind the parental code (shown with a padlock once unlocked).
  final bool locked;
}

/// Copy of [entries] with the "fav" entry showing [count] (the counters are
/// otherwise only computed when the screen loads).
List<CategoryEntry> withFavoriteCount(List<CategoryEntry> entries, int count) => [
  for (final e in entries)
    e.id == 'fav' ? CategoryEntry(id: e.id, label: e.label, count: count, icon: e.icon, locked: e.locked) : e,
];

/// Small pill label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.textColor, this.icon});
  final String text;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: color ?? AppColors.surface3, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: textColor ?? AppColors.text), const SizedBox(width: 5)],
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textColor ?? AppColors.text),
        ),
      ],
    ),
  );
}

/// Outlined quality tag ("4K", "5.1").
class QualityTag extends StatelessWidget {
  const QualityTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.ink.withAlpha(0x73)),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.1)),
  );
}

/// Red "DIRECT" badge.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.label = 'DIRECT'});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: AppColors.liveBadge, borderRadius: BorderRadius.circular(5)),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: Colors.white),
    ),
  );
}
