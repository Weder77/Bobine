import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../core/app_log.dart';
import '../core/secrets.dart';
import '../core/text.dart';
import '../data/repository.dart';
import 'supabase_api.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';

enum SyncStatus {
  /// No account on this device.
  signedOut,

  /// Account created, waiting for the code sent by e-mail.
  confirming,

  /// Signed in, nothing running.
  idle,
  syncing,

  /// Signed in, the last attempt failed (offline…): retried later.
  error,
}

/// The account of this device and its synchronisation.
///
/// Signed in, it synchronises at start, a few seconds after a local change,
/// and every few minutes for the changes made on the other devices.
class SyncService extends ChangeNotifier {
  SyncService(this._repo, this._settings, {SupabaseApi? api, required this.onChanges}) : _api = api ?? SupabaseApi() {
    _session = SupabaseSession.fromStorage(Secrets.reveal(_repo.kvGet(_sessionKey)));
    _keys = SyncKeys.fromStorage(Secrets.reveal(_repo.kvGet(_keysKey)));
    if (_session == null || _keys == null) {
      _session = null;
      _keys = null;
    } else {
      status = SyncStatus.idle;
    }
    lastSync = DateTime.tryParse(_repo.kvGet(_lastKey) ?? '');
  }

  static const _sessionKey = 'sync.session';
  static const _keysKey = 'sync.keys';
  static const _lastKey = 'sync.last';

  /// Delay before sending a local change (several changes go together).
  static const changeDelay = Duration(seconds: 8);

  /// How often the other devices' changes are fetched.
  static const fetchEvery = Duration(minutes: 3);

  final Repository _repo;
  final SyncedSettings _settings;
  final SupabaseApi _api;

  /// What a synchronisation brought (to refresh the screens).
  final void Function(SyncChanges changes) onChanges;

  SupabaseSession? _session;
  SyncKeys? _keys;

  SyncStatus status = SyncStatus.signedOut;
  DateTime? lastSync;

  /// Why the last synchronisation failed, or a reason the account was signed
  /// out (shown on the account page).
  String? message;

  /// Address waiting for its code ([SyncStatus.confirming]).
  String? pendingEmail;
  SyncKeys? _pendingKeys;

  Timer? _poll;
  Timer? _soon;
  Future<void>? _running;
  bool _again = false;

  /// Changes each time the account of this device does (signed in, signed
  /// out): a synchronisation started before belongs to the previous one and
  /// must not write anything any more.
  int _account = 0;

  bool get signedIn => _session != null && _keys != null;

  /// Whether [password] is the account's: checked on this device, by the
  /// keys it gives (no network needed). Used to choose a new parental code
  /// when it was forgotten.
  Future<bool> checkPassword(String password) async {
    final keys = _keys, mail = email;
    if (keys == null || mail == null || password.isEmpty) return false;
    final again = await SyncKeys.derive(mail, password);
    final a = again.encKey, b = keys.encKey;
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  String? get email => _session?.email ?? pendingEmail;

  /// Starts the automatic synchronisation (at app start).
  void start() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    if (signedIn) syncSoon(const Duration(seconds: 2));
  }

  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Failures in a row (the account refuses, the service is down): the
  /// automatic tries wait longer each time, up to half an hour.
  int _failures = 0;
  DateTime? _retryAt;

  void _tick() {
    if (!signedIn || _running != null) return;
    final retry = _retryAt;
    if (retry != null && DateTime.now().isBefore(retry)) return;
    final pending = _repo.db.select('SELECT 1 FROM sync_log LIMIT 1').isNotEmpty;
    if (pending || DateTime.now().difference(_lastFetch) >= fetchEvery) syncSoon(pending ? changeDelay : Duration.zero);
  }

  /// Synchronises after [delay] (several calls give one synchronisation).
  void syncSoon([Duration delay = changeDelay]) {
    if (!signedIn || (_soon?.isActive ?? false)) return;
    _soon = Timer(delay, () => unawaited(syncNow()));
  }

  /// Synchronises now; returns when done (errors end up in [message]).
  Future<void> syncNow() {
    if (!signedIn) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _run().whenComplete(() {
      _running = null;
      if (_again && signedIn) {
        _again = false;
        syncSoon(const Duration(seconds: 1));
      }
    });
  }

  Future<void> _run() async {
    status = SyncStatus.syncing;
    notifyListeners();
    // Signing out (or into another account) while this run waits on the
    // network makes it someone else's: it stops there. It used to finish,
    // and wrote back "last change received" after the sign-out had erased
    // it, so that the next account was never read from its beginning.
    final account = _account;
    bool stale() => account != _account;
    final remote = SupabaseRemote(
      _api,
      _session!,
      onSession: (s) {
        if (!stale()) _keepSession(s);
      },
    );
    final engine = SyncEngine(
      repo: _repo,
      codec: SyncCodec(_keys!),
      remote: remote,
      settings: _settings,
      cancelled: stale,
    );
    try {
      _lastFetch = DateTime.now();
      final changes = await engine.run();
      if (stale()) return;
      lastSync = DateTime.now();
      _repo.kvSet(_lastKey, lastSync!.toIso8601String());
      message = null;
      status = SyncStatus.idle;
      _failures = 0;
      _retryAt = null;
      if (changes.received + changes.sent > 0) {
        AppLog.add('Synchro : ${changes.received} reçu(s), ${changes.sent} envoyé(s)');
      }
      if (changes.skipped > 0) AppLog.add('Synchro : ${changes.skipped} élément(s) illisible(s) laissé(s) de côté');
      if (changes.any) onChanges(changes);
    } catch (e) {
      // The failure of the previous account says nothing about this one.
      if (stale() || e is SyncCancelled) return;
      _failed(e);
    }
    notifyListeners();
  }

