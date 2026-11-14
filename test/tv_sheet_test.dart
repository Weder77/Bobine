import 'dart:async';

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

  testWidgets('Retour ferme au relâchement : l’écran dessous (le lecteur) ne reçoit pas ce relâchement', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // The player: every key it is given, none kept (Android would make a
    // release of Retour a Retour of its own, and the player would close).
    final under = <String>[];
    late BuildContext context;
    await t.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            under.add('${e.runtimeType}');
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    unawaited(
      showTvSheet(
        context,
        title: 'Options',
        sections: [
          TvSheetSection(null, [TvSheetOption('Un', onPick: () {})]),
        ],
      ),
    );
    await t.pumpAndSettle();
    expect(await t.sendKeyDownEvent(LogicalKeyboardKey.escape), isTrue);
    await t.pumpAndSettle();
    expect(find.text('OPTIONS'), findsOneWidget);
    expect(await t.sendKeyUpEvent(LogicalKeyboardKey.escape), isTrue);
    await t.pumpAndSettle();
    expect(find.text('OPTIONS'), findsNothing);
    expect(under, isEmpty);
  });

  testWidgets('lignes paresseuses : seules celles affichées sont calculées', (t) async {
    var built = 0;
    await open(t, [
      TvSheetSection(null, [
        for (var i = 1; i <= 300; i++)
          TvSheetOption.lazy(
            labelOf: () {
              built++;
              return 'Chaîne $i';
            },
            leadingOf: () => const SizedBox(width: 56, height: 56),
            onPick: () => picked.add('$i'),
          ),
      ]),
    ]);
    expect(find.text('Chaîne 1'), findsOneWidget);
    expect(built, lessThan(30));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(picked, ['1']);
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
