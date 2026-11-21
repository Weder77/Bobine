import 'package:bobine/tv/tv_stage.dart';
import 'package:bobine/ui/widgets/tv_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<double> ratioInside(WidgetTester t, Widget Function(Widget) wrap) async {
    // A 1080p TV box: 1920 × 1080 pixels, reported as 960 × 540 points.
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    late double ratio;
    await t.pumpWidget(
      MaterialApp(
        home: wrap(
          Builder(
            builder: (context) {
              ratio = MediaQuery.devicePixelRatioOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return ratio;
  }

  testWidgets('scène télé : un point de la maquette vaut un pixel sur un écran 1080p', (t) async {
    expect(await ratioInside(t, (c) => TvStage(child: c)), closeTo(1, 0.001));
  });

  testWidgets('dans le cadre télé aussi (les images y sont décodées à leur taille réelle)', (t) async {
    expect(await ratioInside(t, (c) => TvCanvas(child: c)), closeTo(1.5, 0.001));
    expect(await ratioInside(t, (c) => TvCanvas(child: TvStage(child: c))), closeTo(1, 0.001));
  });
}