  void _failed(Object e) {
    if (e is SyncKeyException) {
      _forget(message: 'Le mot de passe du compte a changé sur un autre appareil : reconnecte-toi.');
    } else if (e is SyncApiException) {
      if (e.sessionLost) {
        _forget(message: e.message);
      } else {
        message = e.message;
        status = SyncStatus.error;
        _backOff();
      }
    } else if (e is SqliteException) {
      // Busy with an import: next time.
      final busy = e.extendedResultCode & 0xff == 5 || e.extendedResultCode & 0xff == 6;
      message = busy ? null : 'Erreur de la base locale : ${e.message} (${e.extendedResultCode})';
      status = busy ? SyncStatus.idle : SyncStatus.error;
      if (!busy) AppLog.add('Synchro : $e');
    } else {
      message = 'Synchro impossible : ${redactCredentials('$e')}';
      status = SyncStatus.error;
      _backOff();
      AppLog.add('Synchro : $e');
    }
  }

  void _backOff() {
    _failures++;
    final seconds = 20 * (1 << (_failures - 1).clamp(0, 7));
    _retryAt = DateTime.now().add(Duration(seconds: seconds.clamp(20, 1800)));
  }

  void _keepSession(SupabaseSession s) {
    if (_keys == null) return; // signed out meanwhile
    _session = s;
    _repo.kvSet(_sessionKey, Secrets.protect(s.toStorage()));
  }

  void _begin(SupabaseSession s, SyncKeys keys) {
    _account++;
    _keys = keys;
    _keepSession(s);
    _repo.kvSet(_keysKey, Secrets.protect(keys.toStorage()));
    pendingEmail = null;
    _pendingKeys = null;
    message = null;
    status = SyncStatus.idle;
    notifyListeners();
    unawaited(syncNow());
  }

  /// Signs out this device; its data stays here.
  void _forget({String? message}) {
    _account++;
    _soon?.cancel();
    _session = null;
    _keys = null;
    pendingEmail = null;
    _pendingKeys = null;
    // Retried when an import holds the database: a sign-out that stayed on
    // disk signed the device in again at the next start.
    _repo.write(() {
      _repo.db.execute('DELETE FROM kv WHERE key IN (?, ?, ?, ?)', [
        _sessionKey,
        _keysKey,
        _lastKey,
        SyncEngine.cursorKey,
      ]);
    });
    lastSync = null;
    this.message = message;
    status = SyncStatus.signedOut;
    notifyListeners();
  }

  // ---------------------------------------------------------------- account

  /// Creates an account. Throws [SyncApiException] with a message to show.
  Future<void> signUp(String email, String password) async {
    email = normalizeEmail(email);
    final keys = await SyncKeys.derive(email, password);
    final session = await _api.signUp(email, keys.authSecret);
    if (session != null) return _begin(session, keys);
    pendingEmail = email;
    _pendingKeys = keys;
    status = SyncStatus.confirming;
    message = null;
    notifyListeners();
  }

  /// Confirms the address with the code received by e-mail.
  Future<void> confirm(String code) async {
    final email = pendingEmail, keys = _pendingKeys;
    if (email == null || keys == null) return;
    _begin(await _api.verify(email, code), keys);
  }

  Future<void> resendCode() async {
    if (pendingEmail != null) await _api.resendSignup(pendingEmail!);
  }

  void cancelConfirmation() => _forget();

  Future<void> signIn(String email, String password) async {
    email = normalizeEmail(email);
    final keys = await SyncKeys.derive(email, password);
    try {
      _begin(await _api.signIn(email, keys.authSecret), keys);
    } on SyncApiException catch (e) {
      if (e.code != 'email_not_confirmed') rethrow;
      pendingEmail = email;
      _pendingKeys = keys;
      status = SyncStatus.confirming;
      message = null;
      notifyListeners();
      await _api.resendSignup(email);
    }
  }

  /// Sends a code to choose a new password.
  Future<void> forgotPassword(String email) => _api.recover(normalizeEmail(email));

  /// Sets a new password with the code received. What the account held was
  /// encrypted with the old password: it is replaced by this device's data.
  Future<void> resetPassword(String email, String code, String password) async {
    email = normalizeEmail(email);
    final session = await _api.verify(email, code, type: 'recovery');
    final keys = await SyncKeys.derive(email, password);
    await _api.setPassword(session, keys.authSecret);
    await _api.wipe(session);
    _repo.db.execute('DELETE FROM kv WHERE key = ?', [SyncEngine.cursorKey]);
    _begin(session, keys);
  }

  /// Signs this device out. Here first, at once and whatever happens next:
  /// nothing of the session is kept. Then on the server, when it can be
  /// reached (offline, the session only ends there when it expires).
  Future<void> signOut() async {
    final s = _session;
    _forget();
    if (s != null) {
      try {
        await SupabaseRemote(_api, s, onSession: (_) {}).signOut();
      } catch (_) {
        // Signed out here anyway.
      }
    }
  }

  /// Deletes the account and what it holds on the server; this device keeps
  /// its data.
  Future<void> deleteAccount() async {
    final s = _session;
    if (s == null) return;
    final remote = SupabaseRemote(_api, s, onSession: _keepSession);
    await _api.deleteAccount(await remote.current());
    _forget(message: 'Compte supprimé. Les données de cet appareil sont conservées.');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _soon?.cancel();
    _api.close();
    super.dispose();
  }
}
