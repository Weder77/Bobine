import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/text.dart';
import '../core/theme.dart';
import '../core/window.dart';
import '../data/models.dart';
import '../player/multi_view.dart';
import '../player/play_items.dart';
import '../player/player_chrome.dart';
import '../player/player_screen.dart';
import '../player/player_session.dart';
import '../services.dart';
import 'live_catalog.dart';
import 'widgets/common.dart';

/// "Multi-écran": two to four channels at once (sport), one of them heard.
///
/// Each slot has its own small player; the main one is stopped meanwhile.
/// What was shown comes back next time.
class MultiViewScreen extends StatefulWidget {
  const MultiViewScreen({super.key, this.add, this.engine});

  /// Channel to add (opened from a channel or from the player).
  final Channel? add;

  /// Player of the slots (tests); libmpv by default.
  final TileEngine Function()? engine;

  static Route<void> route({Channel? add}) => PageRouteBuilder(
    settings: const RouteSettings(name: PlayerScreen.playbackRoute),
    opaque: true,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) => MultiViewScreen(add: add),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );

  /// Opens the multi-view of the source being browsed.
  static Future<void> open(BuildContext context, {Channel? add}) async {
    if (AppScope.of(context).activeSource == null) return;
    await Navigator.of(context).push(route(add: add));
  }

  @override
  State<MultiViewScreen> createState() => _MultiViewScreenState();
}

class _MultiViewScreenState extends State<MultiViewScreen> {
  late final AppServices _s;
  late final MultiViewController _c;
  final _focus = FocusNode(debugLabel: 'multi-view');
  Timer? _hide;
  bool _chrome = true;
  bool _fullscreen = false;

  /// Slot whose channel is being chosen, or null.
  int? _picking;

