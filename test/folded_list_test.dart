import 'package:bobine/core/theme.dart';
import 'package:bobine/ui/widgets/rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(int count) => MaterialApp(
    theme: darkTheme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: FoldedList(
          moreLabel: 'Tout voir · $count programmes',
          children: [for (var i = 0; i < count; i++) Text('Programme $i')],
        ),
      ),
    ),
  );

  testWidgets('the first five are shown, the others on demand', (t) async {
    await t.pumpWidget(app(12));
    expect(find.textContaining('Programme '), findsNWidgets(5));
    expect(find.text('Programme 5'), findsNothing);

    await t.tap(find.text('Tout voir · 12 programmes'));
    await t.pump();
    expect(find.textContaining('Programme '), findsNWidgets(12));

    await t.tap(find.text('Voir moins'));
    await t.pump();
    expect(find.textContaining('Programme '), findsNWidgets(5));
  });

  testWidgets('five or fewer: no link', (t) async {
    await t.pumpWidget(app(5));
    expect(find.textContaining('Programme '), findsNWidgets(5));
    expect(find.textContaining('Tout voir'), findsNothing);
  });
}
