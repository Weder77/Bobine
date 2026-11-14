import 'package:bobine/data/db.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/tv/tv_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppSettings st;
  late List<TvSetting> rows;

  setUp(() {
    st = AppSettings(Repository(openMemoryDatabase()));
    rows = tvPlaybackSettings(st);
  });

  TvSetting row(String label) => rows.firstWhere((r) => r.label == label);

  test('les quatre réglages de lecture, dans l’ordre de la maquette', () {
    expect(rows.map((r) => r.label), ['Qualité vidéo', 'Langue audio', 'Sous-titres', 'Épisode suivant automatique']);
  });

  test('Qualité vidéo fait tourner la qualité préférée, dans les deux sens', () {
    final q = row('Qualité vidéo');
    expect(q.value(), 'Automatique');
    q.change!(1);
    expect(st.preferredQuality, 'FHD');
    expect(q.value(), 'Full HD');
    q.change!(-1);
    q.change!(-1);
    expect(st.preferredQuality, 'SD');
  });

  test('Épisode suivant automatique bascule', () {
    final r = row('Épisode suivant automatique');
    final before = st.autoNextEpisode;
    r.change!(1);
    expect(st.autoNextEpisode, !before);
  });

  test('Sous-titres : Désactivés → Français écrit les codes de langue', () {
    st.update((s) => s.subtitleLang = '');
    final r = row('Sous-titres');
    expect(r.value(), 'Désactivés');
    r.change!(1);
    expect(st.subtitleLang, 'fr,fre,fra');
    expect(r.value(), 'Français');
  });

  test('Langue audio : Version originale efface la préférence', () {
    st.update((s) => s.audioLang = 'fr,fre,fra');
    final r = row('Langue audio');
    expect(r.value(), 'Français');
    r.change!(1);
    expect(st.audioLang, '');
    expect(r.value(), 'Version originale');
  });
}
