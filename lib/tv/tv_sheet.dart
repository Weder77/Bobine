import 'package:flutter/material.dart';

import 'tv_focus.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

/// A choice of a sheet: a track, a channel, an action.
class TvSheetOption {
  const TvSheetOption(
    String this._label, {
    this.detail,
    this.detailOf,
    this.icon,
    this.leading,
    this.selected = false,
    required this.onPick,
  }) : labelOf = null,
       leadingOf = null;

  /// A line worked out only when it is shown: its label, its detail and what
  /// is on its left (each of hundreds of channels: name, programme, logo).
  const TvSheetOption.lazy({
    required String Function() this.labelOf,
    this.detailOf,
    this.leadingOf,
    this.selected = false,
    required this.onPick,
  }) : _label = null,
       detail = null,
       icon = null,
       leading = null;

  final String? _label;
  final String Function()? labelOf;
  String get label => _label ?? labelOf!();
  final String? detail;

  /// [detail] worked out only when the line is shown (the programme on air
  /// of each of hundreds of channels).
  final String? Function()? detailOf;
  final IconData? icon;

  /// Drawn on the left instead of [icon] (a channel's logo), or worked out
  /// when shown ([leadingOf]).
  final Widget? leading;
  final Widget Function()? leadingOf;
  Widget? get leadingWidget => leading ?? leadingOf?.call();

  /// The one in use (a check, and the remote starts there).
  final bool selected;
  final VoidCallback onPick;
}

/// A group of choices under a title ("Audio", "Sous-titres").
class TvSheetSection {
  const TvSheetSection(this.title, this.options);
  final String? title;
  final List<TvSheetOption> options;
}

/// Opens a sheet of choices at the right of the screen, over what is there
/// (the player goes on). OK picks (the sheet closes first), Retour closes.
Future<void> showTvSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<TvSheetSection> sections,
}) async {
  TvSheetOption? chosen;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, _, _) =>
          TvSheet(title: title, subtitle: subtitle, sections: sections, onPick: (o) => chosen = o),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
  chosen?.onPick();
}

const _headerHeight = 72.0;
const _optionHeight = 104.0;

/// The sheet itself (see [showTvSheet]).
class TvSheet extends StatefulWidget {
  const TvSheet({super.key, required this.title, this.subtitle, required this.sections, required this.onPick});

  final String title;
  final String? subtitle;
  final List<TvSheetSection> sections;
  final ValueChanged<TvSheetOption> onPick;

  @override
  State<TvSheet> createState() => _TvSheetState();
}

class _TvSheetState extends State<TvSheet> {
  /// Section titles (String) and options, one after the other.
  late final List<Object> _entries = [
    for (final s in widget.sections) ...[?s.title, ...s.options],
  ];
  late final TvFocusController _c;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    var start = _entries.indexWhere((e) => e is TvSheetOption && e.selected);
    if (start < 0) start = _entries.indexWhere((e) => e is TvSheetOption);
    var offset = 0.0;
    for (var i = 0; i < start; i++) {
      offset += _entries[i] is String ? _headerHeight : _optionHeight;
    }
    // A long list opens on the option in use, a third of the way down.
    _scroll = ScrollController(initialScrollOffset: offset > 280 ? offset - 280 : 0);
    _c = TvFocusController(initial: start < 0 ? null : 'opt-$start');
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pick(TvSheetOption o) {
    widget.onPick(o);
    Navigator.of(context).pop();
  }

  Widget _option(int i, TvSheetOption o) {
    final label = o.label;
    final detail = o.detail ?? o.detailOf?.call();
    final leading = o.leadingWidget;
    return TvFocusable(
      id: 'opt-$i',
      onOk: () => _pick(o),
      revealAxes: const {Axis.vertical},
      revealPadding: const EdgeInsets.symmetric(vertical: 40),
      builder: (context, on) => GestureDetector(
        onTap: () => _pick(o),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: on ? Colors.white : const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 22)],
                if (leading == null && o.icon != null) ...[
                  Icon(o.icon, size: 34, color: on ? TvColors.bg : TvColors.accent),
                  const SizedBox(width: 22),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tvText(28, weight: FontWeight.w600, height: 1.1, color: on ? TvColors.bg : Colors.white),
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tvText(22, height: 1.1, color: on ? TvColors.dim : TvColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (o.selected) Icon(Icons.check_rounded, size: 34, color: on ? TvColors.bg : TvColors.ok),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => TvStage(
    background: const Color(0x00000000),
    child: Material(
      type: MaterialType.transparency,
      child: TvFocusScope(
        controller: _c,
        onBack: () => Navigator.of(context).maybePop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const ColoredBox(color: Color(0x8C000000)),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 760,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: TvColors.surface,
                  border: Border(left: BorderSide(color: TvColors.line, width: 2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(56, 64, 56, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.title.toUpperCase(), style: tvTitle(56)),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tvText(24, color: TvColors.muted, height: 1.3),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 64),
                          itemCount: _entries.length,
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            if (e is String) {
                              return SizedBox(
                                height: _headerHeight,
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: Text(e.toUpperCase(), style: tvKicker()),
                                  ),
                                ),
                              );
                            }
                            return SizedBox(height: _optionHeight, child: _option(i, e as TvSheetOption));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
