import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_engine.dart';

/// Bobine's Supabase project. The publishable key is meant to ship in apps:
/// row level security decides what each account may read, and writes only go
/// through `sync_push` (see supabase/migrations).
const kSupabaseUrl = 'https://rjgsyscvvoawfenmcnvu.supabase.co';
const kSupabaseKey = 'sb_publishable_cTBVl8rFbV2vphxxzRrLcQ_EFnjzvyn';

/// An error to show as it is (in French).
class SyncApiException implements Exception {
  SyncApiException(this.message, {this.code, this.status, this.network = false});
  final String message;

  /// Supabase error code (`invalid_credentials`, `otp_expired`…).
  final String? code;
  final int? status;

  /// No answer (offline, server paused): worth retrying later.
  final bool network;

  /// The session can no longer be used: sign in again.
  bool get sessionLost =>
      status == 401 || const {'refresh_token_not_found', 'session_not_found', 'user_not_found'}.contains(code);

  @override
  String toString() => message;
}

class SupabaseSession {
  const SupabaseSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String email;

  bool get expiresSoon => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  factory SupabaseSession.fromAuth(Map<String, Object?> j) {
    final user = (j['user'] as Map?)?.cast<String, Object?>() ?? const {};
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return SupabaseSession(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: '${user['id'] ?? ''}',
      email: '${user['email'] ?? ''}',
    );
  }

  String toStorage() => jsonEncode({
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.millisecondsSinceEpoch,
    'user_id': userId,
    'email': email,
  });

