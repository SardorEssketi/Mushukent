import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store_provider.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import '../infrastructure/auth_repository_impl.dart';
import '../infrastructure/google_sign_in_service.dart';

enum AuthPhase {
  initial,
  restoring,
  unauthenticated,
  verificationRequired,
  authenticating,
  authenticated,
  failure,
}

class AuthState {
  const AuthState._({
    required this.phase,
    this.user,
    this.message,
    this.fieldErrors = const <String, String>{},
    this.retryable = false,
    this.pendingVerificationEmail,
    this.devVerificationToken,
  });

  final AuthPhase phase;
  final MushukistanUser? user;
  final String? message;
  final Map<String, String> fieldErrors;
  final bool retryable;
  final String? pendingVerificationEmail;
  final String? devVerificationToken;

  bool get isAuthenticated => phase == AuthPhase.authenticated;
  bool get isBusy =>
      phase == AuthPhase.restoring || phase == AuthPhase.authenticating;
  bool get hasError => message != null && message!.trim().isNotEmpty;

  factory AuthState.initial() => const AuthState._(phase: AuthPhase.initial);

  factory AuthState.restoring() =>
      const AuthState._(phase: AuthPhase.restoring);

  factory AuthState.unauthenticated({
    String? message,
    Map<String, String> fieldErrors = const <String, String>{},
  }) {
    return AuthState._(
      phase: AuthPhase.unauthenticated,
      message: message,
      fieldErrors: fieldErrors,
    );
  }

  factory AuthState.authenticating() =>
      const AuthState._(phase: AuthPhase.authenticating);

  factory AuthState.verificationRequired({
    required String email,
    String? message,
    String? devVerificationToken,
  }) {
    return AuthState._(
      phase: AuthPhase.verificationRequired,
      message: message,
      pendingVerificationEmail: email,
      devVerificationToken: devVerificationToken,
    );
  }

  factory AuthState.authenticated(MushukistanUser user) {
    return AuthState._(phase: AuthPhase.authenticated, user: user);
  }

