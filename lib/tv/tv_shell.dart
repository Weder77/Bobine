import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/widgets/brand.dart';
import 'tv_focus.dart';
import 'tv_stage.dart';
import 'tv_theme.dart';

/// Pages of the TV version.
enum TvTab { home, live, guide, films, series, settings }

const _tabLabels = {
  TvTab.home: 'Accueil',
  TvTab.live: 'Direct',
  TvTab.guide: 'Guide TV',
  TvTab.films: 'Films',
  TvTab.series: 'Séries',
};

/// What Back does.
enum TvBackRule { toNav, toHome, exit }

/// In a page, Back goes to its tab in the top bar; on a tab, to Accueil;
/// on Accueil, Bobine closes.
TvBackRule tvBack({required bool onNav, required TvTab tab}) {
  if (!onNav) return TvBackRule.toNav;
  if (tab != TvTab.home) return TvBackRule.toHome;
  return TvBackRule.exit;
}

/// Builds the page of [tab]. The page tells [setEntry] which of its items
/// the remote lands on when it comes down from the top bar.
typedef TvPageBuilder = Widget Function(
  BuildContext context,
  TvTab tab,
  void Function(String? Function() entry) setEntry,
);

/// The TV version: top bar (logo, tabs, settings, time, profile) over the
/// page of the selected tab, all driven by the remote.
class TvShellView extends StatefulWidget {
  const TvShellView({
    super.key,
    required this.pageBuilder,
    this.profile,
    this.onExit,
    this.onController,
    this.showHint = true,
  });

  final TvPageBuilder pageBuilder;
  final Widget? profile;
  final VoidCallback? onExit;
  final ValueChanged<TvFocusController>? onController;
  final bool showHint;

  @override
  State<TvShellView> createState() => _TvShellViewState();
}

class _TvShellViewState extends State<TvShellView> {
  final _c = TvFocusController();

  /// The page shown (the tab with the remote may not be it yet: [_switch]).
  TvTab _tab = TvTab.home;

  /// Passing over tabs does not build their pages (a big source groups
  /// thousands of channels for Direct and Guide TV): the page follows once
  /// the remote stays on a tab.
  Timer? _switch;
  String? Function()? _entry;

  /// The page [_entry] comes from: right after a switch, the new page may
  /// not be built yet, and the old one keeps setting its own until it goes.
  TvTab? _entryTab;

  void _setEntry(TvTab tab, String? Function() entry) {
    if (tab != _tab) return;
    _entry = entry;
    _entryTab = tab;
  }

  bool _hint = true;
  Timer? _hintTimer;
  Timer? _clock;
  DateTime _now = DateTime.now();

  String _nav(TvTab t) => 'nav-${t.name}';
  bool _isNav(String? id) => id != null && id.startsWith('nav-');

  @override
  void initState() {
    super.initState();
    widget.onController?.call(_c);
    _hint = widget.showHint;
    _hintTimer = Timer(const Duration(seconds: 9), _hideHint);
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _c.before = (from, dir) {
      if (from == null || !_c.isRegistered(from)) return _nav(_tab);
      if (_isNav(from) && dir == TvDir.down) {
        final t = _tabOf(from);
        if (t != _tab || _entryTab != t) {
          // Not shown yet (or not built yet): now, and into it once built.
          _show(t);
          _enter();
          return from;
        }
        final e = _entry?.call();
        // Not built (a lazy list scrolled away): the nearest item below.
        return e != null && _c.isRegistered(e) ? e : null;
      }
      return null;
    };
    _c.redirect = (from, to, dir) => _isNav(to) && !_isNav(from) ? _nav(_tab) : to;
    _c.fallback = () => _entry?.call() ?? _nav(_tab);
    _c.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.focus(_entry?.call() ?? _nav(_tab)));
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _clock?.cancel();
    _switch?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _hideHint() {
    if (mounted && _hint) setState(() => _hint = false);
  }

  TvTab _tabOf(String navId) => TvTab.values.byName(navId.substring(4));

  void _show(TvTab t) {
    _switch?.cancel();
    if (t != _tab) setState(() => _tab = t);
  }

  void _onFocus() {
    // The first focus (set by the app, not a key) leaves the hint up.
    if (_c.lastDir != null) _hideHint();
    final id = _c.id;
    _switch?.cancel();
    if (!_isNav(id)) return;
    final t = _tabOf(id!);
    if (t != _tab) _switch = Timer(const Duration(milliseconds: 300), () => _show(t));
  }

