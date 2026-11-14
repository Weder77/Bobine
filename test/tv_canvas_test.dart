import 'package:bobine/ui/widgets/tv_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> screen(WidgetTester t, Size pixels) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = pixels;
    addTearDown(t.view.reset);
  }

  testWidgets('une télé 1080p voit une toile de 1280 × 720 points', (t) async {
    await screen(t, const Size(1920, 1080));
    late Size seen;
    await t.pumpWidget(
      TvCanvas(
        child: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(seen, const Size(1280, 720));
  });

  testWidgets('un appui au centre de l’écran atteint le centre de la toile', (t) async {
    await screen(t, const Size(1920, 1080));
    var hits = 0;
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvCanvas(child: child!),
        home: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => hits++,
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );
    await t.tapAt(const Offset(480, 270)); // centre of a 960 × 540 logical screen
    expect(hits, 1);
    await t.tapAt(const Offset(100, 100));
    expect(hits, 1);
  });

  testWidgets('un écran 16:10 garde une toile 16:9 centrée', (t) async {
    await screen(t, const Size(1920, 1200));
    await t.pumpWidget(TvCanvas(child: const SizedBox.expand(key: ValueKey('stage'))));
    final box = t.getRect(find.byKey(const ValueKey('stage')));
    expect(box.width / box.height, closeTo(16 / 9, 0.01));
    expect(box.center, const Offset(480, 300));
  });

  testWidgets('un écran plus grand que la toile (télé 4K) est rempli, pas laissé au centre', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1920, 1080);
    addTearDown(t.view.reset);
    await t.pumpWidget(TvCanvas(child: const SizedBox.expand(key: ValueKey('stage'))));
    expect(t.getRect(find.byKey(const ValueKey('stage'))), const Rect.fromLTWH(0, 0, 1920, 1080));
  });

  testWidgets('sans rien de sélectionné, la première flèche sélectionne le premier élément', (t) async {
    await screen(t, const Size(1920, 1080));
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvCanvas(child: child!),
        home: Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('Premier')),
            TextButton(onPressed: () {}, child: const Text('Second')),
          ],
        ),
      ),
    );
    String? focused() =>
        (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>()?.child as Text?)
            ?.data;
    expect(focused(), isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(focused(), 'Premier');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(focused(), 'Second');
  });

  testWidgets('Haut et Bas sortent d’un champ de saisie d’une ligne (sinon la télécommande y reste bloquée)', (
    t,
  ) async {
    await screen(t, const Size(1920, 1080));
    final a = FocusNode(), b = FocusNode(), c = FocusNode();
    addTearDown(() {
      for (final n in [a, b, c]) {
        n.dispose();
      }
    });
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvCanvas(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: a),
              TextField(focusNode: b),
              TextField(focusNode: c, maxLines: 4),
            ],
          ),
        ),
      ),
    );
    a.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(b.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(a.hasPrimaryFocus, isTrue);
    // A text of several lines keeps its arrows to move between its lines.
    c.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(c.hasPrimaryFocus, isTrue);
  });

  testWidgets('Gauche au début du texte et Droite à la fin passent au champ voisin', (t) async {
    await screen(t, const Size(1920, 1080));
    final left = FocusNode(), right = FocusNode();
    final text = TextEditingController(text: 'demo');
    addTearDown(() {
      left.dispose();
      right.dispose();
      text.dispose();
    });
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvCanvas(child: child!),
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: TextField(focusNode: left, controller: text),
              ),
              Expanded(child: TextField(focusNode: right)),
            ],
          ),
        ),
      ),
    );
    left.requestFocus();
    await t.pump();
    text.selection = const TextSelection.collapsed(offset: 2);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(left.hasPrimaryFocus, isTrue, reason: 'in the middle of the text, Right moves the caret');
    expect(text.selection.baseOffset, 3);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(right.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    expect(left.hasPrimaryFocus, isTrue);
  });
}
