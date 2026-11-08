import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'player/mini_player.dart';
import 'services.dart';
import 'ui/onboarding_screen.dart';
import 'ui/profiles.dart';
import 'ui/shell.dart';

class BobineApp extends StatefulWidget {
  const BobineApp({super.key, required this.services});
  final AppServices services;

  @override
  State<BobineApp> createState() => _BobineAppState();
}

class _BobineAppState extends State<BobineApp> with WidgetsBindingObserver {
  late ThemeData _theme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.settings.addListener(_applyTheme);
    _applyTheme(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.settings.removeListener(_applyTheme);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _applyTheme();

  /// Light, dark or the system's choice ("Paramètres → Apparence").
  void _applyTheme({bool initial = false}) {
    final mode = widget.services.settings.themeMode;
    final light =
        mode == 'light' ||
        (mode == 'system' && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light);
    final palette = light ? AppPalette.light : AppPalette.dark;
    if (!initial && identical(palette, AppColors.current)) return;
    AppColors.current = palette;
    _theme = buildTheme(palette);
    if (initial) return;
    setState(() {});
    // Colours are read while building: rebuild every widget (state kept).
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        title: 'Bobine',
        debugShowCheckedModeBanner: false,
        theme: _theme,
        themeAnimationDuration: Duration.zero,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorKey: appNavigatorKey,
        builder: (context, child) => PipLayer(child: child ?? const SizedBox.shrink()),
        home: const _RootGate(),
      ),
    );
  }
}

/// Shows onboarding until a first source exists, then the main shell.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.library]),
      builder: (context, _) {
        if (s.activeSource == null) return const OnboardingScreen();
        if (!s.profileChosen) {
          return ProfilePickerScreen(
            onChosen: () {
              s.profileChosen = true;
              s.library.userChanged();
            },
          );
        }
        return const AppShell();
      },
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.live),
              const SizedBox(height: 16),
              const Text('Bobine n\'a pas pu démarrer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText(error, style: TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      ),
    ),
  );
}
