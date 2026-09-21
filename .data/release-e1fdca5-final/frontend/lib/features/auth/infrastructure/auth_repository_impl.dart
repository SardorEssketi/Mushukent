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
    await _persistSession(session);
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
    await _persistSession(session);
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
  Future<AuthSession> refreshSession() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Invalid or expired session.',
      );
    }
    final session = await _apiClient.postJson<AuthSession>(
      'auth/refresh',
      authenticated: false,
      body: <String, Object?>{'refresh_token': refreshToken},
      decoder: AuthSession.fromJson,
    );
    await _persistSession(session);
    return session;
  }

  @override
  Future<SessionRestoreResult> restoreSession() async {
    final token = await _tokenStore.read();
    final refreshToken = await _tokenStore.readRefreshToken();
    if ((token == null || token.trim().isEmpty) &&
        (refreshToken == null || refreshToken.trim().isEmpty)) {
      return const SessionRestoreMissing();
    }

    try {
      if (token != null && token.trim().isNotEmpty) {
        final user = await fetchCurrentUser();
        final restoredToken = await _tokenStore.read();
        return SessionRestoreSuccess(
          AuthSession.restored(accessToken: restoredToken ?? token, user: user),
        );
      }
      final session = await refreshSession();
      return SessionRestoreSuccess(session);
    } on MushukistanApiException catch (error) {
      if (error.isSessionInvalid) {
        if (refreshToken != null && refreshToken.trim().isNotEmpty) {
          try {
            final session = await refreshSession();
            return SessionRestoreSuccess(session);
          } on MushukistanApiException catch (refreshError) {
            if (refreshError.isSessionInvalid) {
              await _tokenStore.delete();
              return SessionRestoreInvalid(
                message: _restoreInvalidMessage(refreshError),
              );
            }
            return SessionRestoreFailure(
              message: refreshError.userMessage,
              retryable: refreshError.isRetryable,
            );
          }
        } else {
          await _tokenStore.delete();
          return SessionRestoreInvalid(message: _restoreInvalidMessage(error));
        }
      }
      return SessionRestoreFailure(
        message: error.userMessage,
        retryable: error.isRetryable,
      );
    }
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    try {
      await _apiClient.postJson<Object?>(
        'auth/logout',
        body: refreshToken == null
            ? null
            : <String, Object?>{'refresh_token': refreshToken},
        decoder: (_) => null,
      );
    } catch (_) {
      // Client-side logout must still succeed locally.
    } finally {
      await _tokenStore.delete();
    }
  }

  Future<void> _persistSession(AuthSession session) {
    return _tokenStore.writeTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
  }

  String _restoreInvalidMessage(MushukistanApiException error) {
    if (error.code == 'ACCOUNT_DISABLED') {
      return 'Your account is disabled.';
    }
    return 'Your session expired. Please sign in again.';
  }
}
