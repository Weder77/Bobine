import 'package:bobine/ui/widgets/focus_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('un élément sélectionné sous la barre du haut est ramené en dessous', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final scroll = ScrollController();
    final nodes = List.generate(20, (i) => FocusNode(debugLabel: 'item $i'));
    addTearDown(() {
      scroll.dispose();
      for (final n in nodes) {
        n.dispose();
      }
    });
    await t.pumpWidget(
      MaterialApp(
        home: RevealUnderHeader(
          header: 100,
          child: Stack(
            children: [
              ListView(
                controller: scroll,
                children: [
                  for (final n in nodes)
                    SizedBox(
                      height: 80,
                      child: TextButton(focusNode: n, onPressed: () {}, child: Text(n.debugLabel!)),
                    ),
                ],
              ),
              // The header drawn over the page (like the shell's top bar).
              const Positioned(left: 0, right: 0, top: 0, height: 100, child: ColoredBox(color: Colors.black)),
            ],
          ),
        ),
      ),
    );
    scroll.jumpTo(400); // item 5 starts at y 0, under the header
    await t.pump();
    nodes[5].requestFocus();
    await t.pumpAndSettle();
    final top = t.getTopLeft(find.text('item 5')).dy;
    expect(top, greaterThanOrEqualTo(100));
    expect(scroll.offset, lessThan(400));

    // Below the header already: nothing moves.
    final before = scroll.offset;
    nodes[7].requestFocus();
    await t.pumpAndSettle();
    expect(scroll.offset, before);
  });
}
