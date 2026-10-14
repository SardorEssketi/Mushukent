import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';

import '../../support/fakes.dart';

const _network = MushukistanApiException(
  kind: ApiFailureKind.network,
  code: 'NETWORK_ERROR',
  message: 'Network request failed.',
);
const _unavailable = MushukistanApiException(
  kind: ApiFailureKind.server,
  code: 'SERVICE_UNAVAILABLE',
  message: 'Backend unavailable.',
  statusCode: 503,
);
const _unauthorized = MushukistanApiException(
  kind: ApiFailureKind.unauthorized,
  code: 'UNAUTHORIZED',
  message: 'Invalid or expired token.',
  statusCode: 401,
);

Map<String, Object?> _userJson(String id, String name) => {
      'id': id,
      'email': '$name@example.com',
      'name': name,
      'registered_at': '2026-07-01T10:00:00Z',
    };

Map<String, Object?> _sessionJson(String id, String name,
        {String access = 'new-access', String refresh = 'new-refresh'}) =>
    {
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'Bearer',
      'user': _userJson(id, name),
    };

/// Real repository + controller over a scriptable API and in-memory credential store: only the
/// network is faked, so the whole restore/refresh decision path is exercised.
class _Harness {
  _Harness({
    String? access = 'access-1',
    String? refresh = 'refresh-1',
    List<Duration> backoff = const [
      Duration(milliseconds: 5),
      Duration(milliseconds: 5),
      Duration(milliseconds: 5),
    ],
  }) : tokens = FakeAuthTokenStore(access, refresh) {
    api.setHandler('GET', 'users/me', (_) => _usersMe(this));
    api.setHandler('POST', 'auth/refresh', (_) => _refresh(this));
    final repository = MushukistanAuthRepository(
      apiClient: api,
      tokenStore: tokens,
    );
    this.repository = repository;
    controller = AuthController(
      repository,
      FakeGoogleIdentityTokenProvider(),
      reconnectBackoff: backoff,
    );
  }

  final api = FakeApiClient();
  final FakeAuthTokenStore tokens;
  late final AuthRepository repository;
  late final AuthController controller;

  /// What the fake server does next. Tests flip these to simulate outages and recovery.
  Object? meError;
  Object? refreshError;
  String meUserId = 'user-a';
  String meName = 'alice';

  int get meCalls => api.calls.where((c) => c.path == 'users/me').length;
  int get refreshCalls =>
      api.calls.where((c) => c.path == 'auth/refresh').length;

  static Object? _usersMe(_Harness h) {
    if (h.meError != null) throw h.meError!;
    return _userJson(h.meUserId, h.meName);
  }

  static Object? _refresh(_Harness h) {
    if (h.refreshError != null) throw h.refreshError!;
    return _sessionJson(h.meUserId, h.meName);
  }

  Future<void> pump([int ms = 40]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void dispose() => controller.dispose();
}

void main() {
  group('startup', () {
    test('valid session restores and stays authenticated', () async {
      final h = _Harness();
      await h.pump();
      expect(h.controller.state.phase, AuthPhase.authenticated);
      expect(h.controller.state.user?.id, 'user-a');
      h.dispose();
    });

    test('backend unavailable at startup keeps the session and credentials',
        () async {
      final h = _Harness()..meError = _network;
      // The restore started in the constructor already ran with meError unset; rerun.
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);

      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);
      expect(h.controller.state.hasUnconfirmedSession, isTrue);
      expect(h.controller.state.isAuthenticated, isFalse);
      expect(await h.tokens.read(), 'access-1');
      expect(await h.tokens.readRefreshToken(), 'refresh-1');
      h.dispose();
    });

    test('5xx responses are outages too, never a logout', () async {
      final h = _Harness();
      await h.pump();
      h.meError = _unavailable;
      await h.controller.restoreSession(force: true);
      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);
      expect(await h.tokens.readRefreshToken(), 'refresh-1');
      h.dispose();
    });