  /// [PlayerService.takeovers] when this screen opened.
  int _takeovers = 0;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _takeovers = _s.player.takeovers;
    // Already full screen (opened from the player): its button says so.
    _fullscreen = AppWindow.fullscreen.value;
    // The main player and the mini-player stop: their connection is free.
    if (_s.pip.active) {
      unawaited(_s.pip.close());
    } else {
      unawaited(_s.player.stop());
    }
    _c = MultiViewController(
      repo: _s.repo,
      source: _s.activeSource!,
      engine:
          widget.engine ??
          () => MpvTile(hardwareDecoding: _s.settings.hardwareDecoding, deinterlace: _s.settings.deinterlace),
      volume: _s.settings.volume,
      channelName: _s.channelName,
    )..restore(add: widget.add);
    _c.addListener(_changed);
    if (_c.isEmpty) _picking = 0;
    _showChrome();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_changed);
    _c.dispose();
    _focus.dispose();
    // Replaced by a player (a reminder's "Regarder"): the window is its own.
    final replaced = _s.player.takeovers != _takeovers;
    if (_fullscreen && !replaced) scheduleMicrotask(() => AppWindow.setFullscreen(false));
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _showChrome() {
    _hide?.cancel();
    if (!_chrome) setState(() => _chrome = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _picking == null) setState(() => _chrome = false);
    });
  }

  Future<void> _setFullscreen(bool value) async {
    await AppWindow.setFullscreen(value);
    if (mounted) setState(() => _fullscreen = value);
  }

  /// First empty slot (the layout grows), or null when four channels play.
  int? get _freeSlot {
    for (var i = 0; i < _c.layout.slots; i++) {
      if (_c.slots[i] == null) return i;
    }
    return _c.layout.slots < MultiViewController.maxSlots ? _c.layout.slots : null;
  }

  void _pick(int? index) {
    if (index == null) return;
    setState(() => _picking = index);
    _showChrome();
  }

  void _closePicker() {
    setState(() => _picking = null);
    _focus.requestFocus();
    _showChrome();
  }

  void _picked(Channel c) {
    final index = _picking;
    if (index == null) return;
    _c.setChannel(index, c);
    _c.select(index);
    _closePicker();
  }

  /// "Regarder seule" in progress: a second one opened a second player,
  /// stopped when the first closed.
  bool _openingFull = false;

  /// Plays slot [i] in the full player (the others stop).
  Future<void> _openFull(int i) async {
    final slot = _c.slots[i];
    if (slot == null || _openingFull) return;
    _openingFull = true;
    final list = _c.channels;
    final index = list.indexWhere((c) => c.extId == slot.channel.extId);
    final nav = Navigator.of(context);
    // Free the provider's connections before the full player opens its own.
    await _c.stopAll();
    if (!mounted) return;
    // The window is the player's now: this screen does not leave full screen
    // when it closes (the player believed it still was, and needed two
    // presses).
    _s.player.takeOver();
    unawaited(
      nav.pushReplacement(
        PlayerScreen.route(
          PlayerSession(item: channelItem(_c.source, slot.channel), channels: list, channelIndex: math.max(0, index)),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ keyboard

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    _showChrome();
    // While a channel is being chosen, keys belong to the search field and
    // the list; only Échap closes the panel.
    if (_picking != null) {
      if (k != LogicalKeyboardKey.escape && k != LogicalKeyboardKey.goBack) return KeyEventResult.ignored;
      _closePicker();
      return KeyEventResult.handled;
    }
    const digits = [
      [LogicalKeyboardKey.digit1, LogicalKeyboardKey.numpad1],
      [LogicalKeyboardKey.digit2, LogicalKeyboardKey.numpad2],
      [LogicalKeyboardKey.digit3, LogicalKeyboardKey.numpad3],
      [LogicalKeyboardKey.digit4, LogicalKeyboardKey.numpad4],
    ];
    for (var i = 0; i < digits.length; i++) {
      if (digits[i].contains(k)) {
        if (i >= _c.layout.slots || _c.slots[i] == null) {
          _pick(i < _c.layout.slots ? i : _freeSlot);
        } else {
          _c.select(i);
        }
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.goBack) {
      if (_picking != null) {
        _closePicker();
      } else if (_c.solo != null) {
        _c.toggleSolo(_c.solo!);
      } else if (_fullscreen && k == LogicalKeyboardKey.escape) {
        _setFullscreen(false);
      } else {
        Navigator.of(context).maybePop();
      }
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.tab) {
      _c.selectNext(1);
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowUp) {
      _c.selectNext(-1);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.select) {
      _c.slots[_c.selected] == null ? _pick(_c.selected) : _c.toggleSolo(_c.selected);
    } else if (k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.contextMenu) {
      _pick(_c.selected);
    } else if (k == LogicalKeyboardKey.keyA) {
      _pick(_freeSlot);
    } else if (k == LogicalKeyboardKey.delete) {
      _c.remove(_c.selected);
    } else if (k == LogicalKeyboardKey.keyM) {
      _c.toggleMute();
    } else if (k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd) {
      _c.changeVolume(5);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      _c.changeVolume(-5);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _setFullscreen(!_fullscreen);
    } else if (k == LogicalKeyboardKey.keyP) {
      _openFull(_c.selected);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final picking = _picking;
    return Theme(
      // Video surfaces stay dark whatever the theme.
      data: buildTheme(AppPalette.dark),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent && picking == null) _c.changeVolume(e.scrollDelta.dy < 0 ? 5 : -5);
            },
            child: MouseRegion(
              cursor: _chrome ? SystemMouseCursors.basic : SystemMouseCursors.none,
              onHover: (_) => _showChrome(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(builder: (context, box) => _stage(MultiLayout.stage(box.biggest))),
                  _topBar(),
                  if (picking != null) ...[
                    Positioned.fill(child: GestureDetector(onTap: _closePicker)),
                    _ChannelPicker(
                      key: ValueKey(picking),
                      s: _s,
                      source: _c.source,
                      slot: picking,
                      replacing: _c.slots[picking] != null,
                      shown: {for (final c in _c.channels) c.extId},
                      onPick: _picked,
                      onClose: _closePicker,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bottom of the top bar: what a slot shows under it moves down while the
  /// bar is visible.
  double get _barBottom => _c.overLimit ? 118 : 96;

  Widget _stage(Rect stage) {
    final solo = _c.solo;
    final rects = _c.layout.rects;
    return Stack(
      children: [
        for (var i = 0; i < rects.length; i++)
          if (solo == null || solo == i)
            () {
              final rect = solo == i
                  ? stage
                  : Rect.fromLTWH(
                      stage.left + rects[i].left * stage.width,
                      stage.top + rects[i].top * stage.height,
                      rects[i].width * stage.width,
                      rects[i].height * stage.height,
                    ).deflate(2);
              return Positioned.fromRect(
                // Keyed by its player, not its place: after a change of
                // layout, a picture that moves keeps its video view, where
                // a view made again for the same player stayed black.
                key: _c.slots[i] == null ? ValueKey('empty$i') : ObjectKey(_c.slots[i]!.engine),
                rect: rect,
                child: _SlotView(
                  topInset: _chrome ? math.max(0, _barBottom - rect.top) : 0,
                  index: i,
                  slot: _c.slots[i],
                  heard: i == _c.selected,
                  muted: _c.muted,
                  solo: solo == i,
                  chrome: _chrome,
                  s: _s,
                  onSelect: () {
                    _focus.requestFocus();
                    _c.select(i);
                  },
                  onSolo: () => _c.toggleSolo(i),
                  onAdd: () => _pick(i),
                  onChange: () => _pick(i),
                  onRemove: () => _c.remove(i),
                  onFull: () => _openFull(i),
                ),
              );
            }(),
      ],
    );
  }

  Widget _topBar() {
    final count = _c.count;
    final heard = _c.heardName;
    final sub = [
      count == 0 ? 'Aucune chaîne' : '$count chaîne${count > 1 ? 's' : ''}',
      if (heard != null) _c.muted ? 'son coupé' : 'son : $heard',
    ].join(' · ');
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        ignoring: !_chrome,
        child: AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 22, 32, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
            child: Row(
              children: [
                RoundGlassButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Quitter le multi-écran (Échap)',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('MULTI-ÉCRAN', style: darkPoster(30, height: 1)),
                      const SizedBox(height: 6),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: darkMono(13, color: DarkColors.textSoft, height: 1),
                      ),
                      if (_c.overLimit) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xD90D0C0B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 16, color: DarkColors.accent),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Ton abonnement autorise ${_c.maxConnections} connexion'
                                  '${_c.maxConnections! > 1 ? 's simultanées' : ''} : au-delà, des chaînes peuvent '
                                  'rester noires.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, height: 1.2, color: DarkColors.accent),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                for (final l in MultiLayout.values) ...[
                  _LayoutButton(layout: l, selected: l == _c.layout, onTap: () => _c.setLayout(l)),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 14),
                if (_freeSlot != null) ...[
                  PlayerTextButton(
                    icon: Icons.add_rounded,
                    label: 'Ajouter',
                    tooltip: 'Ajouter une chaîne (A)',
                    onTap: () => _pick(_freeSlot),
                  ),
                  const SizedBox(width: 4),
                ],
                PlayerIconButton(
                  icon: _c.muted || _c.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  tooltip: _c.muted ? 'Remettre le son (M)' : 'Couper le son (M)',
                  onTap: _c.toggleMute,
                ),
                const SizedBox(width: 4),
                const Tooltip(
                  message:
                      '1 à 4 ou clic : la chaîne entendue\n'
                      '← → : chaîne suivante · Entrée ou double-clic : agrandir\n'
                      'A : ajouter · C : changer · Suppr : retirer\n'
                      'P : regarder seule dans le lecteur · M : son · F : plein écran\n'
                      'Échap : quitter',
                  child: Padding(
                    padding: EdgeInsets.all(11),
                    child: Icon(Icons.help_outline_rounded, size: 22, color: DarkColors.textSoft),
                  ),
                ),
                const SizedBox(width: 4),
                PlayerIconButton(
                  icon: _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  tooltip: 'Plein écran (F)',
                  onTap: () => _setFullscreen(!_fullscreen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Button of a layout: its shape in miniature.
class _LayoutButton extends StatelessWidget {
  const _LayoutButton({required this.layout, required this.selected, required this.onTap});
  final MultiLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: layout.label,
    child: HoverBuilder(
      onActivate: onTap,
      focusRingRadius: 8,
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0x33FFFFFF) : (hover ? const Color(0x1AFFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            size: const Size(32, 18),
            painter: _LayoutIcon(layout, selected ? DarkColors.text : DarkColors.muted),
          ),
        ),
      ),
    ),
  );
}

class _LayoutIcon extends CustomPainter {
  _LayoutIcon(this.layout, this.color);
  final MultiLayout layout;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final r in layout.rects) {
      final rect = Rect.fromLTWH(
        r.left * size.width,
        r.top * size.height,
        r.width * size.width,
        r.height * size.height,
      ).deflate(0.9);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1.5)), paint);
    }
  }

  @override
  bool shouldRepaint(_LayoutIcon old) => old.layout != layout || old.color != color;
}

// ------------------------------------------------------------------ slots

class _SlotView extends StatefulWidget {
  const _SlotView({
    required this.topInset,
    required this.index,
    required this.slot,
    required this.heard,
    required this.muted,
    required this.solo,
    required this.chrome,
    required this.s,
    required this.onSelect,
    required this.onSolo,
    required this.onAdd,
    required this.onChange,
    required this.onRemove,
    required this.onFull,
  });

  /// Room left at the top for the bar over the slot.
  final double topInset;
  final int index;
  final MultiSlot? slot;
  final bool heard;
  final bool muted;
  final bool solo;
  final bool chrome;
  final AppServices s;
  final VoidCallback onSelect;
  final VoidCallback onSolo;
  final VoidCallback onAdd;
  final VoidCallback onChange;
  final VoidCallback onRemove;
  final VoidCallback onFull;

  @override
  State<_SlotView> createState() => _SlotViewState();
}

class _SlotViewState extends State<_SlotView> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    if (slot == null) return _empty();
    return LayoutBuilder(builder: (context, box) => _filled(slot, big: box.maxWidth > 520));
  }

  Widget _filled(MultiSlot slot, {required bool big}) {
    final info = _hover || widget.chrome;
    final now = widget.s.epg.now(slot.channel);
    final name = widget.s.channelName(slot.channel);
    return MouseRegion(
      // The hand while the cursor shows (it hides with the controls).
      cursor: widget.chrome ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onDoubleTap: widget.onSolo,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black, child: slot.engine.view()),
            ValueListenableBuilder<TileState>(
              valueListenable: slot.engine.state,
              builder: (context, st, _) {
                if (st.message != null) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xD60D0C0B), borderRadius: BorderRadius.circular(8)),
                      child: Text(st.message!, style: darkMono(13, color: DarkColors.textSoft, height: 1)),
                    ),
                  );
                }
                if (!st.loading) return const SizedBox.shrink();
                return const Center(
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 3, color: DarkColors.accent),
                  ),
                );
              },
            ),
            // Name and programme at the bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: info ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(14, 28, 14, big ? 14 : 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xD9000000)],
                      ),
                    ),
                    child: Row(
                      children: [
                        ChannelLogo(name: name, url: slot.channel.logo, size: big ? 40 : 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: big ? 15 : 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                  color: DarkColors.text,
                                ),
                              ),
                              if (now != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${now.title} · jusqu’à ${formatClock(now.stop)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: big ? 13 : 12, height: 1.1, color: DarkColors.textSoft),
                                ),
                                const SizedBox(height: 6),
                                ProgressLine(
                                  now.progressAt(DateTime.now()),
                                  height: 3,
                                  track: const Color(0x33FFFFFF),
                                  color: DarkColors.accent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Number, and the speaker on the channel heard.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              left: 10,
              top: 10 + widget.topInset,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.heard ? DarkColors.accent : const Color(0xB30D0C0B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${widget.index + 1}',
                        style: darkMono(
                          13,
                          weight: FontWeight.w600,
                          color: widget.heard ? DarkColors.onAccent : DarkColors.text,
                          height: 1,
                        ),
                      ),
                    ),
                    if (widget.heard) ...[
                      const SizedBox(width: 6),
                      Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xB30D0C0B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          size: 16,
                          color: DarkColors.text,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Actions of the slot.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              right: 8,
              top: 8 + widget.topInset,
              child: IgnorePointer(
                ignoring: !_hover,
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xB30D0C0B), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlayerIconButton(
                          icon: Icons.swap_horiz_rounded,
                          tooltip: 'Changer de chaîne (C)',
                          size: 20,
                          onTap: widget.onChange,
                        ),
                        PlayerIconButton(
                          icon: widget.solo ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                          tooltip: widget.solo ? 'Revenir à la mosaïque (double-clic)' : 'Agrandir (double-clic)',
                          size: 18,
                          onTap: widget.onSolo,
                        ),
                        PlayerIconButton(
                          icon: Icons.fit_screen_rounded,
                          tooltip: 'Regarder seule dans le lecteur (P)',
                          size: 20,
                          onTap: widget.onFull,
                        ),
                        PlayerIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Retirer (Suppr)',
                          size: 20,
                          onTap: widget.onRemove,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Frame of the channel heard.
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.heard
                        ? DarkColors.accent
                        : (_hover ? const Color(0x59FFFFFF) : const Color(0x00000000)),
                    width: widget.heard ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onAdd,
      child: CustomPaint(
        painter: _DashedFrame(_hover ? const Color(0x80FFFFFF) : const Color(0x33FFFFFF)),
        child: ColoredBox(
          color: _hover ? const Color(0x0DFFFFFF) : const Color(0xFF0A0908),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hover ? DarkColors.accent : const Color(0x1FFFFFFF),
                  ),
                  child: Icon(Icons.add_rounded, size: 28, color: _hover ? DarkColors.onAccent : DarkColors.text),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ajouter une chaîne',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: DarkColors.text),
                ),
                const SizedBox(height: 6),
                Text('Case ${widget.index + 1}', style: darkMono(12, height: 1)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DashedFrame extends CustomPainter {
  _DashedFrame(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(6)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => old.color != color;
}

// ----------------------------------------------------------------- picker

/// Side panel to choose a slot's channel: favourites or all, searched by
/// name or by what plays now ("ligue 1" finds the channels showing a match).
class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker({
    super.key,
    required this.s,
    required this.source,
    required this.slot,
    required this.replacing,
    required this.shown,
    required this.onPick,
    required this.onClose,
  });

  final AppServices s;
  final Source source;
  final int slot;
  final bool replacing;

  /// Channels already on screen.
  final Set<String> shown;
  final ValueChanged<Channel> onPick;
  final VoidCallback onClose;

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  final _query = TextEditingController();
  final _field = FocusNode(debugLabel: 'multi-view search');
  Timer? _debounce;
  late final List<ChannelTile> _favorites;
  late final List<ChannelTile> _all;
  late bool _onlyFavorites;
  List<ChannelTile> _shown = const [];

  @override
  void initState() {
    super.initState();
    final st = widget.s.settings;
    List<ChannelTile> group(List<Channel> list) =>
        LiveCatalog.group(list, clean: st.cleanNames, merge: st.groupQualities, preferred: st.preferredQuality);
    _favorites = group(widget.s.repo.favoriteChannels(widget.source.id));
    _all = group(widget.s.repo.channels(widget.source.id));
    _onlyFavorites = _favorites.isNotEmpty;
    _query.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 180), _filter);
    });
    _filter();
    // The screen already holds the focus, so autofocus would not move it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _field.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  void _filter() {
    final words = searchWords(_query.text);
    final base = _onlyFavorites && words.isEmpty ? _favorites : _all;
    if (words.isEmpty) {
      if (mounted) setState(() => _shown = base);
      return;
    }
    final onAir = widget.s.repo.channelsOnAir(widget.source.id, _query.text);
    final list = _onlyFavorites ? _favorites : _all;
    if (mounted) {
      setState(
        () => _shown = [
          for (final t in list)
            if (t.variants.any((c) => matchesWords(c.search, words) || onAir.contains(c.extId))) t,
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return PlayerSidePanel(
      right: true,
      width: 440,
      kicker: 'CASE ${widget.slot + 1}',
      title: widget.replacing ? 'Changer de chaîne' : 'Ajouter une chaîne',
      onClose: widget.onClose,
      footer: Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: Text('Entrée : la première · Échap : fermer', style: darkMono(12, height: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: TextField(
              controller: _query,
              focusNode: _field,
              style: const TextStyle(fontSize: 15, color: DarkColors.text),
              cursorColor: DarkColors.accent,
              decoration: InputDecoration(
                hintText: 'Chaîne ou programme en cours',
                hintStyle: const TextStyle(color: DarkColors.disabled),
                filled: true,
                fillColor: DarkColors.surface,
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: DarkColors.faint),
                prefixIconConstraints: const BoxConstraints(minWidth: 42),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: DarkColors.borderInput),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: DarkColors.accent, width: 1.2),
                ),
              ),
              onSubmitted: (_) {
                if (_shown.isNotEmpty) widget.onPick(_shown.first.channel);
              },
            ),
          ),
          if (_favorites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PanelSegments<bool>(
                  value: _onlyFavorites,
                  options: const [(true, 'Favoris'), (false, 'Toutes')],
                  onChanged: (v) {
                    setState(() => _onlyFavorites = v);
                    _filter();
                  },
                ),
              ),
            ),
          Expanded(
            child: _shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aucune chaîne ne correspond.',
                      style: const TextStyle(fontSize: 14, color: DarkColors.faint),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemExtent: 66,
                    itemCount: _shown.length,
                    itemBuilder: (context, i) {
                      final t = _shown[i];
                      final c = t.channel;
                      final on = t.variants.any((v) => widget.shown.contains(v.extId));
                      final program = widget.s.epg.now(c);
                      return HoverBuilder(
                        onActivate: () => widget.onPick(c),
                        focusRingRadius: 8,
                        builder: (context, hover) => GestureDetector(
                          onTap: () => widget.onPick(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: hover ? const Color(0x0FFFFFFF) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                ChannelLogo(name: t.name, url: c.logo, size: 40),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          height: 1.15,
                                          color: DarkColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        program?.title ?? 'Pas de programme',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, height: 1, color: DarkColors.faint),
                                      ),
                                      if (program != null) ...[
                                        const SizedBox(height: 6),
                                        ProgressLine(
                                          program.progressAt(now),
                                          height: 3,
                                          track: const Color(0x1FFFFFFF),
                                          color: DarkColors.accent,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (on) ...[
                                  const SizedBox(width: 10),
                                  Text('À L’ÉCRAN', style: darkMono(11, color: DarkColors.accent, height: 1)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
