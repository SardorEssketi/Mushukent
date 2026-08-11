import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_models.dart';
import 'package:mushukistan_frontend/features/auth/domain/auth_repository.dart';
import 'package:mushukistan_frontend/features/auth/infrastructure/google_sign_in_service.dart';

class ApiCall {
  ApiCall({
    required this.method,
    required this.path,
    required this.authenticated,
    this.body,
    this.queryParameters,
  });

  final String method;
  final String path;
  final bool authenticated;
  final Object? body;
  final Map<String, dynamic>? queryParameters;
}

class FakeApiClient implements MushukistanApiClient {
  final calls = <ApiCall>[];
  final handlers = <String, FutureOr<Object?> Function(ApiCall call)>{};

  @override
  Uri? get baseUri => null;

  void setHandler(
    String method,
    String path,
    FutureOr<Object?> Function(ApiCall call) handler,
  ) {
    handlers['$method $path'] = handler;
  }

  Future<T> _handle<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    required bool authenticated,
  }) async {
    final call = ApiCall(
      method: method,
      path: path,
      authenticated: authenticated,
      body: body,
      queryParameters: queryParameters,
    );
    calls.add(call);
    final handler = handlers['$method $path'];
    if (handler == null) {
      throw StateError('No fake handler registered for $method $path');
    }
    final payload = await handler(call);
    return decoder(payload);
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) {
    return _handle<T>(
      'GET',
      path,
      queryParameters: queryParameters,
      decoder: decoder,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> patchJson<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) {
    return _handle<T>(
      'PATCH',
      path,
      body: body,
      queryParameters: queryParameters,
      decoder: decoder,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> postJson<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) {
    return _handle<T>(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      decoder: decoder,
      authenticated: authenticated,
    );
  }

  @override
  Future<T> postMultipart<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) {
    return _handle<T>(
      'POST',
      path,
      body: formData,
      queryParameters: queryParameters,
      decoder: decoder,
      authenticated: authenticated,
    );
  }

  @override
  Future<void> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    await _handle<Object?>(
      'DELETE',
      path,
      queryParameters: queryParameters,
      decoder: (_) => null,
      authenticated: authenticated,
    );
  }
}

class FakeAuthTokenStore implements AuthTokenStore {
  FakeAuthTokenStore([this.initialToken]);

  String? initialToken;
  String? currentToken;

  @override
  Future<void> delete() async {
    currentToken = null;
    initialToken = null;
  }

  @override
  Future<String?> read() async {
    return currentToken ?? initialToken;
  }

  @override
  Future<void> write(String token) async {
    currentToken = token;
    initialToken = token;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.registerResult,
    this.loginResult,
    this.restoreResult = const SessionRestoreMissing(),
    this.currentUser,
  });

  RegisterCredentials? lastRegisterCredentials;
  AuthCredentials? lastLoginCredentials;
  bool logoutCalled = false;
  int restoreCalls = 0;
  int loginCalls = 0;
  int registerCalls = 0;
  Object? loginError;
  Object? registerError;
  Object? resendVerificationError;
  Object? restoreError;
  Completer<AuthSession>? loginCompleter;
  Completer<VerificationRequirement>? registerCompleter;
  Completer<SessionRestoreResult>? restoreCompleter;

  final VerificationRequirement? registerResult;
  AuthSession? loginResult;
  SessionRestoreResult restoreResult;
  final MushukistanUser? currentUser;
  String? lastResendVerificationEmail;
  String? lastVerifyEmailToken;
  String? lastGoogleIdToken;

  @override
  Future<AuthSession> login(AuthCredentials credentials) async {
    loginCalls += 1;
    lastLoginCredentials = credentials;
    final pending = loginCompleter;
    if (pending != null) {
      return pending.future;
    }
    if (loginError != null) {
      throw loginError!;
    }
    final result = loginResult;
    if (result == null) {
      throw StateError('No fake login result configured.');
    }
    return result;
  }

  @override
  Future<VerificationRequirement> register(
      RegisterCredentials credentials) async {
    registerCalls += 1;
    lastRegisterCredentials = credentials;
    final pending = registerCompleter;
    if (pending != null) {
      return pending.future;
    }
    if (registerError != null) {
      throw registerError!;
    }
    final result = registerResult;
    if (result == null) {
      throw StateError('No fake register result configured.');
    }
    return result;
  }

  @override
  Future<AuthSession> loginWithGoogleIdToken(
    String idToken, {
    bool acceptTerms = false,
    bool acceptPrivacy = false,
  }) async {
    lastGoogleIdToken = idToken;
    if (loginError != null) {
      throw loginError!;
    }
    final result = loginResult;
    if (result == null) {
      throw StateError('No fake login result configured.');
    }
    return result;
  }

  @override
  Future<VerificationRequirement> resendVerification(String email) async {
    lastResendVerificationEmail = email;
    if (resendVerificationError != null) {
      throw resendVerificationError!;
    }
    return registerResult ??
        VerificationRequirement(
          email: email,
          devVerificationToken: 'dev-token',
        );
  }

  @override
  Future<void> verifyEmail(String token) async {
    lastVerifyEmailToken = token;
  }

  @override
  Future<MushukistanUser> fetchCurrentUser() async {
    final user = currentUser ?? loginResult?.user;
    if (user == null) {
      throw StateError('No fake current user configured.');
    }
    return user;
  }

  @override
  Future<SessionRestoreResult> restoreSession() async {
    restoreCalls += 1;
    final pending = restoreCompleter;
    if (pending != null) {
      return pending.future;
    }
    if (restoreError != null) {
      throw restoreError!;
    }
    return restoreResult;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

class FakeGoogleIdentityTokenProvider implements GoogleIdentityTokenProvider {
  FakeGoogleIdentityTokenProvider({
    this.idToken = 'google-id-token',
    this.error,
  });

  final String idToken;
  final Object? error;
  int calls = 0;

  @override
  Future<String> authenticate() async {
    calls += 1;
    if (error != null) {
      throw error!;
    }
    return idToken;
  }
}

MushukistanUser testUser({
  String id = '11111111-1111-4111-8111-111111111111',
  String? email = 'user@example.com',
  String? name = 'Sardor',
  String? avatarUrl,
  String? bio = 'Cat lover',
  DateTime? registeredAt,
  int observationCount = 12,
  int totalLikesReceived = 45,
  int commentCount = 17,
  bool allowPublicActivityView = true,
}) {
  return MushukistanUser(
    id: id,
    email: email,
    name: name,
    avatarUrl: avatarUrl,
    bio: bio,
    registeredAt: registeredAt ?? DateTime.utc(2026, 7, 1, 10),
    observationCount: observationCount,
    totalLikesReceived: totalLikesReceived,
    commentCount: commentCount,
    allowPublicActivityView: allowPublicActivityView,
  );
}
