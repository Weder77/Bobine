import 'package:bobine/tv/tv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> picked;

  Future<void> open(WidgetTester t, List<TvSheetSection> sections) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    picked = [];
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showTvSheet(context, title: 'Audio et sous-titres', sections: sections),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
  }

  TvSheetOption option(String label, {bool selected = false}) =>
      TvSheetOption(label, selected: selected, onPick: () => picked.add(label));

  testWidgets('titres, options, et la remote sur l’option choisie', (t) async {
    await open(t, [
      TvSheetSection('Audio', [option('Français'), option('Anglais', selected: true)]),
      TvSheetSection('Sous-titres', [option('Désactivés', selected: true), option('Français')]),
    ]);
    expect(find.text('AUDIO ET SOUS-TITRES'), findsOneWidget);
    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.text('SOUS-TITRES'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(picked, ['Anglais']);
    expect(find.text('AUDIO ET SOUS-TITRES'), findsNothing);
  });

  testWidgets('Bas puis OK choisit l’option suivante ; Retour ferme sans choisir', (t) async {
    await open(t, [
      TvSheetSection(null, [option('Un'), option('Deux')]),
    ]);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.text('AUDIO ET SOUS-TITRES'), findsNothing);
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(picked, ['Deux']);
  });

  testWidgets('une longue liste s’ouvre sur l’option choisie, loin dans la liste', (t) async {
    await open(t, [
      TvSheetSection('Chaînes', [for (var i = 1; i <= 300; i++) option('Chaîne $i', selected: i == 250)]),
    ]);
    expect(find.text('Chaîne 250'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(picked, ['Chaîne 250']);
  });
}
