import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../features/updater.dart';
import '../services.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'profiles.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'widgets/common.dart';

/// Pages of the main shell.
class ShellTab {
  static const home = 0;
  static const live = 1;
  static const guide = 2;
  static const movies = 3;
  static const series = 4;
  static const search = 5;
  static const settings = 6;
  static const count = 7;
}

/// Tabs shown as text in the top bar (search and settings are icons).
const _textTabs = [
  (ShellTab.home, 'Accueil'),
  (ShellTab.live, 'Live TV'),
  (ShellTab.guide, 'Guide TV'),
  (ShellTab.movies, 'Films'),
  (ShellTab.series, 'Séries'),
];

/// Allows any screen to switch tab (e.g. "Tout voir").
class ShellNavigation extends InheritedWidget {
  const ShellNavigation({super.key, required this.goTo, required super.child});
  final ValueChanged<int> goTo;

  static ShellNavigation? of(BuildContext context) => context.getInheritedWidgetOfExactType<ShellNavigation>();

  @override
  bool updateShouldNotify(ShellNavigation oldWidget) => false;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = ShellTab.home;
  final Set<int> _built = {ShellTab.home};
  int _wasRunning = 0;
  late final AppServices _s;

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _s.imports.addListener(_onImports);
    _s.updates.addListener(_onUpdates);
    HardwareKeyboard.instance.addHandler(_onKey);
    // Found while "Qui regarde ?" was shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onUpdates());
  }

  String? _announced;

  /// A newer version found at startup: say it once, with a shortcut.
  void _onUpdates() {
    final info = _s.updates.available;
    if (info == null || _announced == info.version || !mounted) return;
    if (_s.updates.stage != UpdateStage.available || _index == ShellTab.settings) return;
    _announced = info.version;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: Text('Bobine ${info.version} est disponible.'),
        action: SnackBarAction(label: 'Voir', onPressed: () => _go(ShellTab.settings)),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _s.imports.removeListener(_onImports);
    _s.updates.removeListener(_onUpdates);
    super.dispose();
  }

  /// Ctrl/Cmd + K opens the search from anywhere in the shell. A global
  /// handler rather than Shortcuts: after closing the player or a dialog, the
  /// keyboard focus is not always inside the shell's widget tree.
  bool _onKey(KeyEvent e) {
    // Échap / gamepad B on another tab goes back to Accueil.
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      final typing = FocusManager.instance.primaryFocus?.context?.widget is EditableText;
      if (!mounted || typing || _index == ShellTab.home || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
      _go(ShellTab.home);
      return true;
    }
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _go(ShellTab.search);
    return true;
  }

  void _onImports() {
    final running = _s.imports.running.length;
    if (running < _wasRunning && _s.imports.lastMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_s.imports.lastMessage!)));
      _s.imports.lastMessage = null;
    }
    _wasRunning = running;
  }

  void _go(int i) {
    setState(() {
      _index = i;
      _built.add(i);
    });
  }

  Widget _page(int i) => switch (i) {
    ShellTab.home => const HomeScreen(),
    ShellTab.live => LiveScreen(active: _index == ShellTab.live),
    ShellTab.guide => LiveScreen(active: _index == ShellTab.guide, guide: true),
    ShellTab.movies => const CatalogScreen(series: false),
    ShellTab.series => const CatalogScreen(series: true),
    ShellTab.search => SearchScreen(active: _index == ShellTab.search),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    return ShellNavigation(
      goTo: _go,
      child: Scaffold(
        body: Column(
          children: [
            _TopBar(index: _index, onSelect: _go),
            Expanded(
              child: Stack(
                children: [
                  for (var i = 0; i < ShellTab.count; i++)
                    if (_built.contains(i))
                      Offstage(
                        key: ValueKey(i), // keeps each tab's state when others get built
                        offstage: i != _index,
                        // Hidden tabs stay out of the arrow / Tab navigation.
                        child: ExcludeFocus(
                          excluding: i != _index,
                          child: TickerMode(enabled: i == _index, child: _page(i)),
                        ),
                      ),
                ],
              ),
            ),
            const _ImportBanner(),
          ],
        ),
      ),
    );
  }
}

