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

    Future<void> pump(WidgetTester t) async {
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
              setEntry(() => 'p-${tab.name}-0');
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
      expect(find.text('live 0'), findsOneWidget);
      await key(t, LogicalKeyboardKey.arrowDown);
      expect(c.id, 'p-live-0');
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
  });
}
