import 'package:bobine/tv/tv_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('A → B → A pendant le fondu : pas deux enfants avec la même clé', (t) async {
    Future<void> show(String id) => t.pumpWidget(
      MaterialApp(
        home: TvFade(id: id, child: Text(id)),
      ),
    );
    await show('A');
    await show('B');
    await t.pump(const Duration(milliseconds: 100));
    await show('A');
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    await t.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });
}
