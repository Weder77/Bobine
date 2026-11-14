import 'dart:async';

import 'package:bobine/tv/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tvPick (même calcul que la maquette)', () {
    const from = Rect.fromLTWH(100, 100, 200, 100);

    test('à droite : le plus proche sur la même ligne', () {
      final pick = tvPick(from, {
        'loin': const Rect.fromLTWH(800, 100, 200, 100),
        'proche': const Rect.fromLTWH(320, 100, 200, 100),
        'gauche': const Rect.fromLTWH(-200, 100, 200, 100),
      }, TvDir.right);
      expect(pick, 'proche');
    });

    test('à droite : un élément sans recouvrement vertical (autre rangée) est ignoré', () {
      final pick = tvPick(from, {'dessous': const Rect.fromLTWH(320, 400, 200, 100)}, TvDir.right);
      expect(pick, isNull);
    });

    test('en bas : préfère l’élément aligné sous le début de l’élément courant', () {
      final pick = tvPick(from, {
        'aligne': const Rect.fromLTWH(90, 260, 200, 100),
        'decale': const Rect.fromLTWH(600, 240, 200, 100),
      }, TvDir.down);
      expect(pick, 'aligne');
    });

    test('en haut depuis une vignette : la barre du haut, même décalée', () {
      final pick = tvPick(from, {'onglet': const Rect.fromLTWH(900, 0, 120, 60)}, TvDir.up);
      expect(pick, 'onglet');
    });

    test('rien dans la direction : null', () {
      expect(tvPick(from, {'dessus': const Rect.fromLTWH(100, 0, 200, 80)}, TvDir.down), isNull);
    });
  });

  group('TvFocusScope et TvFocusable', () {
    late List<String> oks;
    late int backs;

    Future<TvFocusController> pump(WidgetTester t) async {
      oks = [];
      backs = 0;
      final c = TvFocusController(initial: 'a');
      addTearDown(c.dispose);
      Widget item(String id, double x) => Positioned(
        left: x,
        top: 100,
        child: TvFocusable(
          id: id,
          onOk: () => oks.add(id),
          builder: (context, focused) => Container(
            width: 100,
            height: 60,
            color: focused ? Colors.white : Colors.black,
            child: Text(focused ? '[$id]' : id),
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          home: TvFocusScope(
            controller: c,
            onBack: () => backs++,
            child: Stack(children: [item('a', 0), item('b', 150), item('c', 300)]),
          ),
        ),
      );
      await t.pump();
      return c;
    }

    testWidgets('la flèche droite va au suivant, OK l’active, Retour remonte', (t) async {
      final c = await pump(t);
      expect(find.text('[a]'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(c.id, 'b');
      expect(find.text('[b]'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(oks, ['b', 'b']);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(backs, 2);
    });

    testWidgets('Retour agit au relâchement, gardé aussi (Android en ferait un second Retour)', (t) async {
      await pump(t);
      expect(await t.sendKeyDownEvent(LogicalKeyboardKey.escape), isTrue);
      expect(backs, 0);
      expect(await t.sendKeyUpEvent(LogicalKeyboardKey.escape), isTrue);
      expect(backs, 1);
    });

    testWidgets('un élément peut désigner son voisin pour une flèche', (t) async {
      final c = TvFocusController(initial: 'a');
      Widget item(String id, double left, {String? Function(TvDir)? onMove}) => Positioned(
        left: left,
        top: 0,
        child: TvFocusable(
          id: id,
          onMove: onMove,
          builder: (context, focused) => const SizedBox(width: 100, height: 60),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          home: TvFocusScope(
            controller: c,
            onBack: () {},
            child: Stack(
              children: [
                item('a', 0, onMove: (d) => d == TvDir.right ? 'c' : null),
                item('b', 150),
                item('c', 300),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(c.id, 'c');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(c.id, 'b');
    });

    testWidgets('au bord, la flèche ne fait rien', (t) async {
      final c = await pump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(c.id, 'a');
    });

    testWidgets('un élément peut prendre ← → pour lui (réglages)', (t) async {
      final c = TvFocusController(initial: 'r');
      addTearDown(c.dispose);
      final sides = <TvDir>[];
      await t.pumpWidget(
        MaterialApp(
          home: TvFocusScope(
            controller: c,
            onBack: () {},
            child: Center(
              child: TvFocusable(
                id: 'r',
                onSide: (d) {
                  sides.add(d);
                  return true;
                },
                builder: (context, focused) => const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(sides, [TvDir.left, TvDir.right]);
    });
  });

  group('appui long sur OK', () {
    late TvFocusController c;
    late List<String> events;

    Future<void> pump(WidgetTester t) async {
      c = TvFocusController(initial: 'long');
      events = [];
      await t.pumpWidget(
        MaterialApp(
          home: TvFocusScope(
            controller: c,
            onBack: () {},
            child: Row(
              children: [
                TvFocusable(
                  id: 'long',
                  onOk: () => events.add('ok'),
                  onLongOk: () => events.add('long'),
                  builder: (context, on) => const SizedBox(width: 100, height: 60),
                ),
                TvFocusable(
                  id: 'short',
                  onOk: () => events.add('ok-short'),
                  builder: (context, on) => const SizedBox(width: 100, height: 60),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('maintenu : l’action longue, une fois, et pas OK', (t) async {
      await pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 300));
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 300));
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 600));
      expect(events, ['long']);
    });

    testWidgets('appui bref : OK au relâchement', (t) async {
      await pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 100));
      expect(events, isEmpty);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 600));
      expect(events, ['ok']);
    });

    testWidgets('Retour pendant l’appui : ni action longue ni OK', (t) async {
      await pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 100));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump(const Duration(milliseconds: 600));
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(events, isEmpty);
    });

    testWidgets('les touches parties ailleurs pendant l’appui : pas d’action longue', (t) async {
      await pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.select);
      await t.pump(const Duration(milliseconds: 100));
      // Something opens over the screen and takes the keys.
      unawaited(
        t
            .state<NavigatorState>(find.byType(Navigator))
            .push(MaterialPageRoute<void>(builder: (_) => const Focus(autofocus: true, child: SizedBox()))),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(events, isEmpty);
      await t.sendKeyUpEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(events, isEmpty);
    });

    testWidgets('sans action longue : OK dès l’appui, comme avant', (t) async {
      await pump(t);
      c.focus('short');
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
      expect(events, ['ok-short']);
      await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 600));
      expect(events, ['ok-short']);
    });
  });
}
