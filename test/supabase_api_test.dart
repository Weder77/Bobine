import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bobine/data/db.dart';
import 'package:bobine/data/repository.dart';
import 'package:bobine/data/settings.dart';
import 'package:bobine/sync/supabase_api.dart';
import 'package:bobine/sync/sync_engine.dart';
import 'package:bobine/sync/sync_service.dart';

/// A local stand-in for Supabase answering what each test sets.
class FakeSupabase {
  late HttpServer server;
  final requests = <String>[];
  final bodies = <String, Object?>{};
  (int, Object?) Function(HttpRequest r, Object? body)? handler;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final text = await utf8.decoder.bind(r).join();
      final body = text.isEmpty ? null : jsonDecode(text);
      requests.add('${r.method} ${r.uri.path}${r.uri.hasQuery ? '?${r.uri.query}' : ''}');
      bodies[r.uri.path] = body;
      expect(r.headers.value('apikey'), 'key');
      final (status, json) = handler!(r, body);
      r.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(json == null ? '' : jsonEncode(json));
      await r.response.close();
    });
  }

  SupabaseApi api() => SupabaseApi(url: 'http://127.0.0.1:${server.port}', apiKey: 'key');
}

Map<String, Object?> _session(String token) => {
  'access_token': token,
  'refresh_token': 'r-$token',
  'expires_in': 3600,
  'user': {'id': 'u1', 'email': 'moi@example.com'},
};

