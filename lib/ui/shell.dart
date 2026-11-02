import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../services.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
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

  static ShellNavigation? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNavigation>();

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
  }

  @override
  void dispose() {
    _s.imports.removeListener(_onImports);
    super.dispose();
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
        body: Column(children: [
          _TopBar(index: _index, onSelect: _go),
          Expanded(
            child: Stack(children: [
              for (var i = 0; i < ShellTab.count; i++)
                if (_built.contains(i))
                  Offstage(
                    key: ValueKey(i), // keeps each tab's state when others get built
                    offstage: i != _index,
                    child: TickerMode(enabled: i == _index, child: _page(i)),
                  ),
            ]),
          ),
          const _ImportBanner(),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: AppColors.bg,
      child: Row(children: [
        // Logo
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(ShellTab.home),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              LumenMark(size: 36),
              SizedBox(width: 12),
              Text('LUMEN',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
            ]),
          ),
        ),
        const SizedBox(width: 44),
        // Text tabs
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (tab, label) in _textTabs)
                _TabButton(label: label, selected: index == tab, onTap: () => onSelect(tab)),
            ]),
          ),
        ),
        // Actions
        _IconAction(
          icon: Icons.search_rounded,
          tooltip: 'Recherche',
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
        _SourceAvatar(onManage: () => onSelect(ShellTab.settings)),
        const SizedBox(width: 28),
        const _Clock(),
      ]),
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
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SizedBox(
            height: 76,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(height: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppColors.text
                      : (hover ? const Color(0xFFD5DAE3) : AppColors.muted),
                ),
                child: Text(label),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: selected ? 26 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.selected, required this.onTap});
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        iconSize: 26,
        style: IconButton.styleFrom(
          backgroundColor: selected ? AppColors.accent.withValues(alpha: 0.14) : Colors.transparent,
        ),
        icon: Icon(icon, color: selected ? AppColors.accent : const Color(0xFFC4CAD4)),
      );
}

/// Active source as an avatar; its menu switches source.
class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({required this.onManage});
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
          offset: const Offset(0, 8),
          onSelected: (id) => id < 0 ? onManage() : s.selectSource(id),
          itemBuilder: (_) => [
            for (final src in sources)
              PopupMenuItem(
                value: src.id,
                child: Row(children: [
                  Icon(src.id == active?.id ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 18, color: src.id == active?.id ? AppColors.accent : AppColors.muted),
                  const SizedBox(width: 10),
                  Text(src.name),
                ]),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: -1, child: Text('Gérer les sources…')),
          ],
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.accentGradient),
            child: Text(
              (active?.name.isNotEmpty ?? false) ? active!.name.characters.first.toUpperCase() : '?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1B1204)),
            ),
          ),
        );
      },
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
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
}

/// App logo: a glowing "L".
class LumenMark extends StatelessWidget {
  const LumenMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: size * 0.5),
          ],
        ),
        alignment: Alignment.center,
        child: Text('L',
            style: TextStyle(
                fontSize: size * 0.56, fontWeight: FontWeight.w900, color: const Color(0xFF1B1204))),
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
          child: Row(children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Text('Mise à jour de « $name » — ${st.label}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          ]),
        );
      },
    );
  }
}
