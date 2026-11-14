import 'package:bobine/data/models.dart';
import 'package:bobine/player/player_keys.dart';
import 'package:bobine/tv/tv_player_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OK de la télécommande : pause, sinon réessayer, sinon épisode suivant', () {
    expect(tvPlayerOk(error: false, nextShown: false), TvPlayerOk.togglePause);
    expect(tvPlayerOk(error: true, nextShown: false), TvPlayerOk.retry);
    expect(tvPlayerOk(error: false, nextShown: true), TvPlayerOk.nextEpisode);
    expect(tvPlayerOk(error: true, nextShown: true), TvPlayerOk.retry);
  });

  test('les touches OK de la télécommande', () {
    for (final k in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA]) {
      expect(isOkKey(k), isTrue);
    }
    expect(isOkKey(LogicalKeyboardKey.arrowUp), isFalse);
  });

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
  }

  testWidgets('direct : chaîne, EN DIRECT, programme, ensuite, touches', (t) async {
    final now = DateTime.now();
    await pump(
      t,
      TvPlayerOverlay(
        info: TvPlayerInfo.live(
          channelName: 'Canal Sport',
          channelNumber: 7,
          program: Program(
            start: now.subtract(const Duration(minutes: 20)),
            stop: now.add(const Duration(minutes: 40)),
            title: 'Le grand match',
            category: 'Sport',
          ),
          next: Program(
            start: now.add(const Duration(minutes: 40)),
            stop: now.add(const Duration(minutes: 90)),
            title: 'Le journal',
          ),
        ),
        visible: true,
        paused: false,
        position: Duration.zero,
        duration: Duration.zero,
        seekStep: 10,
      ),
    );
    expect(find.text('Canal Sport'), findsOneWidget);
    expect(find.text('Chaîne 7'), findsOneWidget);
    expect(find.text('● EN DIRECT'), findsOneWidget);
    expect(find.text('LE GRAND MATCH'), findsOneWidget);
    expect(find.text('Changer de chaîne'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Quitter'), findsOneWidget);
    expect(find.textContaining('Le journal', findRichText: true), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('film en pause : titre, temps écoulé, restant, OK = Lecture', (t) async {
    await pump(
      t,
      const TvPlayerOverlay(
        info: TvPlayerInfo.vod(kicker: 'Film', title: 'Le Voyage', meta: '2024 · Aventure'),
        visible: false,
        paused: true,
        position: Duration(minutes: 12, seconds: 5),
        duration: Duration(hours: 1, minutes: 30),
        seekStep: 10,
      ),
    );
    expect(find.text('LE VOYAGE'), findsOneWidget);
    expect(find.text('12:05'), findsOneWidget);
    expect(find.text('−1:17:55'), findsOneWidget);
    expect(find.text('10 secondes'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('épisode suivant proposé : OK = Épisode suivant', (t) async {
    await pump(
      t,
      const TvPlayerOverlay(
        info: TvPlayerInfo.vod(kicker: 'S01E02', title: 'La série'),
        visible: true,
        paused: false,
        position: Duration(minutes: 40),
        duration: Duration(minutes: 41),
        seekStep: 10,
        nextLabel: 'S01E03 · La suite',
      ),
    );
    expect(find.text('Épisode suivant'), findsOneWidget);
    expect(find.text('S01E03 · LA SUITE'), findsOneWidget);
  });
}
