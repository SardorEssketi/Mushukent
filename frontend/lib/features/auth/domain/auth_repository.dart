import 'auth_models.dart';

sealed class SessionRestoreResult {
  const SessionRestoreResult();
}

final class SessionRestoreMissing extends SessionRestoreResult {
  const SessionRestoreMissing();
}

final class SessionRestoreInvalid extends SessionRestoreResult {
  const SessionRestoreInvalid({
    required this.message,
  });

  final String message;
}

final class SessionRestoreFailure extends SessionRestoreResult {
  const SessionRestoreFailure({
    required this.message,
    this.retryable = true,
  });

  final String message;
  final bool retryable;
}

final class SessionRestoreSuccess extends SessionRestoreResult {
  const SessionRestoreSuccess(this.session);

  final AuthSession session;
}

abstract interface class AuthRepository {
  Future<VerificationRequirement> register(RegisterCredentials credentials);
  Future<AuthSession> login(AuthCredentials credentials);
  Future<AuthSession> loginWithGoogleIdToken(
    String idToken, {
    bool acceptTerms = false,
    bool acceptPrivacy = false,
  });
  Future<VerificationRequirement> resendVerification(String email);
  Future<void> verifyEmail(String token);
  Future<MushukistanUser> fetchCurrentUser();
  Future<SessionRestoreResult> restoreSession();
  Future<void> logout();
}
