import 'package:bobine/core/theme.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/ui/widgets/rows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the play button shown over a "Reprendre" card resumes it', (t) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Desktop: hover highlights are shown (the test platform defaults to touch).
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final played = <String>[];
    final entry = ProgressEntry(
      sourceId: 1,
      kind: ContentKind.episode,
      extId: '373225',
      position: const Duration(minutes: 3),
      duration: const Duration(minutes: 52),
      finished: false,
      updatedAt: DateTime(2026, 11, 9),
      title: 'Nocturne (2026)',
      subtitle: 'S01E01 · Sorti du tombeau',
      seriesExt: '42',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        home: Scaffold(
          body: ResumeRail(entries: [entry], onPlay: (p) => played.add(p.extId), onRemove: (_) {}),
        ),
      ),
    );
    // Hover the card: the round play button appears in the middle of the picture.
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.byType(AspectRatio).first));
    await t.pumpAndSettle();
    final button = find.byTooltip('Reprendre');
    expect(button, findsOneWidget);
    await t.tap(button, kind: PointerDeviceKind.mouse);
    await t.pump();
    expect(played, ['373225']);
  });
}
