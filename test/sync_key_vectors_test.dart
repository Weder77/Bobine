import 'dart:convert';
import 'dart:io';

import 'package:bobine/sync/sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The keys the app derives must stay the ones the site derives (site/): both
/// are checked against test/fixtures/sync_key_vectors.json, written by an
/// independent implementation (tool/sync_key_vectors.py).
void main() {
  final vectors = (jsonDecode(File('test/fixtures/sync_key_vectors.json').readAsStringSync()) as List)
      .cast<Map<String, Object?>>();

  for (final v in vectors) {
    test('keys of ${v['email']} (${v['iterations']} iterations)', () {
      final keys = SyncKeys.deriveSync(v['email'] as String, v['password'] as String, iterations: v['iterations'] as int);
      expect(keys.authSecret, v['authSecret']);
      expect(base64Encode(keys.encKey), v['encKey']);
      expect(base64Encode(keys.idKey), v['idKey']);
    });
  }

  test('the default iterations are among the vectors', () {
    expect(vectors.map((v) => v['iterations']), contains(SyncKeys.defaultIterations));
  });
}
