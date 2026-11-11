import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../features/updater.dart';
import '../services.dart';
import 'catalog_controller.dart';
import 'catalog_screen.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'live_catalog.dart';
import 'live_screen.dart';
import 'profiles.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'widgets/brand.dart';
import 'widgets/common.dart';

/// Pages of the main shell.

/// Whether the keyboard focus is in a text field. The focused node belongs
/// to a widget inside the field, not to the field itself: without looking
/// up, "/" typed in a field opened the search and was lost ("AC/DC").
bool focusIsInTextField() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
}

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
  (ShellTab.live, 'Direct'),
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

  /// Search: the header's field drives the search layer above the pages.
  bool _searchOpen = false;
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  /// Pages scrolled past 40 px get an opaque header.
  final Set<int> _scrolled = {};

  /// Groups and channels shared by Direct and Guide TV.
  late final LiveCatalog _live;

  /// Films and Séries pages, shared with the header's sub-bar.
  late final CatalogController _movies;
  late final CatalogController _series;

  CatalogController? get _catalog => switch (_index) {
    ShellTab.movies => _movies,
    ShellTab.series => _series,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _s = AppScope.of(context);
    _live = LiveCatalog(_s);
    _movies = CatalogController(_s, series: false);
    _series = CatalogController(_s, series: true);
    _showCatalogs();
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
    _live.dispose();
    _movies.dispose();
    _series.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _searchCtl.dispose();
    _searchFocus.dispose();
    _s.imports.removeListener(_onImports);
    _s.updates.removeListener(_onUpdates);
    super.dispose();
  }

  /// Ctrl/Cmd + K or "/" opens the search from anywhere in the shell. A
  /// global handler rather than Shortcuts: after closing the player or a
  /// dialog, the keyboard focus is not always inside the shell's widget tree.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final typing = focusIsInTextField();
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      // Échap / gamepad B: closes the search, then goes back to Accueil.
      if (_searchOpen) {
        _closeSearch();
        return true;
      }
      if (typing || _index == ShellTab.home) return false;
      _go(ShellTab.home);
      return true;
    }
    final keys = HardwareKeyboard.instance;
    final ctrlK = e.logicalKey == LogicalKeyboardKey.keyK && (keys.isControlPressed || keys.isMetaPressed);
    // The character typed: on an AZERTY keyboard "/" is Shift + ":".
    final slash = (e.character == '/' || e.logicalKey == LogicalKeyboardKey.slash) && !typing;
    if (!ctrlK && !slash) return false;
    _openSearch();
    return true;
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _closeSearch() {
    _searchCtl.clear();
    _searchFocus.unfocus();
    setState(() => _searchOpen = false);
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
    if (i == ShellTab.search) return _openSearch();
    setState(() {
      _searchOpen = false;
      _searchCtl.clear();
      _index = i;
      _built.add(i);
    });
    _showCatalogs();
  }

  /// Only the catalogs on screen follow the changes as they come.
  void _showCatalogs() {
    _live.shown = _index == ShellTab.live || _index == ShellTab.guide;
    _movies.shown = _index == ShellTab.movies;
    _series.shown = _index == ShellTab.series;
  }

  /// Home, films and series start with a big image under the header.
  static bool _heroPage(int i) => i == ShellTab.home || i == ShellTab.movies || i == ShellTab.series;

  bool _onScroll(int i, ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final past = n.metrics.pixels > 40;
    if (past != _scrolled.contains(i)) setState(() => past ? _scrolled.add(i) : _scrolled.remove(i));
    return false;
  }

  Widget _page(int i) => switch (i) {
    ShellTab.home => const HomeScreen(),
    ShellTab.live => LiveScreen(catalog: _live),
    ShellTab.guide => GuideScreen(catalog: _live),
    ShellTab.movies => CatalogScreen(controller: _movies),
    ShellTab.series => CatalogScreen(controller: _series),
    _ => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final opaque = _searchOpen || !_heroPage(_index) || _scrolled.contains(_index);
    return ShellNavigation(
      goTo: _go,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  for (var i = 0; i < ShellTab.count; i++)
                    if (_built.contains(i) && i != ShellTab.search)
                      Offstage(
                        key: ValueKey(i), // keeps each tab's state when others get built
                        offstage: i != _index,
                        // Hidden tabs stay out of the arrow / Tab navigation.
                        child: ExcludeFocus(
                          excluding: i != _index || _searchOpen,
                          child: TickerMode(
                            enabled: i == _index && !_searchOpen,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (n) => _onScroll(i, n),
                              // Hero pages run under the header, the others start below it.
                              child: Padding(
                                padding: EdgeInsets.only(top: _heroPage(i) ? 0 : kTopBarHeight),
                                child: _page(i),
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (_searchOpen)
                    Positioned.fill(
                      top: kTopBarHeight,
                      child: ColoredBox(
                        color: AppColors.bg,
                        child: SearchScreen(controller: _searchCtl, onClose: _closeSearch),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_movies, _series]),
                      builder: (context, _) {
                        final catalog = _searchOpen ? null : _catalog;
                        return _TopBar(
                          index: _index,
                          onSelect: _go,
                          opaque: opaque || catalog?.mode == CatalogMode.grid,
                          searchOpen: _searchOpen,
                          searchController: _searchCtl,
                          searchFocus: _searchFocus,
                          onOpenSearch: _openSearch,
                          onCloseSearch: _closeSearch,
                          subBar: catalog == null ? null : CatalogSubBar(controller: catalog),
                        );
                      },
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

/// Height of the header row.
const kTopBarHeight = 84.0;

/// Header: logo, text tabs with a vermilion underline, then search (an icon
/// that becomes a field), settings, profile menu and the clock. Over the
/// big images it fades from the background; elsewhere it is opaque.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.onSelect,
    required this.opaque,
    required this.searchOpen,
    required this.searchController,
    required this.searchFocus,
    required this.onOpenSearch,
    required this.onCloseSearch,
    this.subBar,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final bool opaque;
  final bool searchOpen;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;

  /// Second line (Films / Séries).
  final Widget? subBar;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final gap = (width * 0.03).clamp(20.0, 48.0);
    // Narrow windows: the field takes the room of the tabs while searching.
    final showNav = !(searchOpen && width < 1180);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.bg.withAlpha(0xCC), AppColors.bg.withAlpha(0x00)],
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: opaque ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: ColoredBox(color: AppColors.bg.withAlpha(0xF7)),
                ),
              ],
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: kTopBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                children: [
                  HoverBuilder(
                    onActivate: () => onSelect(ShellTab.home),
                    focusRingRadius: 10,
                    builder: (context, _) => GestureDetector(
                      onTap: () => onSelect(ShellTab.home),
                      behavior: HitTestBehavior.opaque,
                      child: Semantics(label: 'Bobine', button: true, child: const BobineLogo()),
                    ),
                  ),
                  SizedBox(width: gap),
                  // Five short tabs: they fit in the smallest window (1024 px).
                  if (showNav)
                    for (final (tab, label) in _textTabs) ...[
                      _TabButton(label: label, selected: index == tab, onTap: () => onSelect(tab)),
                      if (tab != ShellTab.series) SizedBox(width: (width * 0.022).clamp(18.0, 30.0)),
                    ],
                  SizedBox(width: gap),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const _RecordingDot(),
                        if (searchOpen)
                          Flexible(
                            child: _SearchField(
                              controller: searchController,
                              focus: searchFocus,
                              onClose: onCloseSearch,
                            ),
                          )
                        else
                          _IconAction(
                            icon: Icons.search_rounded,
                            tooltip: 'Rechercher ( / )',
                            selected: false,
                            onTap: onOpenSearch,
                          ),
                        const SizedBox(width: 14),
                        _IconAction(
                          icon: Icons.tune_rounded,
                          tooltip: 'Paramètres',
                          selected: index == ShellTab.settings && !searchOpen,
                          onTap: () => onSelect(ShellTab.settings),
                        ),
                        _UpdateButton(
                          onOpen: () {
                            settingsPageRequest.value = 'apropos';
                            onSelect(ShellTab.settings);
                          },
                        ),
                        const SizedBox(width: 14),
                        ListenableBuilder(
                          listenable: Listenable.merge([s.settings, s.library]),
                          builder: (context, _) => ProfileMenuButton(
                            onManage: ({bool profiles = false}) {
                              if (profiles) settingsPageRequest.value = 'profils';
                              onSelect(ShellTab.settings);
                            },
                          ),
                        ),
                        const SizedBox(width: 20),
                        const _Clock(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ?subBar,
          ],
        ),
      ],
    );
  }
}

