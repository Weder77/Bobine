import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ui/widgets/common.dart';

void main() {
  test('favourite counter is updated without touching other entries', () {
    const entries = [
      CategoryEntry(id: 'all', label: 'Tous les films', count: 13569, icon: Icons.apps_rounded),
      CategoryEntry(id: 'fav', label: 'Mes favoris', count: 0, icon: Icons.favorite_rounded),
      CategoryEntry(id: 'c:1', label: 'Action', count: 58),
    ];
    final updated = withFavoriteCount(entries, 1);
    expect(updated.map((e) => e.count), [13569, 1, 58]);
    expect(updated[1].label, 'Mes favoris');
    expect(updated[1].icon, Icons.favorite_rounded);
  });
}
