import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/features/auth/application/auth_controller.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/google_sign_in_service.dart';

import '../../support/fakes.dart';

Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _DelayedGoogleIdentityTokenProvider
    implements GoogleIdentityTokenProvider {
  final first = Completer<String>();
  int calls = 0;

  @override
  Future<String> authenticate() {
    calls += 1;
    return calls == 1 ? first.future : Future.value('test-id-token');
  }
}

void main() {
  test('startup without token becomes unauthenticated', () async {
    final controller = AuthController(
      FakeAuthRepository(restoreResult: const SessionRestoreMissing()),
      FakeGoogleIdentityTokenProvider(),
    );

    await settle();

    expect(controller.state.phase, AuthPhase.unauthenticated);
  });

  test('startup with a valid token becomes authenticated', () async {
    final controller = AuthController(
      FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(
          AuthSession.restored(
            accessToken: 'token-123',
            user: testUser(),
          ),
        ),
      ),
      FakeGoogleIdentityTokenProvider(),
    );

    await settle();

    expect(controller.state.phase, AuthPhase.authenticated);
    expect(controller.state.user?.email, 'user@example.com');
  });

  test('startup with invalid token clears to unauthenticated', () async {
    final controller = AuthController(
      FakeAuthRepository(
        restoreResult: const SessionRestoreInvalid(
          message: 'Session expired. Please sign in again.',
        ),
      ),
      FakeGoogleIdentityTokenProvider(),
    );

    await settle();

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.message, contains('expired'));
  });

  test('startup network failure remains distinguishable', () async {
    final repo = FakeAuthRepository();
    repo.restoreResult = const SessionRestoreFailure(
      message: 'Network request failed.',
      retryable: true,
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();

    expect(controller.state.phase, AuthPhase.failure);
    expect(controller.state.retryable, isTrue);
  });

  test('startup restore exception becomes retryable failure', () async {
    final repo = FakeAuthRepository()..restoreError = StateError('boom');
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();

    expect(controller.state.phase, AuthPhase.failure);
    expect(controller.state.message, 'Session check failed.');
    expect(controller.state.retryable, isTrue);
  });

  test('startup restore timeout does not stay restoring forever', () async {
    final repo = FakeAuthRepository()
      ..restoreCompleter = Completer<SessionRestoreResult>();
    final controller = AuthController(
      repo,
      FakeGoogleIdentityTokenProvider(),
      restoreTimeout: const Duration(milliseconds: 1),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.state.phase, AuthPhase.failure);
    expect(controller.state.message, contains('timed out'));
    expect(controller.state.retryable, isTrue);
  });

  test('login success transitions to authenticated', () async {
    final repo = FakeAuthRepository(
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(),
      ),
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();
    await controller.login(
      const AuthCredentials(email: 'user@example.com', password: 'password1'),
    );

    expect(controller.state.phase, AuthPhase.authenticated);
    expect(repo.loginCalls, 1);
  });

  test('login failure returns to unauthenticated with a message', () async {
    final repo = FakeAuthRepository();
    repo.loginError = const MushukistanApiException(
      kind: ApiFailureKind.unauthorized,
      code: 'INVALID_CREDENTIALS',
      message: 'Invalid email or password.',
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();

    await expectLater(
      controller.login(
        const AuthCredentials(email: 'user@example.com', password: 'wrongpass'),
      ),
      throwsA(isA<MushukistanApiException>()),
    );

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.message, 'Email or password is incorrect.');
  });

  test('logout clears the authenticated state', () async {
    final repo = FakeAuthRepository(
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(),
      ),
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();
    await controller.login(
      const AuthCredentials(email: 'user@example.com', password: 'password1'),
    );
    await controller.logout();

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(repo.logoutCalled, isTrue);
  });

  test('late startup restore cannot authenticate after logout', () async {
    final pending = Completer<SessionRestoreResult>();
    final repo = FakeAuthRepository()..restoreCompleter = pending;
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());
    await Future<void>.delayed(Duration.zero);
    await controller.logout();
    pending.complete(SessionRestoreSuccess(AuthSession.restored(
      accessToken: 'old-access',
      user: testUser(),
    )));
    await settle();
    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.user, isNull);
  });

  test('late password login cannot authenticate after logout', () async {
    final pending = Completer<AuthSession>();
    final repo = FakeAuthRepository()..loginCompleter = pending;
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());
    await settle();
    final login = controller.login(const AuthCredentials(
        email: 'user@example.com', password: 'password1'));
    await controller.logout();
    pending.complete(
        AuthSession.restored(accessToken: 'old-access', user: testUser()));
    await login;
    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.user, isNull);
  });

  test('revoked refresh discovered by API clears authenticated UI state',
      () async {
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    await store.writeTokens(accessToken: 'access-a', refreshToken: 'refresh-a');
    final controller = AuthController(
      FakeAuthRepository(
        restoreResult: SessionRestoreSuccess(AuthSession.restored(
          accessToken: 'access-a',
          user: testUser(),
        )),
      ),
      FakeGoogleIdentityTokenProvider(),
      tokenStore: store,
    );
    await settle();
    expect(controller.state.isAuthenticated, isTrue);
    await store.deleteIfRevision(store.revision);
    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.user, isNull);
  });

  test('register transitions to verification required', () async {
    final repo = FakeAuthRepository(
      registerResult: const VerificationRequirement(
        email: 'user@example.com',
        devVerificationToken: 'dev-token',
      ),
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();
    await controller.register(
      const RegisterCredentials(
        name: 'Test User',
        email: 'user@example.com',
        password: 'password1',
        preferredLanguage: 'en',
        acceptTerms: true,
        acceptPrivacy: true,
      ),
    );

    expect(controller.state.phase, AuthPhase.verificationRequired);
    expect(controller.state.pendingVerificationEmail, 'user@example.com');
    expect(controller.state.devVerificationToken, 'dev-token');
  });

  test('unverified login transitions to verification required', () async {
    final repo = FakeAuthRepository();
    repo.loginError = const MushukistanApiException(
      kind: ApiFailureKind.unauthorized,
      code: 'EMAIL_NOT_VERIFIED',
      message: 'Please confirm your email before signing in.',
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();

    await expectLater(
      controller.login(
        const AuthCredentials(email: 'user@example.com', password: 'password1'),
      ),
      throwsA(isA<MushukistanApiException>()),
    );

    expect(controller.state.phase, AuthPhase.verificationRequired);
    expect(controller.state.pendingVerificationEmail, 'user@example.com');
  });

  test('return to login clears pending verification state', () async {
    final repo = FakeAuthRepository();
    repo.loginError = const MushukistanApiException(
      kind: ApiFailureKind.unauthorized,
      code: 'EMAIL_NOT_VERIFIED',
      message: 'Please confirm your email before signing in.',
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();

    await expectLater(
      controller.login(
        const AuthCredentials(email: 'user@example.com', password: 'password1'),
      ),
      throwsA(isA<MushukistanApiException>()),
    );

    controller.returnToLogin();

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.pendingVerificationEmail, isNull);
  });

  test('verify email failure returns to unauthenticated with message',
      () async {
    final repo = FakeAuthRepository();
    repo.verifyEmailError = const MushukistanApiException(
      kind: ApiFailureKind.unauthorized,
      code: 'INVALID_VERIFICATION_TOKEN',
      message: 'Verification link is invalid or expired.',
    );
    final controller = AuthController(repo, FakeGoogleIdentityTokenProvider());

    await settle();

    await expectLater(
      controller.verifyEmail('bad-token'),
      throwsA(isA<MushukistanApiException>()),
    );

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(
        controller.state.message, 'Verification link is invalid or expired.');
  });

  test('google login success transitions to authenticated', () async {
    final repo = FakeAuthRepository(
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(email: 'google-user@example.com'),
      ),
    );
    final google = FakeGoogleIdentityTokenProvider(idToken: 'google-id-token');
    final controller = AuthController(repo, google);

    await settle();
    await controller.loginWithGoogle();

    expect(controller.state.phase, AuthPhase.authenticated);
    expect(repo.lastGoogleIdToken, 'google-id-token');
    expect(google.calls, 1);
  });

  test('repeated Google taps start once and login works after logout',
      () async {
    final repo = FakeAuthRepository(
      loginResult: AuthSession.restored(
        accessToken: 'test-access-token',
        user: testUser(email: 'google-user@example.com'),
      ),
    );
    final google = _DelayedGoogleIdentityTokenProvider();
    final controller = AuthController(repo, google);
    await settle();

    final first = controller.loginWithGoogle();
    await controller.loginWithGoogle();
    expect(google.calls, 1);
    google.first.complete('test-id-token');
    await first;
    expect(controller.state.phase, AuthPhase.authenticated);

    await controller.logout();
    expect(controller.state.phase, AuthPhase.unauthenticated);
    await controller.loginWithGoogle();
    expect(google.calls, 2);
    expect(controller.state.phase, AuthPhase.authenticated);
  });

  test('google consent error is shown without retaining the ID token',
      () async {
    final repo = FakeAuthRepository(
      loginResult: AuthSession.restored(
        accessToken: 'token-123',
        user: testUser(email: 'google-user@example.com'),
      ),
    );
    repo.loginError = const MushukistanApiException(
      kind: ApiFailureKind.validation,
      code: 'LEGAL_ACCEPTANCE_REQUIRED',
      message: 'Terms of Service and Privacy Policy acceptance is required.',
    );
    final google = FakeGoogleIdentityTokenProvider(idToken: 'google-id-token');
    final controller = AuthController(repo, google);

    await settle();

    await expectLater(
      controller.loginWithGoogle,
      throwsA(isA<MushukistanApiException>()),
    );

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(controller.state.message,
        'Review the Terms of Service and Privacy Policy to continue.');
    expect(google.calls, 1);
  });

  test('google login configuration failure returns to unauthenticated',
      () async {
    final repo = FakeAuthRepository();
    final google = FakeGoogleIdentityTokenProvider(
      error: const GoogleSignInFlowException(
        'Google sign-in is not configured for this build.',
      ),
    );
    final controller = AuthController(repo, google);

    await settle();

    await expectLater(
      controller.loginWithGoogle,
      throwsA(isA<GoogleSignInFlowException>()),
    );

    expect(controller.state.phase, AuthPhase.unauthenticated);
    expect(
      controller.state.message,
      'Google sign-in is not configured for this build.',
    );
  });
}
