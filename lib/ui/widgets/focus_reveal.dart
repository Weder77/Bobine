import 'package:flutter/widgets.dart';

/// Keeps what has the remote / keyboard focus out from under a header drawn
/// over the page ([header] high, at the top of [child]).
///
/// The pages with a large picture at the top scroll under the shell's top
/// bar; Flutter scrolls the focused item into the viewport, which starts
/// under the bar, so an item could end up hidden behind it, and Up from
/// there found nothing above.
class RevealUnderHeader extends StatefulWidget {
  const RevealUnderHeader({super.key, required this.header, required this.child});

  final double header;
  final Widget child;

  @override
  State<RevealUnderHeader> createState() => _RevealUnderHeaderState();
}

class _RevealUnderHeaderState extends State<RevealUnderHeader> {
  static const _gap = 12.0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    // After the frame: Flutter's own scrolling to the item comes first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  bool _isInside(BuildContext item) {
    var inside = false;
    item.visitAncestorElements((e) {
      if (e == context) inside = true;
      return !inside;
    });
    return inside;
  }

  void _reveal() {
    if (!mounted) return;
    final item = FocusManager.instance.primaryFocus?.context;
    final box = context.findRenderObject();
    final target = item?.findRenderObject();
    if (item == null || box is! RenderBox || target is! RenderBox || !target.attached || !_isInside(item)) return;
    final top = box.globalToLocal(target.localToGlobal(Offset.zero)).dy;
    final hidden = widget.header + _gap - top;
    if (hidden <= 0) return;
    final position = Scrollable.maybeOf(item)?.position;
    if (position == null) return;
    final to = (position.pixels - hidden).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (to == position.pixels) return;
    position.animateTo(to, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