/// The search field of the header (max 440 px, vermilion border, "Échap").
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus, required this.onClose});
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 440),
    child: Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(14, 0, 7, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: AppColors.textSoft),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              cursorColor: AppColors.accent,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                hintText: 'Titres, chaînes, programmes…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.borderInput, borderRadius: BorderRadius.circular(4)),
                child: Text('Échap', style: monoStyle(12, color: AppColors.textSoft)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
      focusRingRadius: 6,
      builder: (context, hover) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: kTopBarHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: selected || hover ? AppColors.text : AppColors.muted,
                  ),
                  child: Text(label),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: selected ? 18 : 0,
                  height: 2,
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Square icon button of the header (40 px, rounded 8): a light veil on
/// hover; tinted vermilion while its page is open.
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
      focusRingRadius: 8,
      builder: (context, hover) => Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: selected
                  ? AppColors.accentSelected
                  : (hover ? AppColors.ink.withAlpha(0x1A) : AppColors.ink.withAlpha(0x00)),
            ),
            child: Icon(icon, size: 22, color: selected ? AppColors.accent : AppColors.text),
          ),
        ),
      ),
    ),
  );
}

/// Between the settings and the profile while a newer Bobine is available:
/// opens Paramètres → À propos.
class _UpdateButton extends StatelessWidget {
  const _UpdateButton({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final u = AppScope.of(context).updates;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final info = u.available;
        final shown =
            info != null &&
            (u.stage == UpdateStage.available || u.stage == UpdateStage.downloading || u.stage == UpdateStage.ready);
        if (!shown) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _IconAction(
                icon: Icons.system_update_alt_rounded,
                tooltip: u.stage == UpdateStage.ready
                    ? 'Bobine ${info.version} est prête à installer'
                    : 'Mise à jour disponible : Bobine ${info.version}',
                selected: false,
                onTap: onOpen,
              ),
              Positioned(
                right: 7,
                top: 7,
                child: IgnorePointer(
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 1.5),
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
                    Icon(Icons.fiber_manual_record_rounded, size: 12, color: AppColors.live),
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
  Widget build(BuildContext context) =>
      Text(formatClock(DateTime.now()), style: monoStyle(17, color: AppColors.textSoft));
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
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Text('Mise à jour de « $name » : ${st.label}', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ],
          ),
        );
      },
    );
  }
}
