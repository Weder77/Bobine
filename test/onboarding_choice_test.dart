import 'package:bobine/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingChoice(
            account: (context) => const Text('FORMULAIRE COMPTE'),
            playlist: (context) => const Text('FORMULAIRE PLAYLIST'),
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('au lancement, les deux chemins sont proposés, rien n’est encore ouvert', (t) async {
    await pump(t);
    expect(find.text('Me connecter à mon compte Bobine'), findsOneWidget);
    expect(find.text('Ajouter une playlist sans compte'), findsOneWidget);
    expect(find.text('FORMULAIRE COMPTE'), findsNothing);
    expect(find.text('FORMULAIRE PLAYLIST'), findsNothing);
  });

  testWidgets('le compte ouvre la connexion, « Autre choix » revient aux deux chemins', (t) async {
    await pump(t);
    await t.tap(find.text('Me connecter à mon compte Bobine'));
    await t.pumpAndSettle();
    expect(find.text('FORMULAIRE COMPTE'), findsOneWidget);
    expect(find.text('FORMULAIRE PLAYLIST'), findsNothing);
    await t.tap(find.text('Autre choix'));
    await t.pumpAndSettle();
    expect(find.text('Me connecter à mon compte Bobine'), findsOneWidget);
  });

  testWidgets('sans compte : la playlist, avec l’avertissement qu’il n’y a pas de synchro', (t) async {
    await pump(t);
    await t.tap(find.text('Ajouter une playlist sans compte'));
    await t.pumpAndSettle();
    expect(find.text('FORMULAIRE PLAYLIST'), findsOneWidget);
    expect(find.textContaining('rien n’est synchronisé'), findsOneWidget);
  });

  testWidgets('à la télécommande : le premier chemin est sélectionné, OK l’ouvre', (t) async {
    await pump(t);
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.context?.widget, isNotNull);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pumpAndSettle();
    expect(find.text('FORMULAIRE COMPTE'), findsOneWidget);
  });
}
