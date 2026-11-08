import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../core/app_log.dart';
import '../core/secrets.dart';
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

  bool get signedIn => _session != null && _keys != null;
  String? get email => _session?.email ?? pendingEmail;

  /// Starts the automatic synchronisation (at app start).
  void start() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    if (signedIn) syncSoon(const Duration(seconds: 2));
  }

  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  void _tick() {
    if (!signedIn || _running != null) return;
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
    final remote = SupabaseRemote(_api, _session!, onSession: _keepSession);
    final engine = SyncEngine(repo: _repo, codec: SyncCodec(_keys!), remote: remote, settings: _settings);
    try {
      _lastFetch = DateTime.now();
      final changes = await engine.run();
      lastSync = DateTime.now();
      _repo.kvSet(_lastKey, lastSync!.toIso8601String());
      message = null;
      status = SyncStatus.idle;
      if (changes.received + changes.sent > 0) {
        AppLog.add('Synchro : ${changes.received} reçu(s), ${changes.sent} envoyé(s)');
      }
      if (changes.any) onChanges(changes);
      if (!signedIn) status = SyncStatus.signedOut; // signed out meanwhile
    } on SyncKeyException {
      _forget(message: 'Le mot de passe du compte a changé sur un autre appareil : reconnecte-toi.');
    } on SyncApiException catch (e) {
      if (e.sessionLost) {
        _forget(message: e.message);
      } else {
        message = e.message;
        status = SyncStatus.error;
      }
    } on SqliteException catch (e) {
      // Busy with an import: next time.
      final busy = e.extendedResultCode & 0xff == 5 || e.extendedResultCode & 0xff == 6;
      message = busy ? null : 'Erreur de la base locale : $e';
      status = busy ? SyncStatus.idle : SyncStatus.error;
      if (!busy) AppLog.add('Synchro : $e');
    } catch (e) {
      message = 'Synchro impossible : $e';
      status = SyncStatus.error;
      AppLog.add('Synchro : $e');
    }
    notifyListeners();
  }

  void _keepSession(SupabaseSession s) {
    if (_keys == null) return; // signed out meanwhile
    _session = s;
    _repo.kvSet(_sessionKey, Secrets.protect(s.toStorage()));
  }

  void _begin(SupabaseSession s, SyncKeys keys) {
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
    _soon?.cancel();
    _session = null;
    _keys = null;
    pendingEmail = null;
    _pendingKeys = null;
    for (final k in [_sessionKey, _keysKey, _lastKey, SyncEngine.cursorKey]) {
      _repo.db.execute('DELETE FROM kv WHERE key = ?', [k]);
    }
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

  /// The address was confirmed with the link of the e-mail: signs in.
  Future<void> confirmedByLink() async {
    final email = pendingEmail, keys = _pendingKeys;
    if (email == null || keys == null) return;
    _begin(await _api.signIn(email, keys.authSecret), keys);
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

  Future<void> signOut() async {
    final s = _session;
    _forget();
    if (s != null) {
      try {
        await _api.signOut(s);
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
