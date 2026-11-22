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
  /// [preferredLanguage] is the language shown at sign-in; the server applies
  /// it only when this sign-in creates a new account.
  Future<AuthSession> loginWithGoogleIdToken(String idToken,
      {String? password, String? preferredLanguage});
  Future<VerificationRequirement> resendVerification(String email);
  Future<void> verifyEmail(String token);
  Future<MushukistanUser> fetchCurrentUser();

  /// Records the user's explicit acceptance of the named (current) document versions.
  Future<MushukistanUser> acceptLegal({
    required String termsVersion,
    required String privacyVersion,
  });
  Future<AuthSession> refreshSession();
  Future<SessionRestoreResult> restoreSession();
  Future<void> logout();
}