  static SupabaseSession? fromStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final j = jsonDecode(value) as Map;
      return SupabaseSession(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(j['expires_at'] as int),
        userId: j['user_id'] as String,
        email: j['email'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Auth (GoTrue) and data (PostgREST) calls, with plain HTTP.
class SupabaseApi {
  SupabaseApi({this.url = kSupabaseUrl, this.apiKey = kSupabaseKey, HttpClient? http})
    : _http =
          http ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 15)
            ..idleTimeout = const Duration(seconds: 30));

  final String url;
  final String apiKey;
  final HttpClient _http;

  void close() => _http.close(force: true);

  Future<Object?> _call(
    String method,
    String path, {
    Object? body,
    String? token,
    Map<String, String> query = const {},
  }) async {
    final uri = Uri.parse('$url$path').replace(queryParameters: query.isEmpty ? null : query);
    try {
      final request = await _http.openUrl(method, uri).timeout(const Duration(seconds: 20));
      request.headers
        ..set('apikey', apiKey)
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, 'Bobine');
      if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 60));
      final text = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 60));
      final json = text.isEmpty ? null : _tryJson(text);
      if (response.statusCode >= 400) throw _error(response.statusCode, json);
      return json;
    } on SyncApiException {
      rethrow;
    } on TimeoutException {
      throw SyncApiException('Le service de synchro ne répond pas.', network: true);
    } on SocketException {
      throw SyncApiException('Pas de connexion au service de synchro.', network: true);
    } on HandshakeException {
      throw SyncApiException('Connexion sécurisée impossible avec le service de synchro.', network: true);
    } on HttpException {
      throw SyncApiException('Connexion interrompue avec le service de synchro.', network: true);
    }
  }

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  static const _messages = {
    'invalid_credentials': 'E-mail ou mot de passe incorrect.',
    'invalid_grant': 'E-mail ou mot de passe incorrect.',
    'email_not_confirmed': 'Adresse pas encore confirmée : saisis le code reçu par e-mail.',
    'user_already_exists': 'Un compte existe déjà avec cette adresse : connecte-toi.',
    'email_exists': 'Un compte existe déjà avec cette adresse : connecte-toi.',
    'otp_expired': 'Code incorrect ou expiré.',
    'over_email_send_rate_limit': "Trop d'e-mails envoyés : réessaie dans quelques minutes.",
    'over_request_rate_limit': 'Trop de tentatives : réessaie dans quelques minutes.',
    'signup_disabled': 'Les inscriptions sont fermées pour le moment.',
    'email_address_invalid': 'Adresse e-mail invalide.',
    'validation_failed': 'Adresse e-mail invalide.',
    'refresh_token_not_found': 'Session expirée : reconnecte-toi.',
    'session_not_found': 'Session expirée : reconnecte-toi.',
    'user_not_found': 'Compte introuvable.',
  };

  static SyncApiException _error(int status, Object? json) {
    final j = json is Map ? json.cast<String, Object?>() : const <String, Object?>{};
    final code = (j['error_code'] ?? j['error'] ?? j['code'])?.toString();
    final detail = (j['msg'] ?? j['message'] ?? j['error_description'])?.toString();
    if (code == 'sync quota exceeded' || (detail ?? '').contains('sync quota exceeded')) {
      return SyncApiException('Limite de données du compte atteinte.', code: 'quota', status: status);
    }
    // The account was deleted from another device (its rows can no longer
    // reference it).
    if (code == '23503') {
      return SyncApiException("Ce compte n'existe plus.", code: 'user_not_found', status: status);
    }
    final known = _messages[code];
    if (known != null) return SyncApiException(known, code: code, status: status);
    if (status == 401) return SyncApiException('Session expirée : reconnecte-toi.', code: code, status: status);
    if (status >= 500) {
      return SyncApiException(
        'Le service de synchro est indisponible pour le moment.',
        code: code,
        status: status,
        network: true,
      );
    }
    return SyncApiException(detail ?? 'Erreur du service de synchro ($status).', code: code, status: status);
  }

  Map<String, Object?> _map(Object? json) =>
      json is Map ? json.cast<String, Object?>() : throw SyncApiException('Réponse inattendue du service de synchro.');

  // ------------------------------------------------------------------- auth

  /// Creates the account. Returns its session, or null when the address must
  /// first be confirmed (a code was sent by e-mail).
  Future<SupabaseSession?> signUp(String email, String secret) async {
    final j = _map(await _call('POST', '/auth/v1/signup', body: {'email': email, 'password': secret}));
    if (j['access_token'] is String) return SupabaseSession.fromAuth(j);
    // An address already registered gets an empty user (no e-mail is sent).
    final user = (j['user'] as Map?) ?? j;
    if (user['identities'] is List && (user['identities'] as List).isEmpty) {
      throw SyncApiException(_messages['user_already_exists']!, code: 'user_already_exists');
    }
    return null;
  }

  /// Checks the code of a sign-up ('email') or forgotten password ('recovery').
  Future<SupabaseSession> verify(String email, String code, {String type = 'email'}) async => SupabaseSession.fromAuth(
    _map(await _call('POST', '/auth/v1/verify', body: {'type': type, 'email': email, 'token': code.trim()})),
  );

  Future<void> resendSignup(String email) => _call('POST', '/auth/v1/resend', body: {'type': 'signup', 'email': email});

  Future<SupabaseSession> signIn(String email, String secret) async => SupabaseSession.fromAuth(
    _map(
      await _call(
        'POST',
        '/auth/v1/token',
        query: {'grant_type': 'password'},
        body: {'email': email, 'password': secret},
      ),
    ),
  );

  Future<SupabaseSession> refresh(SupabaseSession s) async {
    try {
      return SupabaseSession.fromAuth(
        _map(
          await _call(
            'POST',
            '/auth/v1/token',
            query: {'grant_type': 'refresh_token'},
            body: {'refresh_token': s.refreshToken},
          ),
        ),
      );
    } on SyncApiException catch (e) {
      if (e.network) rethrow;
      // A refresh token refused for any other reason will never work again.
      throw SyncApiException('Session expirée : reconnecte-toi.', code: 'session_not_found', status: 401);
    }
  }

  /// Ends this device's session. `scope=local`: without it the service ends
  /// every session of the account, and signing out here signed the user's
  /// other devices out too.
  Future<void> signOut(SupabaseSession s) =>
      _call('POST', '/auth/v1/logout', token: s.accessToken, query: {'scope': 'local'});

  /// Sends a code to choose a new password.
  Future<void> recover(String email) => _call('POST', '/auth/v1/recover', body: {'email': email});

  Future<void> setPassword(SupabaseSession s, String secret) =>
      _call('PUT', '/auth/v1/user', token: s.accessToken, body: {'password': secret});

  /// Deletes the account and everything it holds on the server.
  Future<void> deleteAccount(SupabaseSession s) =>
      _call('POST', '/rest/v1/rpc/delete_my_account', token: s.accessToken, body: const {});

  // ------------------------------------------------------------------- data

  Future<List<RemoteItem>> pull(SupabaseSession s, int afterRev, int limit) async {
    final json = await _call(
      'GET',
      '/rest/v1/sync_items',
      token: s.accessToken,
      query: {
        'select': 'id,modified_at,deleted,payload,rev',
        'rev': 'gt.$afterRev',
        'order': 'rev.asc',
        'limit': '$limit',
      },
    );
    return [for (final r in (json as List? ?? const [])) RemoteItem.fromJson((r as Map).cast<String, Object?>())];
  }

  Future<List<RemoteItem>> push(SupabaseSession s, List<RemoteItem> items) async {
    final json = await _call(
      'POST',
      '/rest/v1/rpc/sync_push',
      token: s.accessToken,
      body: {
        'items': [for (final i in items) i.toJson()],
      },
    );
    return [for (final r in (json as List? ?? const [])) RemoteItem.fromJson((r as Map).cast<String, Object?>())];
  }

  /// Removes everything synchronised (kept: the account).
  Future<void> wipe(SupabaseSession s) =>
      _call('DELETE', '/rest/v1/sync_items', token: s.accessToken, query: {'rev': 'gte.0'});
}

/// [SyncRemote] over [SupabaseApi], refreshing the session when needed.
class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this.api, this.session, {required this.onSession});

  final SupabaseApi api;
  SupabaseSession session;

  /// Called with each new session (to keep it).
  final void Function(SupabaseSession) onSession;

  Future<T> _authed<T>(Future<T> Function(SupabaseSession s) call) async {
    if (session.expiresSoon) await _refresh();
    try {
      return await call(session);
    } on SyncApiException catch (e) {
      if (e.status != 401) rethrow;
      await _refresh();
      return call(session);
    }
  }

  Future<void> _refresh() async {
    session = await api.refresh(session);
    onSession(session);
  }

  /// A valid session (refreshed if needed).
  Future<SupabaseSession> current() => _authed((s) async => s);

  /// Ends the session on the server. An access token that expired cannot
  /// sign itself out: it is renewed first, or the session stayed open there.
  Future<void> signOut() => _authed(api.signOut);

  @override
  Future<List<RemoteItem>> pull(int afterRev, {int limit = SyncEngine.pageSize}) =>
      _authed((s) => api.pull(s, afterRev, limit));

  @override
  Future<List<RemoteItem>> push(List<RemoteItem> items) => _authed((s) => api.push(s, items));
}
