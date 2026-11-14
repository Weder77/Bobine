import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Arrow of the TV remote.
enum TvDir { up, down, left, right }

/// The item the remote goes to from [from] in direction [dir], among
/// [candidates] (rects in the same coordinates), or null when there is none.
///
/// Same rule as the "Bobine TV" design: the nearest item in that direction,
/// left / right only within the same row (30 % overlap at least), up / down
/// preferring the item under the start of the current one.
String? tvPick(Rect from, Map<String, Rect> candidates, TvDir dir) {
  final r = from;
  final rx = r.center.dx, ry = r.center.dy;
  final ax = r.left + (r.width / 2 < 40 ? r.width / 2 : 40);
  String? best;
  var bestScore = double.infinity;
  for (final MapEntry(key: id, value: c) in candidates.entries) {
    if (c.isEmpty || c == r) continue;
    final cx = c.center.dx, cy = c.center.dy;
    double prim, orth, tie;
    if (dir == TvDir.left || dir == TvDir.right) {
      final ahead = dir == TvDir.right ? c.left > r.left + 2 && cx > rx : c.right < r.right - 2 && cx < rx;
      if (!ahead) continue;
      final overlap = (r.bottom < c.bottom ? r.bottom : c.bottom) - (r.top > c.top ? r.top : c.top);
      if (overlap < (r.height < c.height ? r.height : c.height) * 0.3) continue;
      prim = dir == TvDir.right
          ? (c.left - r.right).clamp(0, double.infinity)
          : (r.left - c.right).clamp(0, double.infinity);
      orth = 0;
      tie = (cy - ry).abs();
    } else {
      final ahead = dir == TvDir.down ? c.top > r.top + 2 && cy > ry : c.bottom < r.bottom - 2 && cy < ry;
      if (!ahead) continue;
      prim = dir == TvDir.down
          ? (c.top - r.bottom).clamp(0, double.infinity)
          : (r.top - c.bottom).clamp(0, double.infinity);
      orth = ((r.left > c.left ? r.left : c.left) - (r.right < c.right ? r.right : c.right)).clamp(0, double.infinity);
      tie = (ax.clamp(c.left, c.right) - ax).abs();
    }
    final score = prim + orth * 4 + tie * 0.3;
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  }
  return best;
}

class _TvReg {
  _TvReg(this.state);
  final _TvFocusableState state;
}

/// Which item has the remote, and the moves between items. One per screen
/// ([TvFocusScope]); items register themselves ([TvFocusable]).
class TvFocusController extends ChangeNotifier {
  TvFocusController({String? initial}) : _id = initial;

  String? _id;
  String? get id => _id;

  /// Direction of the last move (null after [focus]).
  TvDir? lastDir;

  final Map<String, _TvReg> _items = {};
  RenderBox? Function()? _origin;

  /// Screen rule before the nearest item is looked for: the item to go to
  /// instead, or null (e.g. Down from the top bar goes into the page).
  String? Function(String? from, TvDir dir)? before;

  /// Screen rule on the item found: what to focus instead (e.g. from a page,
  /// Up into the top bar lands on the current tab).
  String Function(String? from, String to, TvDir dir)? redirect;

  /// Item to fall back to when the current one is gone (page changed).
  String? Function()? fallback;

  bool isRegistered(String id) => _items.containsKey(id);

  VoidCallback? _takeKeys;

  /// Gives the keys back to the screen (a text field stopped typing).
  void takeKeys() => _takeKeys?.call();

  void focus(String? id, {TvDir? dir}) {
    if (id == null || id == _id) return;
    _id = id;
    lastDir = dir;
    notifyListeners();
  }

  Rect? _rectOf(_TvFocusableState s) {
    final box = s.context.findRenderObject();
    final origin = _origin?.call();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final topLeft = origin == null ? box.localToGlobal(Offset.zero) : box.localToGlobal(Offset.zero, ancestor: origin);
    final bottomRight = origin == null
        ? box.localToGlobal(box.size.bottomRight(Offset.zero))
        : box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: origin);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Moves in [dir]; false when nothing is there.
  bool move(TvDir dir) {
    final current = _id == null ? null : _items[_id];
    if (current != null &&
        (dir == TvDir.left || dir == TvDir.right) &&
        (current.state.widget.onSide?.call(dir) ?? false)) {
      return true;
    }
    final forced = before?.call(_id, dir);
    if (forced != null) {
      focus(forced, dir: dir);
      return true;
    }
    final from = current == null ? null : _rectOf(current.state);
    if (from == null) {
      final f = fallback?.call();
      if (f == null) return false;
      focus(f, dir: dir);
      return true;
    }
    final rects = <String, Rect>{};
    for (final MapEntry(key: id, value: reg) in _items.entries) {
      if (id == _id) continue;
      final rect = _rectOf(reg.state);
      if (rect != null) rects[id] = rect;
    }
    final picked = tvPick(from, rects, dir);
    if (picked == null) return false;
    focus(redirect?.call(_id, picked, dir) ?? picked, dir: dir);
    return true;
  }

  /// OK on the current item.
  void activate() {
    final id = _id;
    if (id != null) _items[id]?.state.widget.onOk?.call();
  }
}

class _TvScope extends InheritedWidget {
  const _TvScope({required this.controller, required super.child});
  final TvFocusController controller;

