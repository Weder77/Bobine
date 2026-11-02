import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class _NavItem {
  const _NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const _items = [
  _NavItem(Icons.home_outlined, Icons.home_rounded, 'Accueil'),
  _NavItem(Icons.live_tv_outlined, Icons.live_tv_rounded, 'TV'),
  _NavItem(Icons.movie_outlined, Icons.movie_rounded, 'Films'),
  _NavItem(Icons.video_library_outlined, Icons.video_library_rounded, 'Séries'),
  _NavItem(Icons.search_rounded, Icons.search_rounded, 'Recherche'),
  _NavItem(Icons.settings_outlined, Icons.settings_rounded, 'Réglages'),
];

/// Allows any screen to switch tab (e.g. "Voir tout").
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
  int _index = 0;
  final Set<int> _built = {0};
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
        0 => const HomeScreen(),
        1 => LiveScreen(active: _index == 1),
        2 => const CatalogScreen(series: false),
        3 => const CatalogScreen(series: true),
        4 => SearchScreen(active: _index == 4),
        _ => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return ShellNavigation(
      goTo: _go,
      child: Scaffold(
        body: Row(children: [
          _Sidebar(index: _index, onSelect: _go),
          Expanded(
            child: Column(children: [
              Expanded(
                child: Stack(children: [
                  for (var i = 0; i < _items.length; i++)
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
        ]),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(children: [
        const SizedBox(height: 22),
        const LumenMark(size: 40),
        const SizedBox(height: 26),
        for (var i = 0; i < _items.length; i++)
          _NavButton(item: _items[i], selected: i == index, onTap: () => onSelect(i)),
        const Spacer(),
        ListenableBuilder(
          listenable: Listenable.merge([s.settings, s.library]),
          builder: (context, _) {
            final sources = s.repo.sources();
            final active = s.activeSource;
            return PopupMenuButton<int>(
              tooltip: 'Changer de source',
              position: PopupMenuPosition.over,
              onSelected: (id) => id < 0 ? onSelect(5) : s.selectSource(id),
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
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: AppColors.surface3,
                    child: Text(
                      (active?.name.isNotEmpty ?? false) ? active!.name.characters.first.toUpperCase() : '?',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 76,
                    child: Text(active?.name ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                  ),
                ]),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Material(
        color: selected ? AppColors.accent.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(selected ? item.activeIcon : item.icon,
                  size: 24, color: selected ? AppColors.accent : AppColors.muted),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.accent : AppColors.muted,
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
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
