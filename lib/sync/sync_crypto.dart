import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as c;

/// The data could not be decrypted: wrong keys (the account password was
/// changed on another device) or altered data.
class SyncKeyException implements Exception {
  @override
  String toString() => 'Données du compte illisibles avec ce mot de passe.';
}

String normalizeEmail(String email) => email.trim().toLowerCase();

String _b64url(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

/// PBKDF2-HMAC-SHA256 with a 32-byte output (RFC 8018).
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

/// Keys of a sync account, derived on the device from the email and password.
///
/// The password never leaves the device: Supabase receives [authSecret], a
/// one-way derivative of it, and the data is encrypted with [encKey], which
/// the server cannot work out from [authSecret]. Item ids are HMACs keyed
/// with [idKey], so the server cannot tell what they are either.
class SyncKeys {
  const SyncKeys({required this.encKey, required this.idKey, this.authSecret = ''});

  /// OWASP 2023 recommendation for PBKDF2-HMAC-SHA256 (about 2 s).
  static const defaultIterations = 600000;

  final Uint8List encKey;
  final Uint8List idKey;

  /// Sent to Supabase as the account password (not kept on the device).
  final String authSecret;

  /// Derives the keys in a background isolate.
  static Future<SyncKeys> derive(String email, String password, {int iterations = defaultIterations}) =>
      Isolate.run(() => deriveSync(email, password, iterations: iterations));

  static SyncKeys deriveSync(String email, String password, {int iterations = defaultIterations}) {
    final salt = utf8.encode('bobine-sync|${normalizeEmail(email)}');
    final master = pbkdf2Sha256(utf8.encode(password), salt, iterations);
    final h = Hmac(sha256, master);
    Uint8List sub(String label) => Uint8List.fromList(h.convert(utf8.encode(label)).bytes);
    return SyncKeys(authSecret: _b64url(sub('bobine-auth')), encKey: sub('bobine-enc'), idKey: sub('bobine-id'));
  }

  /// What the device keeps to synchronise without asking the password again.
  String toStorage() => jsonEncode({'enc': base64Encode(encKey), 'id': base64Encode(idKey)});

  static SyncKeys? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final j = jsonDecode(value) as Map;
      return SyncKeys(encKey: base64Decode(j['enc'] as String), idKey: base64Decode(j['id'] as String));
    } catch (_) {
      return null;
    }
  }
}

/// Turns sync records into opaque ids and encrypted payloads (AES-256-GCM,
/// the item id as associated data so a payload cannot be moved to another id).
class SyncCodec {
  SyncCodec(SyncKeys keys) : _idHmac = Hmac(sha256, keys.idKey), _key = c.SecretKey(keys.encKey);

  static final _aes = c.AesGcm.with256bits();
  final Hmac _idHmac;
  final c.SecretKey _key;

  String itemId(String naturalKey) => _b64url(_idHmac.convert(utf8.encode(naturalKey)).bytes);

  Future<String> seal(String id, Map<String, Object?> value) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(value)), secretKey: _key, aad: utf8.encode(id));
    return base64Encode(box.concatenation());
  }

  Future<Map<String, Object?>> open(String id, String payload) async {
    try {
      final box = c.SecretBox.fromConcatenation(
        base64Decode(payload),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clear = await _aes.decrypt(box, secretKey: _key, aad: utf8.encode(id));
      return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
    } catch (_) {
      throw SyncKeyException();
    }
  }
}