/// Height of the top bar.
const kTopBarHeight = 76.0;

/// Top bar: logo, text tabs with an amber underline, then search, settings,
/// profile / source menu and the clock.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Container(
      height: kTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: AppColors.bg,
      child: Row(
        children: [
          HoverBuilder(
            onActivate: () => onSelect(ShellTab.home),
            focusRingRadius: 10,
            builder: (context, _) => GestureDetector(
              onTap: () => onSelect(ShellTab.home),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    BobineMark(size: 36),
                    SizedBox(width: 12),
                    Text('BOBINE', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (tab, label) in _textTabs)
                    _TabButton(label: label, selected: index == tab, onTap: () => onSelect(tab)),
                ],
              ),
            ),
          ),
          const _RecordingDot(),
          _IconAction(
            icon: Icons.search_rounded,
            tooltip: 'Recherche (Ctrl K)',
            selected: index == ShellTab.search,
            onTap: () => onSelect(ShellTab.search),
          ),
          const SizedBox(width: 4),
          _IconAction(
            icon: Icons.tune_rounded,
            tooltip: 'Réglages',
            selected: index == ShellTab.settings,
            onTap: () => onSelect(ShellTab.settings),
          ),
          const SizedBox(width: 14),
          ListenableBuilder(
            listenable: Listenable.merge([s.settings, s.library]),
            builder: (context, _) => ProfileMenuButton(onManage: () => onSelect(ShellTab.settings)),
          ),
          const SizedBox(width: 28),
          const _Clock(),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      onActivate: onTap,
      focusRingRadius: 10,
      builder: (context, hover) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SizedBox(
              height: kTopBarHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 6),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.text : (hover ? const Color(0xFFD5DAE3) : AppColors.muted),
                    ),
                    child: Text(label),
                  ),
                  const SizedBox(height: 7),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: selected ? 26 : 0,
                    height: 3,
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon of the top bar: the icon lights up and a soft disc appears
/// on hover (amber while its page is open).
class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.selected, required this.onTap});
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 500),
    child: HoverBuilder(
      onActivate: onTap,
      focusRingRadius: 999,
      builder: (context, hover) => Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? AppColors.accent.withValues(alpha: hover ? 0.24 : 0.14)
                  : (hover ? const Color(0x1FFFFFFF) : const Color(0x00FFFFFF)),
            ),
            child: Icon(
              icon,
              size: 26,
              color: selected ? AppColors.accent : (hover ? AppColors.text : const Color(0xFFC4CAD4)),
            ),
          ),
        ),
      ),
    ),
  );
}

/// "REC" while recordings are in progress.
class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: s.recordings.activeCount,
      builder: (context, n, _) => n == 0
          ? const SizedBox.shrink()
          : Tooltip(
              message: n == 1 ? 'Un enregistrement en cours' : '$n enregistrements en cours',
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record_rounded, size: 12, color: AppColors.live),
                    const SizedBox(width: 4),
                    Text(n == 1 ? 'REC' : 'REC $n', style: labelStyle(color: AppColors.text, size: 12)),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Current time (only this widget rebuilds, twice a minute).
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    formatClock(DateTime.now()),
    style: const TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: Color(0xFFB9C0CC),
      fontFeatures: tabularFigures,
    ),
  );
}

/// App logo: a bold "B" on the amber brand colour, like the app icon.
class BobineMark extends StatelessWidget {
  const BobineMark({super.key, this.size = 40, this.round = false});
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(round ? size : size * 0.28)),
    alignment: Alignment.center,
    // Same letter as the app icon (tool/make_icon.py).
    child: Text(
      'B',
      style: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: size * 0.56,
        fontWeight: FontWeight.w800,
        color: AppColors.onAccent,
        height: 1.1,
      ),
    ),
  );
}

class _ImportBanner extends StatelessWidget {
  const _ImportBanner();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.imports,
      builder: (context, _) {
        final running = s.imports.running.toList();
        if (running.isEmpty) return const SizedBox.shrink();
        final st = running.first;
        final name = s.repo.source(st.sourceId)?.name ?? '';
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Text(
                'Mise à jour de « $name » — ${st.label}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}