  @override
  bool updateShouldNotify(_TvScope old) => old.controller != controller;
}

/// Takes the keys of the remote for a screen: arrows move ([TvFocusController.move]),
/// OK (Entrée, A) activates, Retour / Échap goes back ([onBack]).
class TvFocusScope extends StatefulWidget {
  const TvFocusScope({super.key, required this.controller, required this.onBack, required this.child});

  final TvFocusController controller;
  final VoidCallback onBack;
  final Widget child;

  static TvFocusController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TvScope>()?.controller;

  @override
  State<TvFocusScope> createState() => _TvFocusScopeState();
}

class _TvFocusScopeState extends State<TvFocusScope> {
  final _node = FocusNode(debugLabel: 'tv');
  final _origin = GlobalKey();

  static final _arrows = {
    LogicalKeyboardKey.arrowUp: TvDir.up,
    LogicalKeyboardKey.arrowDown: TvDir.down,
    LogicalKeyboardKey.arrowLeft: TvDir.left,
    LogicalKeyboardKey.arrowRight: TvDir.right,
  };
  static final _ok = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };
  static final _back = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.gameButtonB,
  };

  @override
  void initState() {
    super.initState();
    _attach();
    // A screen shown in place of another one (first launch: the choice, then
    // the form) takes the keys even if the one before had them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_node.hasFocus) _node.requestFocus();
    });
  }

  @override
  void didUpdateWidget(TvFocusScope old) {
    super.didUpdateWidget(old);
    _attach();
  }

  void _attach() {
    widget.controller._origin = _box;
    widget.controller._takeKeys = _node.requestFocus;
  }

  RenderBox? _box() => _origin.currentContext?.findRenderObject() as RenderBox?;

  @override
  void dispose() {
    if (widget.controller._takeKeys == _node.requestFocus) widget.controller._takeKeys = null;
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    // A text field is typing: its keys (Effacer, the arrows in the text) are
    // its own; it gives the remote back itself ([TvTextField]).
    if (FocusManager.instance.primaryFocus != _node) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final dir = _arrows[k];
    if (dir != null) {
      widget.controller.move(dir);
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;
    if (_ok.contains(k)) {
      widget.controller.activate();
      return KeyEventResult.handled;
    }
    if (_back.contains(k)) {
      widget.onBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => _TvScope(
    controller: widget.controller,
    child: Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: _onKey,
      child: KeyedSubtree(key: _origin, child: widget.child),
    ),
  );
}

/// An item the remote can go to. [builder] gets whether it has the remote.
/// When it gets it, the lists around it scroll to show it, keeping
/// [revealPadding] (design: 96 at the sides, 48 above and below).
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.id,
    required this.builder,
    this.onOk,
    this.onSide,
    this.revealAxes = const {Axis.horizontal, Axis.vertical},
    this.revealPadding = const EdgeInsets.symmetric(horizontal: 96, vertical: 48),
  });

  final String id;
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onOk;

  /// ← → kept by the item (a setting changes value): true when handled.
  final bool Function(TvDir dir)? onSide;

  final Set<Axis> revealAxes;
  final EdgeInsets revealPadding;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  TvFocusController? _c;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = TvFocusScope.maybeOf(context);
    if (c == _c) return;
    _detach();
    _c = c;
    if (c != null) {
      c._items[widget.id] = _TvReg(this);
      c.addListener(_changed);
      _focused = c.id == widget.id;
      if (_focused) _scheduleReveal();
    }
  }

  @override
  void didUpdateWidget(TvFocusable old) {
    super.didUpdateWidget(old);
    final c = _c;
    if (c == null || old.id == widget.id) return;
    if (c._items[old.id]?.state == this) c._items.remove(old.id);
    c._items[widget.id] = _TvReg(this);
    _changed();
  }

  void _detach() {
    final c = _c;
    if (c == null) return;
    c.removeListener(_changed);
    if (c._items[widget.id]?.state == this) c._items.remove(widget.id);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _changed() {
    final now = _c?.id == widget.id;
    if (now == _focused) return;
    setState(() => _focused = now);
    if (now) _scheduleReveal();
  }

  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focused) _reveal();
    });
  }

  void _reveal() {
    final item = context.findRenderObject();
    if (item is! RenderBox || !item.attached) return;
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final position = scrollable.position;
      final viewport = scrollable.context.findRenderObject();
      if (widget.revealAxes.contains(position.axis) && viewport is RenderBox && viewport.attached) {
        final horizontal = position.axis == Axis.horizontal;
        final topLeft = item.localToGlobal(Offset.zero, ancestor: viewport);
        final bottomRight = item.localToGlobal(item.size.bottomRight(Offset.zero), ancestor: viewport);
        final start = horizontal ? topLeft.dx : topLeft.dy;
        final end = horizontal ? bottomRight.dx : bottomRight.dy;
        final extent = horizontal ? viewport.size.width : viewport.size.height;
        final padStart = horizontal ? widget.revealPadding.left : widget.revealPadding.top;
        final padEnd = horizontal ? widget.revealPadding.right : widget.revealPadding.bottom;
        var target = position.pixels;
        if (start < padStart) {
          target -= padStart - start;
        } else if (end > extent - padEnd) {
          target += end - (extent - padEnd);
        }
        target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
        if ((target - position.pixels).abs() > 1) {
          position.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
        }
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _focused);
}