  /// OK on a tab, or Down from it: its page, its first item.
  void _enter() {
    final id = _c.id;
    if (_isNav(id)) _show(_tabOf(id!));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Still not built: the next Down or OK tries again.
      if (!mounted || !_isNav(_c.id) || _entryTab != _tab) return;
      final e = _entry?.call();
      if (e != null && _c.isRegistered(e)) {
        _c.focus(e, dir: TvDir.down);
      } else {
        _c.move(TvDir.down);
      }
    });
  }

  void _back() {
    _hideHint();
    final onNav = _isNav(_c.id);
    switch (tvBack(onNav: onNav, tab: onNav ? _tabOf(_c.id!) : _tab)) {
      case TvBackRule.toNav:
        _c.focus(_nav(_tab));
      case TvBackRule.toHome:
        _c.focus(_nav(TvTab.home));
      case TvBackRule.exit:
        (widget.onExit ?? SystemNavigator.pop)();
    }
  }

  Widget _pill(TvTab t, String label) => TvFocusable(
    id: _nav(t),
    onOk: _enter,
    builder: (context, on) {
      final current = t == _tab;
      return AnimatedScale(
        scale: on ? 1.05 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on
                ? Colors.white
                : current
                ? const Color(0x24FFFFFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Text(
            label,
            style: tvText(
              28,
              weight: FontWeight.w600,
              height: 1,
              color: on
                  ? TvColors.bg
                  : current
                  ? Colors.white
                  : TvColors.muted,
            ),
          ),
        ),
      );
    },
  );

  Widget _gear() => TvFocusable(
    id: _nav(TvTab.settings),
    onOk: _enter,
    builder: (context, on) {
      final current = _tab == TvTab.settings;
      return AnimatedScale(
        scale: on ? 1.05 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on
                ? Colors.white
                : current
                ? const Color(0x24FFFFFF)
                : Colors.transparent,
          ),
          child: Icon(
            Icons.settings_outlined,
            size: 32,
            color: on
                ? TvColors.bg
                : current
                ? Colors.white
                : TvColors.muted,
          ),
        ),
      );
    },
  );

  Widget _topBar() {
    final hh = _now.hour.toString().padLeft(2, '0'), mm = _now.minute.toString().padLeft(2, '0');
    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 160,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xF00D0C0B), Color(0x9E0D0C0B), Color(0x000D0C0B)],
                  stops: [0, 0.58, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 96,
          right: 96,
          top: 40,
          height: 84,
          child: Row(
            children: [
              const BobineLogo(height: 64),
              const SizedBox(width: 56),
              // Shrinks rather than overflow if a font is wider than Geist.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      for (final MapEntry(key: t, value: label) in _tabLabels.entries) ...[
                        _pill(t, label),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
              ),
              _gear(),
              const SizedBox(width: 24),
              Text('$hh:$mm', style: tvMono(30)),
              if (widget.profile != null) ...[const SizedBox(width: 24), widget.profile!],
            ],
          ),
        ),
      ],
    );
  }

  Widget _hintBubble() => Positioned(
    right: 96,
    bottom: 44,
    child: IgnorePointer(
      child: AnimatedOpacity(
        opacity: _hint ? 1 : 0,
        duration: const Duration(milliseconds: 800),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xF21A1816),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TvColors.border),
            boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(0, 20), blurRadius: 60)],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvKeyHint('← ↑ → ↓', 'Naviguer'),
              SizedBox(width: 26),
              TvKeyHint('OK', 'Choisir'),
              SizedBox(width: 26),
              TvKeyHint('Retour', 'Revenir'),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    // Back of the remote (Android's back) follows the same rule as the key.
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      // Scaffold: where the messages of the app (wrong code, locked…) show.
      backgroundColor: TvColors.bg,
      body: TvStage(
        // Material: text styles and ink for everything below.
        child: Material(
          color: TvColors.bg,
          child: TvFocusScope(
            controller: _c,
            onBack: _back,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Builder(
                    builder: (context) {
                      final tab = _tab;
                      return KeyedSubtree(
                        key: ValueKey(tab),
                        child: widget.pageBuilder(context, tab, (e) => _setEntry(tab, e)),
                      );
                    },
                  ),
                ),
                Positioned.fill(child: _topBar()),
                _hintBubble(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
