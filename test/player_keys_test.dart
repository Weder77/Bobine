import 'package:bobine/player/player_chrome.dart';
import 'package:bobine/player/player_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlayerKeyRoute route(LogicalKeyboardKey k, {bool visible = false, bool button = false}) =>
      playerKeyRoute(k, controlsVisible: visible, buttonFocused: button);

  test('contrôles cachés : OK les fait apparaître, les flèches reculent, avancent et zappent', () {
    expect(route(LogicalKeyboardKey.select), PlayerKeyRoute.revealControls);
    expect(route(LogicalKeyboardKey.enter), PlayerKeyRoute.revealControls);
    expect(route(LogicalKeyboardKey.arrowLeft), PlayerKeyRoute.handle);
    expect(route(LogicalKeyboardKey.arrowRight), PlayerKeyRoute.handle);
    expect(route(LogicalKeyboardKey.arrowUp), PlayerKeyRoute.handle);
  });

  test('contrôles visibles, un bouton sélectionné : flèches et OK vont au bouton', () {
    for (final k in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
    ]) {
      expect(route(k, visible: true, button: true), PlayerKeyRoute.toFocusedButton, reason: k.keyLabel);
    }
  });

  test('contrôles visibles sans bouton sélectionné : OK met en pause, les flèches restent au lecteur', () {
    expect(route(LogicalKeyboardKey.select, visible: true), PlayerKeyRoute.handle);
    expect(route(LogicalKeyboardKey.arrowLeft, visible: true), PlayerKeyRoute.handle);
  });

  test('lecture/pause, chaînes et chiffres de la télécommande marchent toujours', () {
    for (final k in [
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.channelUp,
      LogicalKeyboardKey.channelDown,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.numpad5,
    ]) {
      expect(route(k), PlayerKeyRoute.handle, reason: k.keyLabel);
      expect(route(k, visible: true, button: true), PlayerKeyRoute.handle, reason: k.keyLabel);
    }
  });

  testWidgets('un panneau ouvert donne le focus à son premier élément, pas au bouton Fermer', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            PlayerSidePanel(
              right: true,
              width: 400,
              title: 'Chaînes',
              onClose: () {},
              child: ListView(
                children: [
                  TextButton(onPressed: () {}, child: const Text('TF1')),
                  TextButton(onPressed: () {}, child: const Text('France 2')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await t.pump();
    final button = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>();
    expect((button?.child as Text?)?.data, 'TF1');
  });
}
