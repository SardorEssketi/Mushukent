import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../../core/storage/token_store.dart';
import '../../notifications/application/notification_push.dart';
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
    final revision = _sessionRevision;
    final session = await _apiClient.postJson<AuthSession>(
      'auth/login',
      authenticated: false,
      body: credentials.toJson(),
      decoder: AuthSession.fromJson,
    );
    await _persistSession(session, revision);
    return session;
  }

  @override
  Future<AuthSession> loginWithGoogleIdToken(String idToken,
      {String? password}) async {
    final revision = _sessionRevision;
    final session = await _apiClient.postJson<AuthSession>(
      'auth/google',
      authenticated: false,
      body: <String, Object?>{
        'id_token': idToken,
        if (password != null) 'password': password,
        // The linked agreement is shown immediately beside the Google CTA.
        // The server still records only the current legal document versions.
        'accept_terms': true,
        'accept_privacy': true,
      },
      decoder: AuthSession.fromJson,
    );
    await _persistSession(session, revision);
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
    final revision = _sessionRevision;
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
    await _persistSession(session, revision);
    return session;
  }

  @override
  Future<SessionRestoreResult> restoreSession() async {
    final revision = _sessionRevision;
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
      if (error.code == 'SESSION_CHANGED') {
        return const SessionRestoreMissing();
      }
      if (error.isSessionInvalid) {
        if (refreshToken != null && refreshToken.trim().isNotEmpty) {
          try {
            final session = await refreshSession();
            return SessionRestoreSuccess(session);
          } on MushukistanApiException catch (refreshError) {
            if (refreshError.code == 'SESSION_CHANGED') {
              return const SessionRestoreMissing();
            }
            if (refreshError.isSessionInvalid) {
              await _deleteIfRevision(revision);
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
          await _deleteIfRevision(revision);
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
    final guarded = _tokenStore is GuardedAuthTokenStore ? _tokenStore : null;
    guarded?.invalidatePendingWrites();
    String? accessToken;
    String? refreshToken;
    try {
      accessToken = await _tokenStore.read();
      refreshToken = await _tokenStore.readRefreshToken();
    } catch (_) {
      // Clear what is available even if a platform credential read fails.
    }
    if (accessToken != null) {
      try {
        final pushToken = await AndroidPushService.tokenForLogout();
        if (pushToken != null) {
          await _apiClient.postJson<void>(
            'notifications/devices/unregister',
            bearerToken: accessToken,
            body: {'platform': 'android', 'token': pushToken},
            decoder: (_) {},
          );
        }
      } catch (_) {
        // Account switching rebinds the token and drops old queued jobs.
      }
    }
    try {
      await AndroidPushService.clearRegisteredToken();
    } catch (_) {
      // A secure-storage failure must not block account logout.
    }
    await _tokenStore.delete();
    if (accessToken == null && refreshToken == null) return;
    try {
      if (accessToken != null) {
        await _revokeSession(accessToken, refreshToken);
        return;
      }
    } on MushukistanApiException catch (error) {
      if (!error.isSessionInvalid || refreshToken == null) return;
    } catch (_) {
      return;
    }
    if (refreshToken == null) return;
    try {
      final renewed = await _apiClient.postJson<AuthSession>(
        'auth/refresh',
        authenticated: false,
        body: <String, Object?>{'refresh_token': refreshToken},
        decoder: AuthSession.fromJson,
      );
      await _revokeSession(renewed.accessToken, refreshToken);
    } catch (_) {
      // Local credentials have already been removed. An unreachable server
      // cannot confirm revocation; an invalid refresh token is unusable.
    }
  }

  Future<void> _revokeSession(String accessToken, String? refreshToken) {
    return _apiClient.postJson<Object?>(
      'auth/logout',
      authenticated: false,
      bearerToken: accessToken,
      body: refreshToken == null
          ? null
          : <String, Object?>{'refresh_token': refreshToken},
      decoder: (_) => null,
    );
  }

  int? get _sessionRevision =>
      _tokenStore is GuardedAuthTokenStore ? _tokenStore.revision : null;

  Future<void> _deleteIfRevision(int? revision) async {
    if (_tokenStore is GuardedAuthTokenStore) {
      await _tokenStore.deleteIfRevision(revision!);
    } else {
      await _tokenStore.delete();
    }
  }

  Future<void> _persistSession(AuthSession session, int? revision) async {
    if (_tokenStore is GuardedAuthTokenStore) {
      final written = await _tokenStore.writeTokensIfRevision(revision!,
          accessToken: session.accessToken, refreshToken: session.refreshToken);
      if (!written) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.unauthorized,
          code: 'SESSION_CHANGED',
          message: 'Session changed during sign-in.',
        );
      }
      return;
    }
    await _tokenStore.writeTokens(
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
