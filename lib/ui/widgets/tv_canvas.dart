import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/device.dart';

/// Lays the whole app out on a fixed 1280 × 720 stage, scaled to fill the
/// screen (letterboxed when the screen is not 16:9).
///
/// A 1080p TV reports itself to Flutter as 960 × 540 logical points, too
/// small for screens drawn for a computer; on the stage they get the room
/// of a 1280 × 720 window, and text stays sharp (the scaling happens when
/// painting, at the screen's resolution). Taps are scaled back the same way.
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});

  final Widget child;

  static const Size size = Size(1280, 720);

  /// Margin kept clear of the TV's edges (Android TV guidelines: 5 %).
  static const EdgeInsets safe = EdgeInsets.symmetric(horizontal: 64, vertical: 36);

  /// The remote has no Tab key: in a one-line text field, Up / Down move
  /// to the field above / below (the field keeps them otherwise: start / end
  /// of the text), and Left / Right too once the caret is at the start / end.
  static KeyEventResult _leaveTextField(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final direction = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    // In a dialog (parental code, confirmation…), Up / Down go through every
    // item in reading order, as in the forms (TvFormNav).
    final vertical = direction == TraversalDirection.up || direction == TraversalDirection.down;
    final route = focus?.context == null ? null : ModalRoute.of(focus!.context!);
    if (vertical && route is RawDialogRoute) return TvFormNav._onKey(node, e);
    final field = focus?.context?.findAncestorWidgetOfExactType<EditableText>();
    if (focus == null || field == null || field.maxLines != 1) return KeyEventResult.ignored;
    final sel = field.controller.selection;
    final atStart = !sel.isValid || (sel.isCollapsed && sel.baseOffset == 0);
    final atEnd = !sel.isValid || (sel.isCollapsed && sel.baseOffset >= field.controller.text.length);
    if (direction == TraversalDirection.left && !atStart) return KeyEventResult.ignored;
    if (direction == TraversalDirection.right && !atEnd) return KeyEventResult.ignored;
    focus.focusInDirection(direction);
    return KeyEventResult.handled;
  }

  /// Stage points per screen point (the stage is letterboxed to 16:9).
  static double _scale(Size screen) {
    if (screen.isEmpty) return 1;
    final fit = (screen.width / size.width).clamp(0.0, screen.height / size.height);
    return fit == 0 ? 1 : 1 / fit;
  }

  @override
  Widget build(BuildContext context) {
    // A TV has no touch screen: the focus ring shows from the start, not
    // only after the first key of the remote.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    final outer = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _leaveTextField,
      child: ColoredBox(
        color: const Color(0xFF000000),
        // Tight constraints: FittedBox scales up too (a 4K set reports
        // 1920 × 1080 points), not only down.
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox.fromSize(
              size: size,
              child: MediaQuery(
                data: outer.copyWith(
                  size: size,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  // The on-screen keyboard, in stage points: a Scaffold then
                  // lifts the field being typed above it.
                  viewInsets: outer.viewInsets * _scale(outer.size),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Forms and settings on the TV: Up / Down go through every item one after
/// the other, in reading order (like Tab on a computer), so a small link at
/// the side ("Mot de passe oublié ?") is never skipped. Left / Right keep
/// moving the caret and between neighbours. On a computer, nothing changes.
///
/// Not for grids (channels, posters, guide), where Up / Down go to the row
/// above or below.
class TvFormNav extends StatelessWidget {
  const TvFormNav({super.key, required this.child});

  final Widget child;

  static KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!down && e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return KeyEventResult.ignored;
    // A text of several lines keeps its arrows to move between its lines.
    final field = focus.context?.findAncestorWidgetOfExactType<EditableText>();
    if (field != null && field.maxLines != 1) return KeyEventResult.ignored;
    down ? focus.nextFocus() : focus.previousFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Device.isTv ? Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: child) : child;
}
