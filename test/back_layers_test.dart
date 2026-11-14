import 'package:bobine/ui/back_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int backs;
  late bool lastLayer;

  Future<void> open(WidgetTester t) async {
    backs = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => StatefulBuilder(
                  builder: (context, setState) => BackLayers(
                    atLastLayer: lastLayer,
                    onBack: () => backs++,
                    child: TextButton(
                      // Like "Retour (la télé continue)" or the mini-player key.
                      onPressed: () => BackLayers.leave(context),
                      child: const Text('Quitter'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Ouvrir'));
    await t.pumpAndSettle();
  }

  testWidgets('Retour de la télécommande ferme une couche à la fois', (t) async {
    lastLayer = false;
    await open(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(backs, 1);
    expect(find.text('Quitter'), findsOneWidget);
  });

  testWidgets('à la dernière couche, Retour quitte l’écran', (t) async {
    lastLayer = true;
    await open(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(backs, 0);
    expect(find.text('Quitter'), findsNothing);
  });

  testWidgets('une sortie voulue (cast, mini-lecteur, bouton Quitter) part même avec des couches ouvertes', (t) async {
    lastLayer = false;
    await open(t);
    await t.tap(find.text('Quitter'));
    await t.pumpAndSettle();
    expect(find.text('Quitter'), findsNothing);
    expect(backs, 0);
  });
}
