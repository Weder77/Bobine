import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _go(ShellTab.search),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _go(ShellTab.search),
        },
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
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 48),
      color: AppColors.bg,
      child: Row(children: [
        // Logo
        Semantics(
          button: true,
          label: 'Lumen, accueil',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(ShellTab.home),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Row(children: [
                const LumenMark(size: 34),
                const SizedBox(width: 12),
                Text('LUMEN',
                    style: displayStyle(21, weight: FontWeight.w800).copyWith(letterSpacing: 4.2)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 40),
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
        const SizedBox(width: 16),
        _SearchPill(selected: index == ShellTab.search, onTap: () => onSelect(ShellTab.search)),
        const SizedBox(width: 12),
        _IconAction(
          icon: Icons.tune_rounded,
          tooltip: 'Réglages',
          selected: index == ShellTab.settings,
          onTap: () => onSelect(ShellTab.settings),
        ),
        const SizedBox(width: 12),
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
      builder: (context, hover) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 3),
              ),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.text
                        : (hover ? AppColors.textSoft : AppColors.muted),
                  )),
            ),
          ),
        ),
      ),
    );
  }
}

/// Search entry point styled as a field ("Ctrl K" opens it from anywhere).
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Rechercher',
      child: Material(
        color: AppColors.field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.accent : const Color(0xFF23262F)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            width: 300,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 19, color: AppColors.muted),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Chaînes, films, séries…',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: AppColors.muted)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderStrong),
                  ),
                  child: const Text('Ctrl K', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              ]),
            ),
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
        iconSize: 24,
        style: IconButton.styleFrom(
          backgroundColor: selected ? AppColors.accentTint : Colors.transparent,
        ),
        icon: Icon(icon, color: selected ? AppColors.accent : AppColors.textSoft),
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
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface3,
              border: Border.all(color: AppColors.borderStrong, width: 2),
            ),
            child: Text(
              (active?.name.isNotEmpty ?? false) ? active!.name.characters.first.toUpperCase() : '?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.accent),
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
        style: displayStyle(26, weight: FontWeight.w600, color: AppColors.textSoft)
            .copyWith(fontFeatures: tabularFigures),
      );
}

/// App logo: an "L" on a solid accent square.
class LumenMark extends StatelessWidget {
  const LumenMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(size * 0.29),
        ),
        alignment: Alignment.center,
        child: Text('L', style: displayStyle(size * 0.6, weight: FontWeight.w800, color: AppColors.onAccent)),
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
