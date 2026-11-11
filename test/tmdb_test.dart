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
    // Real titles are left whole.
    expect(cleanTitle('The French Dispatch (2021)'), ('The French Dispatch', 2021));
    expect(cleanTitle('French Connection'), ('French Connection', null));
    expect(cleanTitle('CSI: Miami'), ('CSI: Miami', null));
    expect(cleanTitle('Blade Runner - 2049'), ('Blade Runner - 2049', null));
    expect(cleanTitle('ENG: Dune FRENCH HD'), ('Dune', null));
    expect(cleanTitle('Dune (VOSTFR, 1080p)'), ('Dune', null));
  });

  test('a TMDB result far from the title is not taken', () {
    final results = <Map>[
      {'id': 1, 'title': 'Le Phare des sables', 'original_title': 'Sand Lighthouse'},
      {'id': 2, 'title': 'The Lighthouse', 'original_title': 'The Lighthouse'},
    ];
    expect(pickTmdbResult(results, 'The Lighthouse', tv: false)?['id'], 2);
    expect(pickTmdbResult(results, 'the lighthouse', tv: false)?['id'], 2);
    expect(pickTmdbResult(results, 'Un tout autre film', tv: false), isNull);
    expect(
      pickTmdbResult(
        [
          {'id': 3, 'name': 'Les Veilleurs du phare', 'original_name': 'x'},
        ],
        'Les Veilleurs',
        tv: true,
      )?['id'],
      3,
    );
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
