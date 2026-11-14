import 'package:bobine/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int activated;
  late int menus;

  Future<void> card(WidgetTester t, {bool withMenu = true}) async {
    activated = 0;
    menus = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: HoverBuilder(
            autofocus: true,
            onActivate: () => activated++,
            onContextMenu: withMenu ? (_) => menus++ : null,
            builder: (context, hovered) => const SizedBox(width: 100, height: 60),
          ),
        ),
      ),
    );
    await t.pump();
  }

  for (final key in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA]) {
    testWidgets('appui court sur ${key.keyLabel} : lecture, pas de menu', (t) async {
      await card(t);
      await t.sendKeyDownEvent(key);
      await t.sendKeyUpEvent(key);
      expect((activated, menus), (1, 0));
    });

    testWidgets('appui long sur ${key.keyLabel} : menu seulement, rien au relâchement', (t) async {
      await card(t);
      await t.sendKeyDownEvent(key);
      await t.pump(HoverBuilder.longPressDelay);
      await t.sendKeyRepeatEvent(key);
      await t.sendKeyRepeatEvent(key);
      await t.sendKeyUpEvent(key);
      expect((activated, menus), (0, 1));
    });
  }

  testWidgets('une répétition avant le délai ne compte pas pour un appui long', (t) async {
    await card(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.pump(const Duration(milliseconds: 100));
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect((activated, menus), (1, 0));
  });

  testWidgets('sans menu, Entrée garde le comportement actuel (dès l’appui)', (t) async {
    await card(t, withMenu: false);
    await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
    expect(activated, 1);
    await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect((activated, menus), (1, 0));
  });

  testWidgets('RemoteOk seul (affiches, guide) : court = action, long = menu', (t) async {
    var acts = 0, menu = 0;
    await t.pumpWidget(
      MaterialApp(
        home: RemoteOk(
          onActivate: () => acts++,
          onMenu: (_) => menu++,
          child: Focus(autofocus: true, child: const SizedBox(width: 50, height: 50)),
        ),
      ),
    );
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.pump(HoverBuilder.longPressDelay);
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect((acts, menu), (1, 1));
  });
}
