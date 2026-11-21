import 'package:bobine/core/device.dart';
import 'package:bobine/ui/widgets/tv_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Device.debugTv = null);

  // Like the account form: a small link at the right, above the password.
  Future<void> form(WidgetTester t) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFormNav(
            child: Column(
              children: [
                const TextField(key: ValueKey('email')),
                Row(
                  children: [
                    const Text('Mot de passe'),
                    const Spacer(),
                    TextButton(onPressed: () {}, child: const Text('Mot de passe oublié ?')),
                  ],
                ),
                const TextField(key: ValueKey('password')),
                FilledButton(onPressed: () {}, child: const Text('Se connecter')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String focused() {
    final c = FocusManager.instance.primaryFocus?.context;
    final key = c?.findAncestorWidgetOfExactType<TextField>()?.key;
    if (key is ValueKey<String>) return key.value;
    final b = c?.findAncestorWidgetOfExactType<TextButton>() ?? c?.findAncestorWidgetOfExactType<FilledButton>();
    return ((b?.child) as Text?)?.data ?? '?';
  }

  testWidgets('sur la télé, Bas et Haut passent par tous les éléments, dans l’ordre de lecture', (t) async {
    Device.debugTv = true;
    await form(t);
    await t.tap(find.byKey(const ValueKey('email')));
    await t.pump();
    final order = <String>[focused()];
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      order.add(focused());
    }
    expect(order, ['email', 'Mot de passe oublié ?', 'password', 'Se connecter']);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(focused(), 'password');
  });

  testWidgets('sur ordinateur, rien ne change (Bas reste dans le champ)', (t) async {
    Device.debugTv = false;
    await form(t);
    await t.tap(find.byKey(const ValueKey('email')));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(focused(), 'email');
  });

  testWidgets('dans une fenêtre de dialogue, Bas passe aussi par tous les boutons dans l’ordre', (t) async {
    Device.debugTv = true;
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvCanvas(child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                // The link beside the field: Down by geometry went straight
                // to "Valider" and skipped it.
                content: Row(
                  children: [
                    const Expanded(child: TextField(key: ValueKey('code'))),
                    TextButton(onPressed: () {}, child: const Text('Code oublié ?')),
                  ],
                ),
                actions: [TextButton(onPressed: () {}, child: const Text('Valider'))],
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Ouvrir'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('code')));
    await t.pump();
    final order = <String>[];
    for (var i = 0; i < 2; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      order.add(focused());
    }
    expect(order, ['Code oublié ?', 'Valider']);
  });
}