  factory AuthState.failure({
    required String message,
    bool retryable = true,
  }) {
    return AuthState._(
      phase: AuthPhase.failure,
      message: message,
      retryable: retryable,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return MushukistanAuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final googleIdentityTokenProvider =
    Provider<GoogleIdentityTokenProvider>((ref) {
  return GoogleSignInService(ref.watch(appEnvironmentProvider));
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(googleIdentityTokenProvider),
  );
});

final currentUserProvider = Provider<MushukistanUser?>((ref) {
  return ref.watch(authControllerProvider.select((state) => state.user));
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._googleIdentityTokens)
      : super(AuthState.restoring()) {
    unawaited(restoreSession());
  }

  final AuthRepository _repository;
  final GoogleIdentityTokenProvider _googleIdentityTokens;
  Future<void>? _restoreInFlight;

  Future<void> restoreSession({bool force = false}) async {
    if (!force && _restoreInFlight != null) {
      return _restoreInFlight!;
    }

    final future = _performRestoreSession();
    _restoreInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_restoreInFlight, future)) {
        _restoreInFlight = null;
      }
    }
  }

  Future<void> _performRestoreSession() async {
    state = AuthState.restoring();
    final result = await _repository.restoreSession();
    switch (result) {
      case SessionRestoreMissing():
        state = AuthState.unauthenticated();
        break;
      case SessionRestoreInvalid(:final message):
        state = AuthState.unauthenticated(message: message);
        break;
      case SessionRestoreFailure(:final message, :final retryable):
        state = AuthState.failure(message: message, retryable: retryable);
        break;
      case SessionRestoreSuccess(:final session):
        state = AuthState.authenticated(session.user);
        break;
    }
  }

  Future<void> login(AuthCredentials credentials) async {
    state = AuthState.authenticating();
    try {
      final session = await _repository.login(credentials);
      state = AuthState.authenticated(session.user);
    } on MushukistanApiException catch (error) {
      if (error.code == 'EMAIL_NOT_VERIFIED') {
        state = AuthState.verificationRequired(
          email: credentials.email.trim(),
          message: error.userMessage,
        );
      } else {
        state = AuthState.unauthenticated(
          message: error.userMessage,
          fieldErrors: _fieldErrorsFromDetails(error.details),
        );
      }
      rethrow;
    }
  }

  Future<void> register(RegisterCredentials credentials) async {
    state = AuthState.authenticating();
    try {
      final verification = await _repository.register(credentials);
      state = AuthState.verificationRequired(
        email: verification.email,
        message: 'Check your email for a verification link.',
        devVerificationToken: verification.devVerificationToken,
      );
    } on MushukistanApiException catch (error) {
      state = AuthState.unauthenticated(
        message: error.userMessage,
        fieldErrors: _fieldErrorsFromDetails(error.details),
      );
      rethrow;
    }
  }

  Future<void> loginWithGoogle({
    bool acceptTerms = false,
    bool acceptPrivacy = false,
  }) async {
    state = AuthState.authenticating();
    try {
      final idToken = await _googleIdentityTokens.authenticate();
      await loginWithGoogleIdToken(
        idToken,
        acceptTerms: acceptTerms,
        acceptPrivacy: acceptPrivacy,
      );
    } on GoogleSignInFlowException catch (error) {
      state = AuthState.unauthenticated(message: error.message);
      rethrow;
    } on MushukistanApiException catch (error) {
      state = AuthState.unauthenticated(message: error.userMessage);
      rethrow;
    }
  }

  Future<void> loginWithGoogleIdToken(
    String idToken, {
    bool acceptTerms = false,
    bool acceptPrivacy = false,
  }) async {
    state = AuthState.authenticating();
    try {
      final session = await _repository.loginWithGoogleIdToken(
        idToken,
        acceptTerms: acceptTerms,
        acceptPrivacy: acceptPrivacy,
      );
      state = AuthState.authenticated(session.user);
    } on MushukistanApiException catch (error) {
      state = AuthState.unauthenticated(message: error.userMessage);
      rethrow;
    }
  }

  Future<void> resendVerification([String? email]) async {
    final targetEmail = email?.trim().isNotEmpty == true
        ? email!.trim()
        : state.pendingVerificationEmail;
    if (targetEmail == null || targetEmail.isEmpty) {
      state = AuthState.unauthenticated(
        message: 'Email is required.',
      );
      return;
    }

    try {
      final verification = await _repository.resendVerification(targetEmail);
      state = AuthState.verificationRequired(
        email: verification.email,
        message: 'Verification email sent.',
        devVerificationToken: verification.devVerificationToken,
      );
    } on MushukistanApiException catch (error) {
      state = AuthState.verificationRequired(
        email: targetEmail,
        message: error.userMessage,
        devVerificationToken: state.devVerificationToken,
      );
      rethrow;
    }
  }

  Future<void> verifyEmail(String token) async {
    try {
      await _repository.verifyEmail(token);
      state = AuthState.unauthenticated(
        message: 'Email verified. You can sign in now.',
      );
    } on MushukistanApiException catch (error) {
      state = AuthState.unauthenticated(message: error.userMessage);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = AuthState.unauthenticated();
  }

  void returnToLogin() {
    state = AuthState.unauthenticated();
  }

  void showUnauthenticatedMessage(String message) {
    state = AuthState.unauthenticated(message: message);
  }

  Map<String, String> _fieldErrorsFromDetails(Object? details) {
    if (details is! Map) {
      return const <String, String>{};
    }
    final result = <String, String>{};
    for (final entry in details.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is String) {
        result[key] = value;
      } else if (value is Iterable) {
        result[key] = value.map((item) => item.toString()).join(', ');
      } else if (value != null) {
        result[key] = value.toString();
      }
    }
    return result;
  }
}
