import 'package:bobine/tv/tv_focus.dart';
import 'package:bobine/tv/tv_grid.dart';
import 'package:bobine/tv/tv_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = [
    for (var i = 1; i <= 10; i++)
      TvItem(kind: TvItemKind.movie, key: 'm$i', title: 'Film $i', kicker: 'Film · Tout', meta: '2020', ref: 'm$i'),
  ];

  testWidgets('grille : sept par ligne, Haut depuis la première ligne va à la pastille', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = TvFocusController(initial: tvGridId(items[1]));
    await t.pumpWidget(
      MaterialApp(
        home: TvFocusScope(
          controller: c,
          onBack: () {},
          child: Stack(
            children: [
              Positioned(
                left: 96,
                top: 20,
                child: TvFocusable(id: 'pill', builder: (context, on) => const SizedBox(width: 200, height: 60)),
              ),
              Positioned.fill(
                top: 120,
                child: TvPosterGrid(items: items, upFromTop: () => 'pill'),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(c.id, tvGridId(items[8]));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(c.id, tvGridId(items[1]));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(c.id, 'pill');
  });

  testWidgets('au-dessus de la grille : le titre de l’affiche choisie et combien il y en a', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvGridInfo(item: items.first, count: 248, noun: 'film'),
        ),
      ),
    );
    expect(find.textContaining('Film 1', findRichText: true), findsOneWidget);
    expect(find.text('248 films'), findsOneWidget);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TvGridInfo(item: null, count: 1, noun: 'série')),
      ),
    );
    expect(find.text('1 série'), findsOneWidget);
  });

  testWidgets('en défilant, les affiches restent dans la grille (pas sur les pastilles ni les onglets)', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: TvFocusScope(
          controller: TvFocusController(),
          onBack: () {},
          child: TvPosterGrid(items: items),
        ),
      ),
    );
    expect(t.widget<GridView>(find.byType(GridView)).clipBehavior, Clip.hardEdge);
  });
}
