import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/auth_repository_impl.dart';

import '../../support/fakes.dart';

void main() {
  test('login success persists the token and returns a session', () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore();
    apiClient.setHandler('POST', 'auth/login', (call) {
      expect(call.authenticated, isFalse);
      expect(call.body, isA<Map>());
      return <String, Object?>{
        'access_token': 'token-123',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'user': testUser().toJson(),
      };
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final session = await repository.login(
      const AuthCredentials(email: 'user@example.com', password: 'password1'),
    );

    expect(session.accessToken, 'token-123');
    expect(await tokenStore.read(), 'token-123');
    expect(apiClient.calls.single.path, 'auth/login');
  });

  test('login failure does not persist a token', () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore();
    apiClient.setHandler('POST', 'auth/login', (call) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password.',
      );
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );

    await expectLater(
      () => repository.login(
        const AuthCredentials(email: 'user@example.com', password: 'badpass1'),
      ),
      throwsA(isA<MushukistanApiException>()),
    );
    expect(await tokenStore.read(), isNull);
  });

  test('google login success persists the token and returns a session',
      () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore();
    apiClient.setHandler('POST', 'auth/google', (call) {
      expect(call.authenticated, isFalse);
      expect(call.body, <String, Object?>{
        'id_token': 'google-id-token',
        'accept_terms': false,
        'accept_privacy': false,
      });
      return <String, Object?>{
        'access_token': 'token-123',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'user': testUser(email: 'google-user@example.com').toJson(),
      };
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final session = await repository.loginWithGoogleIdToken('google-id-token');

    expect(session.user.email, 'google-user@example.com');
    expect(await tokenStore.read(), 'token-123');
  });

  test('session restoration returns the current user when the token is valid',
      () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore('token-123');
    apiClient.setHandler('GET', 'users/me', (call) {
      expect(call.authenticated, isTrue);
      return testUser().toJson();
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final result = await repository.restoreSession();

    expect(result, isA<SessionRestoreSuccess>());
    final session = (result as SessionRestoreSuccess).session;
    expect(session.accessToken, 'token-123');
    expect(session.user.email, 'user@example.com');
    expect(await tokenStore.read(), 'token-123');
  });

  test('invalid tokens are cleared during restoration', () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore('token-123');
    apiClient.setHandler('GET', 'users/me', (call) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'UNAUTHORIZED',
        message: 'Missing or invalid Authorization header.',
      );
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final result = await repository.restoreSession();

    expect(result, isA<SessionRestoreInvalid>());
    expect(await tokenStore.read(), isNull);
  });

  test('network failures stay distinguishable from invalid sessions', () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore('token-123');
    apiClient.setHandler('GET', 'users/me', (call) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.network,
        code: 'NETWORK_ERROR',
        message: 'Network request failed.',
      );
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final result = await repository.restoreSession();

    expect(result, isA<SessionRestoreFailure>());
    expect(await tokenStore.read(), 'token-123');
  });

  test('logout clears the local token', () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore('token-123');
    apiClient.setHandler('DELETE', 'auth/logout', (call) => null);

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    await repository.logout();

    expect(await tokenStore.read(), isNull);
    expect(apiClient.calls.single.method, 'DELETE');
  });

  test('register returns verification requirement instead of session',
      () async {
    final apiClient = FakeApiClient();
    final tokenStore = FakeAuthTokenStore();
    apiClient.setHandler('POST', 'auth/register', (call) {
      expect(call.authenticated, isFalse);
      return <String, Object?>{
        'email': 'user@example.com',
        'verification_required': true,
        'dev_verification_token': 'dev-token',
      };
    });

    final repository = MushukistanAuthRepository(
      apiClient: apiClient,
      tokenStore: tokenStore,
    );
    final result = await repository.register(
      const RegisterCredentials(
        email: 'user@example.com',
        password: 'password1',
        preferredLanguage: 'en',
        acceptTerms: true,
        acceptPrivacy: true,
      ),
    );

    expect(result.email, 'user@example.com');
    expect(result.devVerificationToken, 'dev-token');
    expect(await tokenStore.read(), isNull);
  });
}
