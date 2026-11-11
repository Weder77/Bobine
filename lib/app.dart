import 'dart:ui' show AppExitResponse;

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
    widget.services.repo.onWriteFailed = _writeFailed;
    _applyTheme(initial: true);
  }

  /// A change that could not be saved, after two minutes of tries: said,
  /// rather than lost without a word.
  void _writeFailed() {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Une modification n'a pas pu être enregistrée (base occupée) : refais-la.")),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.settings.removeListener(_applyTheme);
    widget.services.repo.onWriteFailed = null;
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _applyTheme();

  /// Closing the window: asked first while something is being recorded,
  /// then everything is saved and stopped properly.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final s = widget.services;
    final recording = s.recordings.activeCount.value;
    final context = appNavigatorKey.currentContext;
    if (recording > 0 && context != null && context.mounted) {
      final quit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Quitter Bobine ?'),
          content: Text(
            recording == 1
                ? "Un enregistrement est en cours : il sera arrêté (ce qui est déjà enregistré est gardé)."
                : '$recording enregistrements sont en cours : ils seront arrêtés (ce qui est déjà enregistré est gardé).',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
          ],
        ),
      );
      if (quit != true) return AppExitResponse.cancel;
    }
    await s.prepareExit();
    return AppExitResponse.exit;
  }

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
              s.reminders.profileChanged();
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
