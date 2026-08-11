import 'package:flutter_test/flutter_test.dart';
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
    expect(controller.state.message, 'Invalid email or password.');
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
