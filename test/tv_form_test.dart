import 'package:bobine/tv/tv_account.dart';
import 'package:bobine/tv/tv_focus.dart';
import 'package:bobine/tv/tv_form.dart';
import 'package:bobine/tv/tv_sources.dart';
import 'package:bobine/tv/tv_welcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TvFocusController c;
  late TextEditingController a, b;
  late int backs, saves;

  setUp(() {
    c = TvFocusController(initial: 'a');
    a = TextEditingController();
    b = TextEditingController();
    backs = 0;
    saves = 0;
  });

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusScope(
            controller: c,
            onBack: () => backs++,
            child: Column(
              children: [
                TvTextField(id: 'a', label: 'Adresse du serveur', controller: a),
                TvTextField(id: 'b', label: 'Mot de passe', controller: b, obscure: true),
                TvButton(id: 'save', label: 'Enregistrer', primary: true, onOk: () => saves++),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('OK ouvre la saisie, ▼ la ferme et passe au champ suivant', (t) async {
    await pump(t);
    expect(t.testTextInput.hasAnyClients, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(t.testTextInput.hasAnyClients, isTrue);
    t.testTextInput.enterText('http://iptv.exemple');
    await t.pump();
    expect(a.text, 'http://iptv.exemple');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(c.id, 'b');
    expect(t.testTextInput.hasAnyClients, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(c.id, 'save');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(saves, 1);
  });

  testWidgets('en saisie, Effacer n’est pas Retour et Échap ferme seulement la saisie', (t) async {
    await pump(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    t.testTextInput.enterText('abc');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(backs, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(backs, 0);
    expect(t.testTextInput.hasAnyClients, isFalse);
    expect(c.id, 'a');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(backs, 1);
  });

  testWidgets('valider au clavier passe au champ suivant', (t) async {
    await pump(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pump();
    expect(c.id, 'b');
  });

  test('source : ce qui manque, dans l’ordre du formulaire', () {
    expect(tvSourceError(xtream: true, server: ' ', user: 'u', pass: 'p'), "Indique l'adresse du serveur.");
    expect(tvSourceError(xtream: true, server: 'http://s', user: '', pass: 'p'), 'Identifiant et mot de passe requis.');
    expect(tvSourceError(xtream: true, server: 'http://s', user: 'u', pass: 'p'), isNull);
    expect(tvSourceError(xtream: false, m3u: ''), "Indique l'adresse de la playlist.");
    expect(tvSourceError(xtream: false, m3u: 'http://p.m3u'), isNull);
  });

  test('source : son nom vient de l’adresse', () {
    expect(tvSourceName(xtream: true, location: 'iptv.exemple.com:8080'), 'iptv.exemple.com');
    expect(tvSourceName(xtream: false, location: 'http://listes.fr/a.m3u'), 'listes.fr');
    expect(tvSourceName(xtream: true, location: ''), 'Mon IPTV');
    expect(tvSourceName(xtream: false, location: 'liste'), 'Ma playlist');
  });

  test('compte : les vérifications du formulaire', () {
    expect(tvAccountError(TvAccountMode.signIn, email: 'pas-une-adresse'), 'Adresse e-mail invalide.');
    expect(tvAccountError(TvAccountMode.signIn, email: 'a@b.fr'), 'Saisis ton mot de passe.');
    expect(tvAccountError(TvAccountMode.signIn, email: 'a@b.fr', password: 'x'), isNull);
    expect(tvAccountError(TvAccountMode.forgot, email: 'a@b.fr'), isNull);
    expect(
      tvAccountError(TvAccountMode.signUp, email: 'a@b.fr', password: 'court', confirm: 'court'),
      'Le mot de passe doit faire au moins 8 caractères.',
    );
    expect(
      tvAccountError(TvAccountMode.signUp, email: 'a@b.fr', password: 'motdepasse', confirm: 'autre'),
      'Les deux mots de passe ne sont pas identiques.',
    );
    expect(tvAccountError(TvAccountMode.reset, email: 'a@b.fr', code: '12'), startsWith('Saisis les'));
  });

  testWidgets('premier lancement : les deux façons de commencer, Retour quitte', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var exits = 0;
    await t.pumpWidget(MaterialApp(home: TvWelcomeScreen(onExit: () => exits++)));
    await t.pump();
    expect(find.text('Me connecter à mon compte Bobine'), findsOneWidget);
    expect(find.text('Ajouter une source sans compte'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(exits, 1);
  });

  testWidgets('la saisie finie, le texte entier est remis (pas lettre par lettre)', (t) async {
    final done = <String>[];
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusScope(
            controller: c,
            onBack: () {},
            child: Column(
              children: [
                TvTextField(id: 'a', label: 'Adresse', controller: a, onDone: done.add),
                TvTextField(id: 'b', label: 'Identifiant', controller: b),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    t.testTextInput.enterText('http://s/get.php?username=u&password=p');
    await t.pump();
    expect(done, isEmpty);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(done, ['http://s/get.php?username=u&password=p']);
  });

  test('une source : ce qu’elle contient', () {
    expect(tvSourceCounts(live: 1234, movies: 1, series: 0), '1\u202f234 chaînes · 1 film');
    expect(tvSourceCounts(live: 0, movies: 0, series: 0), 'Vide pour l’instant');
  });

  test('une source : son état', () {
    final now = DateTime(2026, 11, 14, 21);
    expect(tvSourceState(now: now, stage: 'Chaînes… 120'), ('Actualisation : Chaînes… 120', false));
    expect(tvSourceState(now: now, error: 'Ressource introuvable (404).'), (
      'Erreur : Ressource introuvable (404).',
      true,
    ));
    expect(tvSourceState(now: now, updated: DateTime(2026, 11, 14, 20, 15)), (
      'Connectée · mise à jour il y a 45 min',
      false,
    ));
    expect(tvSourceState(now: now), ('Jamais mise à jour', false));
  });
}