void main() {
  late FakeSupabase fake;
  setUp(() async {
    fake = FakeSupabase();
    await fake.start();
  });
  tearDown(() => fake.server.close(force: true));

  test('errors come out in French, network failures are told apart', () async {
    fake.handler = (r, _) =>
        (400, {'code': 400, 'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'});
    final api = fake.api();
    await expectLater(
      api.signIn('moi@example.com', 'x'),
      throwsA(isA<SyncApiException>().having((e) => e.message, 'message', 'E-mail ou mot de passe incorrect.')),
    );
    fake.handler = (r, _) => (409, {'code': '23503', 'message': 'insert or update violates foreign key constraint'});
    await expectLater(
      api.push(SupabaseSession.fromAuth(_session('t')), [
        const RemoteItem(id: 'aaaaaaaaaaaaaaaa', modifiedAt: 1, payload: 'p'),
      ]),
      throwsA(isA<SyncApiException>().having((e) => e.sessionLost, 'sessionLost', isTrue)),
    );
    fake.handler = (r, _) => (503, null);
    await expectLater(
      api.pull(SupabaseSession.fromAuth(_session('t')), 0, 10),
      throwsA(isA<SyncApiException>().having((e) => e.network, 'network', isTrue)),
    );
    await fake.server.close(force: true);
    await expectLater(
      api.signIn('moi@example.com', 'x'),
      throwsA(isA<SyncApiException>().having((e) => e.network, 'network', isTrue)),
    );
  });

  test('sign-up waits for the e-mail code, the password never leaves the device', () async {
    fake.handler = (r, body) => switch (r.uri.path) {
      '/auth/v1/signup' => (
        200,
        {
          'id': 'u1',
          'email': 'moi@example.com',
          'identities': [{}],
        },
      ),
      '/auth/v1/verify' => (200, _session('t1')),
      '/rest/v1/sync_items' => (200, <Object?>[]),
      '/rest/v1/rpc/sync_push' => (200, <Object?>[]),
      _ => (404, null),
    };
    final repo = Repository(openMemoryDatabase());
    final sync = SyncService(repo, AppSettings(repo), api: fake.api(), onChanges: (_) {});
    await sync.signUp(' Moi@Example.com ', 'mot de passe secret');
    expect(sync.status, SyncStatus.confirming);
    expect(sync.pendingEmail, 'moi@example.com');
    final sent = jsonEncode(fake.bodies['/auth/v1/signup']);
    expect(sent, isNot(contains('mot de passe secret')));

    await sync.confirm('123456');
    expect((fake.bodies['/auth/v1/verify'] as Map)['token'], '123456');
    await sync.syncNow();
    expect(sync.status, SyncStatus.idle);
    expect(sync.signedIn, isTrue);
    expect(fake.requests, contains(startsWith('GET /rest/v1/sync_items?select=id%2Cmodified_at')));
    expect(fake.requests, contains('POST /rest/v1/rpc/sync_push'));

    // Kept (encrypted on Windows) for the next start.
    final again = SyncService(repo, AppSettings(repo), api: fake.api(), onChanges: (_) {});
    expect(again.signedIn, isTrue);
    expect(again.email, 'moi@example.com');
    sync.dispose();
    again.dispose();
  });

  test('an address already registered is told to sign in; an expired session is refreshed', () async {
    fake.handler = (r, body) => switch (r.uri.path) {
      '/auth/v1/signup' => (200, {'id': 'u1', 'email': 'moi@example.com', 'identities': <Object?>[]}),
      '/auth/v1/token' => (200, _session('t2')),
      '/rest/v1/sync_items' => (r.headers.value('authorization') == 'Bearer t2' ? 200 : 401, <Object?>[]),
      _ => (404, null),
    };
    final api = fake.api();
    await expectLater(
      api.signUp('moi@example.com', 's'),
      throwsA(isA<SyncApiException>().having((e) => e.code, 'code', 'user_already_exists')),
    );
    SupabaseSession? kept;
    final remote = SupabaseRemote(api, SupabaseSession.fromAuth(_session('t1')), onSession: (s) => kept = s);
    expect(await remote.pull(0), isEmpty);
    expect(kept?.accessToken, 't2');
    expect(fake.requests, contains('POST /auth/v1/token?grant_type=refresh_token'));
  });

  test('only a refresh token the service no longer knows ends the session', () async {
    final api = fake.api();
    final s = SupabaseSession.fromAuth(_session('t1'));
    // Too many tries behind a shared address, a proxy in the way: later.
    for (final (status, body) in [
      (429, {'error_code': 'over_request_rate_limit', 'msg': 'Too many requests'}),
      (403, null),
      (401, {'msg': 'Unauthorized'}),
    ]) {
      fake.handler = (r, _) => (status, body);
      await expectLater(
        api.refresh(s),
        throwsA(
          isA<SyncApiException>()
              .having((e) => e.sessionLost, 'sessionLost', isFalse)
              .having((e) => e.network, 'network', isTrue),
        ),
        reason: '$status',
      );
    }
    fake.handler = (r, _) => (400, {'error_code': 'refresh_token_not_found', 'msg': 'Invalid Refresh Token'});
    await expectLater(
      api.refresh(s),
      throwsA(isA<SyncApiException>().having((e) => e.sessionLost, 'sessionLost', isTrue)),
    );
  });

  group('signing out', () {
    (int, Object?) account(HttpRequest r, Object? body) => switch (r.uri.path) {
      '/auth/v1/token' => (200, _session(r.uri.queryParameters['grant_type'] == 'password' ? 't1' : 't2')),
      '/auth/v1/logout' => (204, null),
      '/rest/v1/sync_items' => (200, <Object?>[]),
      '/rest/v1/rpc/sync_push' => (200, <Object?>[]),
      _ => (404, null),
    };

    test('ends this session, not those of the other devices, and keeps nothing here', () async {
      fake.handler = account;
      final repo = Repository(openMemoryDatabase());
      final sync = SyncService(repo, AppSettings(repo), api: fake.api(), onChanges: (_) {});
      addTearDown(sync.dispose);
      await sync.signIn('moi@example.com', 'mot de passe secret');
      await sync.syncNow();
      expect(repo.kvGet(SyncEngine.cursorKey), isNotNull);
      // The password lets a forgotten parental code be changed, checked here.
      expect(await sync.checkPassword('mot de passe secret'), isTrue);
      expect(await sync.checkPassword('autre chose'), isFalse);

      await sync.signOut();
      expect(fake.requests.last, 'POST /auth/v1/logout?scope=local');
      expect(sync.signedIn, isFalse);
      expect(await sync.checkPassword('mot de passe secret'), isFalse);
      expect(sync.status, SyncStatus.signedOut);
      for (final key in ['sync.session', 'sync.keys', 'sync.last', SyncEngine.cursorKey]) {
        expect(repo.kvGet(key), isNull, reason: key);
      }
    });

    test('a token that expired is renewed first, or the session stayed open on the server', () async {
      final seen = <String?>[];
      fake.handler = (r, body) {
        if (r.uri.path != '/auth/v1/logout') return account(r, body);
        seen.add(r.headers.value('authorization'));
        return r.headers.value('authorization') == 'Bearer t2' ? (204, null) : (401, {'msg': 'JWT expired'});
      };
      final expired = SupabaseSession(
        accessToken: 't1',
        refreshToken: 'r-t1',
        expiresAt: DateTime.now().subtract(const Duration(hours: 3)),
        userId: 'u1',
        email: 'moi@example.com',
      );
      await SupabaseRemote(fake.api(), expired, onSession: (_) {}).signOut();
      expect(seen, ['Bearer t2']);

      // The device's clock says "still valid" but the server disagrees.
      seen.clear();
      final stale = SupabaseSession(
        accessToken: 't1',
        refreshToken: 'r-t1',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        userId: 'u1',
        email: 'moi@example.com',
      );
      await SupabaseRemote(fake.api(), stale, onSession: (_) {}).signOut();
      expect(seen, ['Bearer t1', 'Bearer t2']);
    });

    test('while a synchronisation is on the network: nothing of it is written back', () async {
      final repo = Repository(openMemoryDatabase());
      late SyncService sync;
      var leaveDuringPull = false;
      fake.handler = (r, body) {
        if (r.uri.path == '/rest/v1/sync_items' && leaveDuringPull) {
          leaveDuringPull = false;
          unawaited(sync.signOut());
        }
        return account(r, body);
      };
      sync = SyncService(repo, AppSettings(repo), api: fake.api(), onChanges: (_) {});
      addTearDown(sync.dispose);
      await sync.signIn('moi@example.com', 'mot de passe secret');
      await sync.syncNow();
      expect(repo.kvGet(SyncEngine.cursorKey), isNotNull);

      leaveDuringPull = true;
      await sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sync.signedIn, isFalse);
      expect(sync.status, SyncStatus.signedOut);
      // The next account must be read from its beginning.
      expect(repo.kvGet(SyncEngine.cursorKey), isNull);
      expect(repo.kvGet('sync.last'), isNull);
      expect(sync.lastSync, isNull);
      expect(sync.message, isNull);
    });
  });
}
