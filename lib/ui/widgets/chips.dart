import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'common.dart';

/// Pill of a group / category: white when selected, outlined otherwise,
/// with an optional mono counter.
class GroupChip extends StatelessWidget {
  const GroupChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.locked = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool locked;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    onActivate: onTap,
    focusRingRadius: 999,
    builder: (context, hover) {
      final fg = selected ? AppColors.onAction : AppColors.textSoft;
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: padding,
            decoration: BoxDecoration(
              color: selected ? AppColors.action : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.action : (hover ? AppColors.muted : AppColors.borderStrong),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked) ...[Icon(Icons.lock_rounded, size: 13, color: fg), const SizedBox(width: 6)],
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1, color: fg),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: 0.7,
                    child: Text(formatCount(count!), style: monoStyle(11, color: fg, height: 1)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Horizontal strip of chips without scrollbar; arrows appear on hover
/// when it overflows.
class ChipStrip extends StatefulWidget {
  const ChipStrip({super.key, required this.children, this.gap = 8, this.padding = EdgeInsets.zero});
  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;

  @override
  State<ChipStrip> createState() => _ChipStripState();
}

class _ChipStripState extends State<ChipStrip> {
  final _controller = ScrollController();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int dir) {
    final pos = _controller.position;
    _controller.animateTo(
      (_controller.offset + dir * pos.viewportDimension * 0.7).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final has = _controller.hasClients && _controller.position.hasContentDimensions;
    final back = has && _controller.offset > 2;
    final forward = has && _controller.offset < _controller.position.maxScrollExtent - 2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.children.length; i++) ...[
                    if (i > 0) SizedBox(width: widget.gap),
                    widget.children[i],
                  ],
                ],
              ),
            ),
          ),
          if (_hover && back)
            Positioned(left: 0, child: _StripArrow(Icons.chevron_left_rounded, () => _page(-1), left: true)),
          if (_hover && forward)
            Positioned(right: 0, child: _StripArrow(Icons.chevron_right_rounded, () => _page(1), left: false)),
        ],
      ),
    );
  }
}

class _StripArrow extends StatelessWidget {
  const _StripArrow(this.icon, this.onTap, {required this.left});
  final IconData icon;
  final VoidCallback onTap;
  final bool left;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(left: left ? 0 : 24, right: left ? 24 : 0),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: left ? Alignment.centerLeft : Alignment.centerRight,
        end: left ? Alignment.centerRight : Alignment.centerLeft,
        colors: [AppColors.bg, AppColors.bg, AppColors.bg.withAlpha(0x00)],
        stops: const [0, 0.55, 1],
      ),
    ),
    child: Material(
      color: AppColors.surface,
      shape: CircleBorder(side: BorderSide(color: AppColors.borderStrong)),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        canRequestFocus: false,
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 22)),
      ),
    ),
  );
}
