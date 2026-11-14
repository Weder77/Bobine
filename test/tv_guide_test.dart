import 'package:bobine/data/models.dart';
import 'package:bobine/tv/tv_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 14, 22, 32);
  Program at(int h1, int m1, int h2, int m2) =>
      Program(start: DateTime(2026, 11, 14, h1, m1), stop: DateTime(2026, 11, 14, h2, m2), title: 'P');

  test('en cours : le temps qui reste, OK regarde', () {
    final p = at(21, 0, 23, 0);
    expect(tvProgramStatus(p, now), 'En cours · reste 28 min');
    expect(tvProgramAction(p, now, reminded: false), 'Regarder');
  });

  test('à venir : dans combien de temps, OK met ou retire le rappel', () {
    final p = at(23, 50, 1, 0).withStop(DateTime(2026, 11, 15, 1));
    expect(tvProgramStatus(p, now), 'Dans 1 h 18');
    expect(tvProgramAction(p, now, reminded: false), 'Me le rappeler');
    expect(tvProgramAction(p, now, reminded: true), 'Retirer le rappel');
  });

  test('terminé : OK va sur la chaîne', () {
    final p = at(20, 0, 21, 0);
    expect(tvProgramStatus(p, now), 'Terminé');
    expect(tvProgramAction(p, now, reminded: false), 'Voir la chaîne');
  });

  test('la fenêtre du guide commence une demi-heure avant maintenant, arrondie', () {
    expect(tvGuideStart(now), DateTime(2026, 11, 14, 22));
    expect(tvGuideStart(DateTime(2026, 11, 14, 22, 10)), DateTime(2026, 11, 14, 21, 30));
  });
}

extension on Program {
  Program withStop(DateTime stop) => Program(start: start, stop: stop, title: title);
}
