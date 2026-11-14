import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_focus.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

/// A text to type with the remote: OK opens the keyboard of the TV, ▲ ▼ or
/// the keyboard's "Suivant" close it and go on, Retour only closes it.
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.id,
    required this.label,
    required this.controller,
    this.hint = '',
    this.obscure = false,
    this.keyboard = TextInputType.text,
    this.onChanged,
    this.onDone,
  });

  final String id;
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType keyboard;
  final ValueChanged<String>? onChanged;

  /// Typing is over (the keyboard closed): the whole text, not one letter
  /// at a time as the TV's keyboard sends it.
  final ValueChanged<String>? onDone;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  final _node = FocusNode(debugLabel: 'tv-field');
  TvFocusController? _c;
  bool _editing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = TvFocusScope.maybeOf(context);
    if (c != _c) {
      _c?.removeListener(_onFocus);
      _c = c?..addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  /// The remote went elsewhere (a button pressed, the screen changed).
  void _onFocus() {
    if (_editing && _c?.id != widget.id) _stop();
  }

  void _edit() {
    _c?.focus(widget.id);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _node.requestFocus();
    });
  }

  void _stop() {
    if (!_editing) return;
    setState(() => _editing = false);
    _c?.takeKeys();
    widget.onDone?.call(widget.controller.text);
  }

  void _next() {
    _stop();
    _c?.move(TvDir.down);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _stop();
      _c?.move(k == LogicalKeyboardKey.arrowUp ? TvDir.up : TvDir.down);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.gameButtonB) {
      _stop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => TvFocusable(
    id: widget.id,
    revealAxes: const {Axis.vertical},
    onOk: _edit,
    builder: (context, on) {
      final lit = on && !_editing;
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: tvText(24, weight: FontWeight.w600, color: TvColors.muted, height: 1),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _edit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 84,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: lit ? Colors.white : TvColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _editing ? TvColors.accent : TvColors.surface, width: 3),
                ),
                child: IgnorePointer(
                  ignoring: !_editing,
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _node,
                      obscureText: widget.obscure,
                      keyboardType: widget.keyboard,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onChanged: widget.onChanged,
                      onSubmitted: (_) => _next(),
                      onTapOutside: (_) {},
                      cursorColor: TvColors.accent,
                      style: tvText(30, height: 1.2, color: lit ? TvColors.bg : Colors.white),
                      // Every border and fill spelled out: the app's theme would
                      // draw its own inside the box.
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: tvText(30, height: 1.2, color: lit ? TvColors.dim : TvColors.faint),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// A big button of the remote: white when it has the remote; [primary] is
/// vermilion otherwise (the action of the screen).
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.id,
    required this.label,
    required this.onOk,
    this.icon,
    this.primary = false,
  });

  final String id;
  final String label;
  final VoidCallback? onOk;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) => TvFocusable(
    id: id,
    onOk: onOk,
    revealAxes: const {Axis.vertical},
    builder: (context, on) {
      final ink = on ? TvColors.bg : (primary ? TvColors.accentInk : Colors.white);
      return GestureDetector(
        onTap: onOk,
        child: AnimatedScale(
          scale: on ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 36),
            decoration: BoxDecoration(
              color: on
                  ? Colors.white
                  : primary
                  ? TvColors.accent
                  : const Color(0x29FFFFFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 32, color: ink), const SizedBox(width: 14)],
                Text(
                  label,
                  style: tvText(30, weight: primary ? FontWeight.w700 : FontWeight.w600, height: 1, color: ink),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// A big line to choose (a source, a way to start): a title, a line of
/// text, and what is on its right.
class TvChoice extends StatelessWidget {
  const TvChoice({
    super.key,
    required this.id,
    required this.title,
    required this.onOk,
    this.text,
    this.icon,
    this.trailing,
  });

  final String id;
  final String title;
  final String? text;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) => TvFocusable(
    id: id,
    onOk: onOk,
    revealAxes: const {Axis.vertical},
    builder: (context, on) => GestureDetector(
      onTap: onOk,
      child: AnimatedScale(
        scale: on ? 1.02 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 14),
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: text == null ? 26 : 24),
          decoration: BoxDecoration(
            color: on ? Colors.white : TvColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 40, color: on ? TvColors.bg : TvColors.accent),
                const SizedBox(width: 26),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tvText(30, weight: FontWeight.w600, height: 1.1, color: on ? TvColors.bg : Colors.white),
                    ),
                    if (text != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        text!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tvText(24, height: 1.35, color: on ? TvColors.dim : TvColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 20), trailing!],
            ],
          ),
        ),
      ),
    ),
  );
}

/// A message under a form: an error in vermilion, otherwise in green.
class TvFormMessage extends StatelessWidget {
  const TvFormMessage(this.text, {super.key, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Text(text, style: tvText(26, height: 1.35, color: error ? TvColors.accent : TvColors.ok)),
  );
}

/// The frame of a TV form screen, as Réglages: the big title, a line under
/// it, the column of the form at the left, [side] at the right (help) and
/// the keys of the remote at the bottom.
class TvFormFrame extends StatelessWidget {
  const TvFormFrame({
    super.key,
    required this.controller,
    required this.onBack,
    required this.title,
    required this.children,
    this.subtitle,
    this.side,
    this.backLabel = 'Retour',
  });

  final TvFocusController controller;
  final VoidCallback onBack;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? side;
  final String backLabel;

  @override
  Widget build(BuildContext context) => PopScope(
    // The back gesture as the Retour key (the TV's own back is a key).
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onBack();
    },
    child: TvStage(
      child: Material(
        color: TvColors.bg,
        child: TvFocusScope(
          controller: controller,
          onBack: onBack,
          child: Stack(
            children: [
              Positioned(
                left: 96,
                top: 96,
                right: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: tvTitle(84)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 14),
                      Text(subtitle!, style: tvText(28, height: 1.35, color: TvColors.soft)),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 96,
                top: subtitle == null ? 250 : 300,
                width: 1040,
                bottom: 130,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.only(top: 8, bottom: 48),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              ),
              if (side != null) Positioned(left: 1230, top: subtitle == null ? 258 : 308, width: 594, child: side!),
              Positioned(
                left: 96,
                bottom: 56,
                child: Row(
                  children: [
                    const TvKeyHint('OK', 'Choisir'),
                    const SizedBox(width: 36),
                    TvKeyHint('Retour', backLabel),
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

/// Help at the right of a form (as in Réglages): a kicker and a text.
class TvFormHelp extends StatelessWidget {
  const TvFormHelp({super.key, required this.title, required this.text, this.extra});
  final String title;
  final String text;
  final Widget? extra;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(), style: tvKicker()),
      const SizedBox(height: 18),
      Text(text, style: tvText(28, height: 1.45, color: TvColors.soft)),
      if (extra != null) ...[const SizedBox(height: 28), extra!],
    ],
  );
}
