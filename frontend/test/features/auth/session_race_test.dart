import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';

import '../../support/fakes.dart';

Map<String, Object?> session(
        String access, String refresh, MushukistanUser user) =>
    {
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'Bearer',
      'expires_in': 3600,
      'user': user.toJson(),
    };

void main() {
  test('refresh completing after logout cannot restore credentials', () async {
    final api = FakeApiClient();
    final store =
        GuardedAuthTokenStore(FakeAuthTokenStore('access-a', 'refresh-a'));
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<Object?>();
    final logoutStarted = Completer<void>();
    final logoutResponse = Completer<Object?>();
    api.setHandler('POST', 'auth/refresh', (_) {
      refreshStarted.complete();
      return refreshResponse.future;
    });
    api.setHandler('POST', 'auth/logout', (call) {
      expect(call.body, {'refresh_token': 'refresh-a'});
      expect(call.bearerToken, 'access-a');
      logoutStarted.complete();
      return logoutResponse.future;
    });
    final repo = MushukistanAuthRepository(apiClient: api, tokenStore: store);
    final refresh = repo.refreshSession();
    await refreshStarted.future;
    final logout = repo.logout();
    await logoutStarted.future;
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(await repo.restoreSession(), isA<SessionRestoreMissing>());
    refreshResponse.complete(session('new-access-a', 'refresh-a', testUser()));
    await expectLater(refresh, throwsA(isA<MushukistanApiException>()));
    logoutResponse.complete(null);
    await logout;
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect((await repo.restoreSession()), isA<SessionRestoreMissing>());
  });

  test('Google A, B, then A switch without retaining the previous session',
      () async {
    final api = FakeApiClient();
    final store = GuardedAuthTokenStore(FakeAuthTokenStore());
    api.setHandler('POST', 'auth/google', (call) {
      final token = (call.body as Map)['id_token'];
      final isA = token == 'google-a';
      return session(
          isA ? 'access-a' : 'access-b',
          isA ? 'refresh-a' : 'refresh-b',
          testUser(
              id: isA ? 'user-a' : 'user-b',
              email: isA ? 'a@gmail.com' : 'b@gmail.com'));
    });
    api.setHandler('POST', 'auth/logout', (_) => null);
    final repo = MushukistanAuthRepository(apiClient: api, tokenStore: store);
    for (final token in ['google-a', 'google-b', 'google-a']) {
      final result = await repo.loginWithGoogleIdToken(token);
      expect(await store.read(), result.accessToken);
      expect(await store.readRefreshToken(), result.refreshToken);
      await repo.logout();
      expect(await store.read(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(await repo.restoreSession(), isA<SessionRestoreMissing>());
    }
    expect(api.calls.where((call) => call.path == 'auth/google'), hasLength(3));
  });

  test('repeated logout and failed revocation still clear local credentials',
      () async {
    final api = FakeApiClient();
    final store =
        GuardedAuthTokenStore(FakeAuthTokenStore('access-a', 'refresh-a'));
    api.setHandler('POST', 'auth/logout', (_) {
      throw const MushukistanApiException(
          kind: ApiFailureKind.network,
          code: 'NETWORK_ERROR',
          message: 'Offline');
    });
    final repo = MushukistanAuthRepository(apiClient: api, tokenStore: store);
    await Future.wait([repo.logout(), repo.logout()]);
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('expired access during logout refreshes only for server revocation',
      () async {
    final api = FakeApiClient();
    final store = GuardedAuthTokenStore(
        FakeAuthTokenStore('expired-access', 'refresh-a'));
    var logoutCalls = 0;
    api.setHandler('POST', 'auth/logout', (call) {
      logoutCalls++;
      expect(call.authenticated, isFalse);
      expect(call.bearerToken,
          logoutCalls == 1 ? 'expired-access' : 'renewed-access');
      if (logoutCalls == 1) {
        throw const MushukistanApiException(
            kind: ApiFailureKind.unauthorized,
            code: 'UNAUTHORIZED',
            message: 'Access expired');
      }
      return null;
    });
    api.setHandler('POST', 'auth/refresh',
        (_) => session('renewed-access', 'refresh-a', testUser()));
    final repo = MushukistanAuthRepository(apiClient: api, tokenStore: store);
    await repo.logout();
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
    expect(await repo.restoreSession(), isA<SessionRestoreMissing>());
    expect(logoutCalls, 2);
  });
}