    test('no stored credentials is a plain guest', () async {
      final h = _Harness(access: null, refresh: null);
      await h.pump();
      expect(h.controller.state.phase, AuthPhase.unauthenticated);
      expect(h.meCalls, 0);
      h.dispose();
    });
  });

  group('token refresh', () {
    test('expired access token is refreshed and the user stays signed in',
        () async {
      final h = _Harness();
      await h.pump();
      var first = true;
      h.api.setHandler('GET', 'users/me', (_) {
        if (first) {
          first = false;
          throw _unauthorized;
        }
        return _userJson('user-a', 'alice');
      });
      await h.controller.restoreSession(force: true);

      expect(h.controller.state.phase, AuthPhase.authenticated);
      expect(await h.tokens.read(), 'new-access');
      expect(h.refreshCalls, 1);
      h.dispose();
    });

    test('network failure during refresh keeps credentials (no logout)',
        () async {
      final h = _Harness();
      await h.pump();
      h.meError = _unauthorized;
      h.refreshError = _network;
      await h.controller.restoreSession(force: true);

      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);
      expect(await h.tokens.readRefreshToken(), 'refresh-1');
      expect(await h.tokens.read(), 'access-1');
      h.dispose();
    });

    test('a 5xx during refresh keeps credentials', () async {
      final h = _Harness();
      await h.pump();
      h.meError = _unauthorized;
      h.refreshError = _unavailable;
      await h.controller.restoreSession(force: true);
      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);
      expect(await h.tokens.readRefreshToken(), 'refresh-1');
      h.dispose();
    });

    test('invalid refresh token is a confirmed logout and clears credentials',
        () async {
      final h = _Harness();
      await h.pump();
      h.meError = _unauthorized;
      h.refreshError = _unauthorized;
      await h.controller.restoreSession(force: true);

      expect(h.controller.state.phase, AuthPhase.unauthenticated);
      expect(h.controller.state.message, contains('expired'));
      expect(await h.tokens.read(), isNull);
      expect(await h.tokens.readRefreshToken(), isNull);
      h.dispose();
    });

    test('refresh is attempted once per restore: no refresh loop', () async {
      final h = _Harness();
      await h.pump();
      final before = h.refreshCalls;
      h.meError = _unauthorized;
      h.refreshError = _unauthorized;
      await h.controller.restoreSession(force: true);
      expect(h.refreshCalls - before, 1);
      h.dispose();
    });
  });

  group('recovery', () {
    test('automatic re-check restores the session when the backend returns',
        () async {
      final h = _Harness();
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);

      h.meError = null; // backend is back
      await h.pump(120);

      expect(h.controller.state.phase, AuthPhase.authenticated);
      expect(h.controller.state.user?.id, 'user-a');
      expect(await h.tokens.readRefreshToken(), 'refresh-1');
      h.dispose();
    });

    test('automatic retries are bounded: an outage does not become polling',
        () async {
      final h = _Harness(); // backoff has 3 entries
      await h.pump();
      h.meError = _network;
      final before = h.meCalls;
      await h.controller.restoreSession(force: true);
      await h.pump(250);

      // 1 forced attempt + exactly 3 automatic ones, then silence.
      expect(h.meCalls - before, 4);
      final settled = h.meCalls;
      await h.pump(250);
      expect(h.meCalls, settled);
      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);
      h.dispose();
    });

    test('manual retry starts a fresh round and recovers', () async {
      final h = _Harness();
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      await h.pump(250); // budget exhausted
      final exhausted = h.meCalls;

      h.meError = null;
      await h.controller.retrySession();
      expect(h.controller.state.phase, AuthPhase.authenticated);
      expect(h.meCalls, exhausted + 1);
      h.dispose();
    });

    test('repeated transient failures never lose the session', () async {
      final h = _Harness();
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      for (var i = 0; i < 15; i++) {
        await h.controller.retrySession();
        expect(h.controller.state.phase, AuthPhase.sessionUnavailable);
      }
      expect(await h.tokens.read(), 'access-1');
      expect(await h.tokens.readRefreshToken(), 'refresh-1');
      h.meError = null;
      await h.controller.retrySession();
      expect(h.controller.state.phase, AuthPhase.authenticated);
      h.dispose();
    });

    test('simultaneous retries coalesce into one request', () async {
      final h = _Harness();
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      await h.pump(250); // let automatic retries finish
      final before = h.meCalls;
      await Future.wait([
        for (var i = 0; i < 6; i++) h.controller.retrySession(),
      ]);
      expect(h.meCalls - before, 1);
      h.dispose();
    });

    test('retrySession is a no-op unless a session is unconfirmed', () async {
      final h = _Harness();
      await h.pump();
      final before = h.meCalls;
      await h.controller.retrySession();
      expect(h.meCalls, before);
      expect(h.controller.state.phase, AuthPhase.authenticated);
      h.dispose();
    });

    test('a later confirmed-invalid answer ends the session and clears it',
        () async {
      final h = _Harness();
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      h.meError = _unauthorized;
      h.refreshError = _unauthorized;
      await h.controller.retrySession();

      expect(h.controller.state.phase, AuthPhase.unauthenticated);
      expect(await h.tokens.readRefreshToken(), isNull);
      h.dispose();
    });
  });

  group('logout and account switching', () {
    test('explicit logout during an outage cancels reconnect attempts',
        () async {
      final h = _Harness(backoff: const [Duration(milliseconds: 30)]);
      await h.pump();
      h.api.setHandler('POST', 'auth/logout', (_) => null);
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      final before = h.meCalls;

      await h.controller.logout();
      await h.pump(120);

      expect(h.controller.state.phase, AuthPhase.unauthenticated);
      expect(h.meCalls, before, reason: 'no restore after logout');
      expect(await h.tokens.read(), isNull);
      expect(await h.tokens.readRefreshToken(), isNull);
      h.dispose();
    });

    test('signing in as another account during an outage replaces the session',
        () async {
      final h = _Harness(backoff: const [Duration(milliseconds: 30)]);
      await h.pump();
      h.meError = _network;
      await h.controller.restoreSession(force: true);
      expect(h.controller.state.phase, AuthPhase.sessionUnavailable);

      h.api.setHandler(
          'POST',
          'auth/login',
          (_) => _sessionJson('user-b', 'bob',
              access: 'bob-access', refresh: 'bob-refresh'));
      await h.controller.login(
        const AuthCredentials(email: 'bob@example.com', password: 'Pass12345'),
      );
      expect(h.controller.state.user?.id, 'user-b');
      final calls = h.meCalls;
      await h
          .pump(120); // a stale reconnect must not run or flip the account back
      expect(h.meCalls, calls);
      expect(h.controller.state.user?.id, 'user-b');
      expect(await h.tokens.read(), 'bob-access');
      h.dispose();
    });

    test('a slow restore for the old account cannot overwrite a new login',
        () async {
      final repo = FakeAuthRepository();
      final slow = Completer<SessionRestoreResult>();
      repo.restoreCompleter = slow;
      repo.loginResult = AuthSession(
        accessToken: 'bob-access',
        user: testUser(id: 'user-b', name: 'Bob'),
      );
      final controller =
          AuthController(repo, FakeGoogleIdentityTokenProvider());
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, AuthPhase.restoring);

      await controller.login(
        const AuthCredentials(email: 'bob@example.com', password: 'Pass12345'),
      );
      slow.complete(SessionRestoreSuccess(AuthSession.restored(
        accessToken: 'alice-access',
        user: testUser(id: 'user-a', name: 'Alice'),
      )));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(controller.state.user?.id, 'user-b');
      controller.dispose();
    });
  });

  group('state classification', () {
    test('only unauthenticated means signed out', () {
      expect(AuthState.sessionUnavailable(message: 'x').phase,
          AuthPhase.sessionUnavailable);
      expect(AuthState.sessionUnavailable(message: 'x').hasUnconfirmedSession,
          isTrue);
      expect(
          AuthState.sessionUnavailable(message: 'x').isAuthenticated, isFalse);
      expect(AuthState.unauthenticated().hasUnconfirmedSession, isFalse);
      expect(
          AuthState.authenticated(testUser()).hasUnconfirmedSession, isFalse);
      expect(AuthState.restoring().hasUnconfirmedSession, isFalse);
    });
  });
}
