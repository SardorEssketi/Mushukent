import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

class MushukistanAuthRepository implements AuthRepository {
  MushukistanAuthRepository({
    required MushukistanApiClient apiClient,
    required AuthTokenStore tokenStore,
  })  : _apiClient = apiClient,
        _tokenStore = tokenStore;

  final MushukistanApiClient _apiClient;
  final AuthTokenStore _tokenStore;

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    final session = await _apiClient.postJson<AuthSession>(
      'auth/login',
      authenticated: false,
      body: credentials.toJson(),
      decoder: AuthSession.fromJson,
    );
    await _tokenStore.write(session.accessToken);
    return session;
  }

  @override
  Future<AuthSession> loginWithGoogleIdToken(
    String idToken, {
    bool acceptTerms = false,
    bool acceptPrivacy = false,
  }) async {
    final session = await _apiClient.postJson<AuthSession>(
      'auth/google',
      authenticated: false,
      body: <String, Object?>{
        'id_token': idToken,
        'accept_terms': acceptTerms,
        'accept_privacy': acceptPrivacy,
      },
      decoder: AuthSession.fromJson,
    );
    await _tokenStore.write(session.accessToken);
    return session;
  }

  @override
  Future<VerificationRequirement> register(
      RegisterCredentials credentials) async {
    return _apiClient.postJson<VerificationRequirement>(
      'auth/register',
      authenticated: false,
      body: credentials.toJson(),
      decoder: VerificationRequirement.fromJson,
    );
  }

  @override
  Future<VerificationRequirement> resendVerification(String email) {
    return _apiClient.postJson<VerificationRequirement>(
      'auth/resend-verification',
      authenticated: false,
      body: <String, Object?>{'email': email},
      decoder: VerificationRequirement.fromJson,
    );
  }

  @override
  Future<void> verifyEmail(String token) async {
    await _apiClient.postJson<Object?>(
      'auth/verify-email',
      authenticated: false,
      body: <String, Object?>{'token': token},
      decoder: (_) => null,
    );
  }

  @override
  Future<MushukistanUser> fetchCurrentUser() async {
    return _apiClient.get<MushukistanUser>(
      'users/me',
      decoder: MushukistanUser.fromJson,
    );
  }

  @override
  Future<SessionRestoreResult> restoreSession() async {
    final token = await _tokenStore.read();
    if (token == null || token.trim().isEmpty) {
      return const SessionRestoreMissing();
    }

    try {
      final user = await fetchCurrentUser();
      return SessionRestoreSuccess(
        AuthSession.restored(accessToken: token, user: user),
      );
    } on MushukistanApiException catch (error) {
      if (error.isSessionInvalid) {
        await _tokenStore.delete();
        return SessionRestoreInvalid(message: _restoreInvalidMessage(error));
      }
      return SessionRestoreFailure(
        message: error.userMessage,
        retryable: error.isRetryable,
      );
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _apiClient.delete('auth/logout');
    } catch (_) {
      // Client-side logout must still succeed locally.
    } finally {
      await _tokenStore.delete();
    }
  }

  String _restoreInvalidMessage(MushukistanApiException error) {
    if (error.code == 'ACCOUNT_DISABLED') {
      return 'Your account is disabled.';
    }
    return 'Your session expired. Please sign in again.';
  }
}
