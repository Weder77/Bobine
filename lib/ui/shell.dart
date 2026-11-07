import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
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
  (ShellTab.guide, 'Guide'),
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
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _s.imports.removeListener(_onImports);
    super.dispose();
  }

  /// Ctrl/Cmd + K opens the search from anywhere in the shell. A global
  /// handler rather than Shortcuts: after closing the player or a dialog, the
  /// keyboard focus is not always inside the shell's widget tree.
  bool _onKey(KeyEvent e) {
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
            Expanded(
              child: Stack(
                children: [
                  for (var i = 0; i < ShellTab.count; i++)
                    if (_built.contains(i))
                      Offstage(
                        key: ValueKey(i), // keeps each tab's state when others get built
                        offstage: i != _index,
                        child: TickerMode(
                          enabled: i == _index,
                          // The home hero runs under the floating bar; the
                          // other pages start below it.
                          child: Padding(
                            padding: EdgeInsets.only(top: i == ShellTab.home ? 0 : kTopBarHeight),
                            child: _page(i),
                          ),
                        ),
                      ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _TopBar(index: _index, onSelect: _go),
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

/// Height taken by the floating top bar.
const kTopBarHeight = 100.0;

/// Floating "liquid glass" bar: source on the left, tabs in the middle,
/// clock and settings on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 26, 48, 0),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            _SourceButton(onManage: () => onSelect(ShellTab.settings)),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Glass(
                    height: 54,
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GlassIcon(
                          icon: Icons.search_rounded,
                          tooltip: 'Rechercher (Ctrl K)',
                          selected: index == ShellTab.search,
                          onTap: () => onSelect(ShellTab.search),
                        ),
                        for (final (tab, label) in _textTabs)
                          _TabButton(label: label, selected: index == tab, onTap: () => onSelect(tab)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Glass(
              height: 54,
              padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _RecordingDot(),
                  ListenableBuilder(
                    listenable: Listenable.merge([AppScope.of(context).settings, AppScope.of(context).library]),
                    builder: (context, _) => ProfileMenuButton(onManage: () => onSelect(ShellTab.settings)),
                  ),
                  const SizedBox(width: 12),
                  const _Clock(),
                  const SizedBox(width: 12),
                  _GlassIcon(
                    icon: Icons.tune_rounded,
                    tooltip: 'Réglages',
                    selected: index == ShellTab.settings,
                    filled: true,
                    onTap: () => onSelect(ShellTab.settings),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final text = Text(
      label,
      style: TextStyle(fontSize: 15.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.text),
    );
    return HoverBuilder(
      builder: (context, hover) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: selected
              ? Glass(
                  strong: true,
                  shadow: false,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Center(child: text),
                )
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: hover ? const Color(0x1AFFFFFF) : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: text,
                ),
        ),
      ),
    );
  }
}

/// Round icon inside a glass bar.
class _GlassIcon extends StatelessWidget {
  const _GlassIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    iconSize: 20,
    style: IconButton.styleFrom(
      fixedSize: const Size(42, 42),
      minimumSize: const Size(42, 42),
      backgroundColor: selected ? const Color(0x52FFFFFF) : (filled ? const Color(0x29FFFFFF) : Colors.transparent),
      foregroundColor: AppColors.text,
      shape: const CircleBorder(),
    ),
    icon: Icon(icon),
  );
}

/// Lumen mark in a glass capsule; its menu switches the active source.
class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.onManage});
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.library]),
      builder: (context, _) {
        final sources = s.repo.sources();
        final active = s.activeSource;
        return PopupMenuButton<int>(
          tooltip: active == null ? 'Sources' : 'Source : ${active.name}',
          position: PopupMenuPosition.under,
          offset: const Offset(0, 10),
          onSelected: (id) => id < 0 ? onManage() : s.selectSource(id),
          itemBuilder: (_) => [
            for (final src in sources)
              PopupMenuItem(
                value: src.id,
                child: Row(
                  children: [
                    Icon(src.id == active?.id ? Icons.check_rounded : null, size: 18, color: AppColors.text),
                    const SizedBox(width: 10),
                    Text(
                      src.name,
                      style: TextStyle(fontWeight: src.id == active?.id ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: -1, child: Text('Gérer les sources…')),
          ],
          child: Glass(
            height: 54,
            padding: const EdgeInsets.fromLTRB(7, 7, 14, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LumenMark(size: 40, round: true),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    active?.name ?? 'Lumen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSoft),
              ],
            ),
          ),
        );
      },
    );
  }
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
                padding: const EdgeInsets.only(right: 12),
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
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
  );
}

/// App logo: a poster-style "L" on the amber brand colour.
class LumenMark extends StatelessWidget {
  const LumenMark({super.key, this.size = 40, this.round = false});
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(round ? size : size * 0.28)),
    alignment: Alignment.center,
    child: Text('L', style: posterStyle(size * 0.68, color: AppColors.onAccent, height: 1.05)),
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
