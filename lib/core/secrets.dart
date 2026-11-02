import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Encrypts small secrets (passwords, URLs containing credentials) before
/// they are written to the local database.
///
/// Windows: DPAPI (`CryptProtectData`), bound to the current Windows user
/// account, so a copied `lumen.db` cannot be read on another account or PC.
/// Other platforms: values are stored as-is for now.
///
/// Values are tagged with a prefix so plain (legacy) values keep working and
/// can be migrated transparently.
class Secrets {
  static const prefix = 'dpapi:';
  static final Map<String, String> _revealed = {};

  static bool get supported => Platform.isWindows;

  /// Returns the value to store in the database.
  static String? protect(String? value) {
    if (value == null || value.isEmpty || !supported || value.startsWith(prefix)) return value;
    try {
      return prefix + base64.encode(_Dpapi.protect(utf8.encode(value)));
    } catch (_) {
      return value; // never lose the value: fall back to plain storage
    }
  }

  /// Returns the clear value of something read from the database, or null
  /// when it was encrypted by another user / machine and cannot be read.
  static String? reveal(String? stored) {
    if (stored == null || !stored.startsWith(prefix)) return stored;
    final cached = _revealed[stored];
    if (cached != null) return cached;
    if (!supported) return null;
    try {
      final clear = utf8.decode(_Dpapi.unprotect(base64.decode(stored.substring(prefix.length))));
      if (_revealed.length > 64) _revealed.clear();
      _revealed[stored] = clear;
      return clear;
    } catch (_) {
      return null;
    }
  }
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(Pointer<_DataBlob> dataIn, Pointer<Void> description,
    Pointer<_DataBlob> entropy, Pointer<Void> reserved, Pointer<Void> prompt, Uint32 flags,
    Pointer<_DataBlob> dataOut);
typedef _CryptDart = int Function(Pointer<_DataBlob> dataIn, Pointer<Void> description,
    Pointer<_DataBlob> entropy, Pointer<Void> reserved, Pointer<Void> prompt, int flags,
    Pointer<_DataBlob> dataOut);

/// Minimal DPAPI binding (crypt32.dll + LocalFree from kernel32.dll).
class _Dpapi {
  static const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN
  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _protect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
  static final _unprotect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptUnprotectData');
  static final _localFree = _kernel32
      .lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('LocalFree');

  /// Ties the encrypted values to this application.
  static final List<int> _entropy = utf8.encode('Lumen IPTV v1');

  static List<int> protect(List<int> data) => _run(_protect, data);
  static List<int> unprotect(List<int> data) => _run(_unprotect, data);

  static List<int> _run(_CryptDart fn, List<int> data) {
    return using((arena) {
      Pointer<_DataBlob> blob(List<int> bytes) {
        final buffer = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final b = arena<_DataBlob>();
        b.ref
          ..cbData = bytes.length
          ..pbData = buffer;
        return b;
      }

      final input = blob(data);
      final entropy = blob(_entropy);
      final output = arena<_DataBlob>();
      final ok = fn(input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output);
      if (ok == 0) throw StateError('DPAPI call failed');
      try {
        return List<int>.of(output.ref.pbData.asTypedList(output.ref.cbData));
      } finally {
        _localFree(output.ref.pbData.cast());
      }
    });
  }
}
