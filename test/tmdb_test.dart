import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/features/tmdb.dart';

void main() {
  test('provider names are cleaned before searching TMDB', () {
    expect(cleanTitle('FR - Odyssée (2018) [4K]'), ('Odyssée', 2018));
    expect(cleanTitle('|FR| Les Veilleurs S01'), ('Les Veilleurs', null));
    expect(cleanTitle('Le Phare - 2016', year: 2015), ('Le Phare', 2015));
    expect(cleanTitle('[VOSTFR] Brume MULTI 1080p'), ('Brume', null));
    expect(cleanTitle('EN: The Lighthouse (2019)'), ('The Lighthouse', 2019));
    expect(cleanTitle('Marée'), ('Marée', null));
  });

  test('cached info survives a round trip', () {
    const info = TmdbInfo(id: 7, title: 'Odyssée', genres: ['Drame'], cast: ['A', 'B'], rating: 7.4, year: 2018);
    final back = TmdbInfo.fromJson(info.toJson());
    expect(back.id, 7);
    expect(back.genres, ['Drame']);
    expect(back.cast, ['A', 'B']);
    expect(back.rating, 7.4);
  });
}
