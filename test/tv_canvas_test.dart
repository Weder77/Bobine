import 'package:bobine/ui/widgets/tv_canvas.dart';
import 'package:flutter/material.dart';
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
}
