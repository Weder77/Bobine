import 'package:bobine/tv/tv_focus.dart';
import 'package:bobine/tv/tv_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Retour', () {
    test('dans une page : vers l’onglet en cours', () {
      expect(tvBack(onNav: false, tab: TvTab.films), TvBackRule.toNav);
      expect(tvBack(onNav: false, tab: TvTab.home), TvBackRule.toNav);
    });
    test('sur un onglet : vers Accueil, puis Bobine se ferme', () {
      expect(tvBack(onNav: true, tab: TvTab.guide), TvBackRule.toHome);
      expect(tvBack(onNav: true, tab: TvTab.home), TvBackRule.exit);
    });
  });

  group('barre du haut', () {
    late TvFocusController c;
    late int exits;

    Future<void> pump(WidgetTester t, {bool missingEntry = false}) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      exits = 0;
      await t.pumpWidget(
        MaterialApp(
          home: TvShellView(
            showHint: false,
            onExit: () => exits++,
            onController: (x) => c = x,
            pageBuilder: (context, tab, setEntry) {
              setEntry(() => missingEntry ? 'p-${tab.name}-99' : 'p-${tab.name}-0');
              return Stack(
                children: [
                  for (var i = 0; i < 2; i++)
                    Positioned(
                      left: 96 + i * 300.0,
                      top: 400,
                      child: TvFocusable(
                        id: 'p-${tab.name}-$i',
                        builder: (context, on) => SizedBox(width: 200, height: 100, child: Text('${tab.name} $i')),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
      await t.pump();
      await t.pump();
    }

    Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
      await t.sendKeyEvent(k);
      await t.pump();
      await t.pump();
    }

    testWidgets('au départ, la page Accueil a la main ; Haut va sur l’onglet Accueil', (t) async {
      await pump(t);
      expect(c.id, 'p-home-0');
      await key(t, LogicalKeyboardKey.arrowUp);
      expect(c.id, 'nav-home');
    });

    testWidgets('arriver sur un onglet l’affiche ; Bas entre dans sa page', (t) async {
      await pump(t);
      await key(t, LogicalKeyboardKey.arrowUp);
      await key(t, LogicalKeyboardKey.arrowRight);
      expect(c.id, 'nav-live');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('live 0'), findsOneWidget);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(c.id, 'p-live-0');
    });

    testWidgets('passer sur des onglets ne construit pas leurs pages ; Bas entre tout de suite', (t) async {
      await pump(t);
      await key(t, LogicalKeyboardKey.arrowUp);
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.arrowRight);
      expect(c.id, 'nav-guide');
      expect(find.text('live 0'), findsNothing);
      expect(find.text('home 0'), findsOneWidget);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(find.text('guide 0'), findsOneWidget);
      expect(c.id, 'p-guide-0');
    });

    testWidgets('Bas depuis l’onglet, l’entrée de la page pas encore construite : le plus proche dessous', (t) async {
      await pump(t, missingEntry: true);
      await key(t, LogicalKeyboardKey.arrowUp);
      expect(c.id, 'nav-home');
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(c.id, startsWith('p-home-'));
    });

    testWidgets('depuis une page, Haut revient sur l’onglet de la page, même s’il est loin', (t) async {
      await pump(t);
      await key(t, LogicalKeyboardKey.arrowUp);
      for (var i = 0; i < 4; i++) {
        await key(t, LogicalKeyboardKey.arrowRight);
      }
      expect(c.id, 'nav-series');
      await key(t, LogicalKeyboardKey.arrowDown);
      await key(t, LogicalKeyboardKey.arrowUp);
      expect(c.id, 'nav-series');
    });

    testWidgets('Retour : page → onglet → Accueil → sortie', (t) async {
      await pump(t);
      await key(t, LogicalKeyboardKey.arrowUp);
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(c.id, 'p-guide-0');
      await key(t, LogicalKeyboardKey.escape);
      expect(c.id, 'nav-guide');
      await key(t, LogicalKeyboardKey.escape);
      expect(c.id, 'nav-home');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('home 0'), findsOneWidget);
      expect(exits, 0);
      await key(t, LogicalKeyboardKey.escape);
      expect(exits, 1);
    });

    testWidgets('OK sur un onglet entre dans sa page', (t) async {
      await pump(t);
      await key(t, LogicalKeyboardKey.arrowUp);
      await key(t, LogicalKeyboardKey.arrowRight);
      await key(t, LogicalKeyboardKey.enter);
      expect(c.id, 'p-live-0');
    });

    testWidgets('les messages de l’app s’affichent (code faux, verrouillé…)', (t) async {
      t.view.physicalSize = const Size(1920, 1080);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: TvShellView(
            showHint: false,
            pageBuilder: (context, tab, setEntry) {
              setEntry(() => 'msg');
              return TvFocusable(
                id: 'msg',
                onOk: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect'))),
                builder: (context, on) => const SizedBox(width: 200, height: 100),
              );
            },
          ),
        ),
      );
      await t.pump();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Code incorrect'), findsOneWidget);
    });
  });
}
