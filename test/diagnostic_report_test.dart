import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/models.dart';
import 'package:bobine/ui/diagnostic_screen.dart';

void main() {
  test('a shared report names neither the provider, the account nor the person', () {
    const sources = [
      Source(
        id: 1,
        name: 'tv.example.net',
        type: SourceType.xtream,
        url: 'http://tv.example.net:8080',
        username: 'jean.dupont',
        password: 'x',
      ),
      Source(id: 2, name: 'Ma liste', type: SourceType.m3u, url: 'https://lists.example.org/a.m3u'),
    ];
    final out = anonymizeReport(
      'Source « tv.example.net » : erreur http://tv.example.net:8080/live/jean.dupont/***/1.ts\n'
      'Source « Ma liste » : https://lists.example.org/a.m3u\n'
      r'Fichier : C:\Users\Jean Dupont\Videos\Bobine\a.ts',
      sources: sources,
      home: r'C:\Users\Jean Dupont',
    );
    expect(out, isNot(contains('example')));
    expect(out, isNot(contains('jean')));
    expect(out, isNot(contains('Jean Dupont')));
    expect(out, contains('serveur-1'));
    expect(out, contains('compte-1'));
    expect(out, contains('source-2'));
    expect(out, contains(r'~\Videos'));
  });
}
