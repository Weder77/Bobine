import 'package:bobine/core/theme.dart';
import 'package:bobine/ui/widgets/chips.dart';
import 'package:bobine/ui/widgets/rows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('everything that can be clicked shows the hand, in both themes', (t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<MouseCursor> over(Finder f) async {
      await mouse.moveTo(t.getCenter(f));
      await t.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
    }

    for (final theme in [darkTheme, buildTheme(AppPalette.light)]) {
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton(key: const Key('filled'), onPressed: () {}, child: const Text('Lecture')),
                OutlinedButton(key: const Key('outlined'), onPressed: () {}, child: const Text('Ajouter un profil')),
                TextButton(key: const Key('text'), onPressed: () {}, child: const Text('Annuler')),
                // Like the player's buttons: their own style, no cursor in it.
                IconButton(
                  key: const Key('icon'),
                  onPressed: () {},
                  style: IconButton.styleFrom(fixedSize: const Size(44, 44)),
                  icon: const Icon(Icons.cast_rounded),
                ),
                Checkbox(key: const Key('checkbox'), value: true, onChanged: (_) {}),
                SegmentedButton<int>(
                  key: const Key('segmented'),
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Xtream')),
                    ButtonSegment(value: 2, label: Text('M3U')),
                  ],
                  selected: const {1},
                  onSelectionChanged: (_) {},
                ),
                CircleAction(
                  key: const Key('circle'),
                  icon: Icons.play_arrow_rounded,
                  onTap: () {},
                  tooltip: 'Lecture',
                ),
                GroupChip(key: const Key('chip'), label: 'Sport', selected: false, onTap: () {}),
                const FilledButton(key: Key('disabled'), onPressed: null, child: Text('Indisponible')),
                const SizedBox(key: Key('empty'), width: 200, height: 60),
              ],
            ),
          ),
        ),
      );
      for (final key in ['filled', 'outlined', 'text', 'icon', 'checkbox', 'segmented', 'circle', 'chip']) {
        expect(await over(find.byKey(Key(key))), SystemMouseCursors.click, reason: key);
      }
      // Not everything: a disabled button and the background keep the arrow.
      expect(await over(find.byKey(const Key('disabled'))), SystemMouseCursors.basic);
      expect(await over(find.byKey(const Key('empty'))), SystemMouseCursors.basic);
    }
  });
}
