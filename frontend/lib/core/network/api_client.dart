import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../config/app_environment.dart';
import '../storage/token_store.dart';
import '../storage/token_store_provider.dart';
import 'api_error.dart';
import 'publication_retry.dart';
import 'publication_session.dart';

abstract class MushukistanApiClient {
  Uri? get baseUri;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  });

  Future<T> postJson<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
    String? bearerToken,
    Map<String, String>? headers,
  });

  Future<T> patchJson<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  });

  Future<T> postMultipart<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  });

  Future<T> patchMultipart<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  });

  Future<void> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  });
}

class DioMushukistanApiClient implements MushukistanApiClient {
  DioMushukistanApiClient({
    required Dio dio,
    required AuthTokenStore tokenStore,
    Duration uploadRequestTimeout = const Duration(minutes: 3),
    PublicationJournal? publicationJournal,
  })  : _dio = dio,
        _tokenStore = tokenStore,
        _uploadRequestTimeout = uploadRequestTimeout,
        _publicationJournal = publicationJournal ?? MemoryPublicationJournal() {
    // Pin credentials at dispatch, after any earlier asynchronous interceptor.
    _dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) async {
      final binding = options.extra['publicationSession'];
      if (binding is PublicationSession) {
        try {
          final token = await binding.credentials();
          if (options.extra['publicationRefresh'] != true) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } on MushukistanApiException catch (error) {
          handler.reject(DioException(requestOptions: options, error: error));
          return;
        }
      }
      handler.next(options);
    }));
  }

  final Dio _dio;
  final AuthTokenStore _tokenStore;
  final Duration _uploadRequestTimeout;
  Future<bool>? _refreshInFlight;
  final PublicationJournal _publicationJournal;
  final _publicationInFlight = <String, Future<Object?>>{};

  @override
  Uri? get baseUri => Uri.tryParse(_dio.options.baseUrl);

  factory DioMushukistanApiClient.fromEnvironment({
    required AppEnvironment environment,
    required AuthTokenStore tokenStore,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: environment.apiBaseUri.toString(),
        connectTimeout: environment.requestTimeout,
        receiveTimeout: environment.requestTimeout,
        sendTimeout: environment.requestTimeout,
        // `x-contact-mode: reveal` tells the server this app fetches owner contacts through the
        // explicit reveal endpoints, so detail responses never need to carry them.
        headers: const {
          'accept': 'application/json',
          'x-contact-mode': 'reveal',
        },
        validateStatus: (_) => true,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final skipAuth = options.extra['skipAuth'] == true;
          if (!skipAuth) {
            final token = await tokenStore.read();
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
    return DioMushukistanApiClient(
      dio: dio,
      tokenStore: tokenStore,
      uploadRequestTimeout: environment.uploadRequestTimeout,
      publicationJournal: PreferencesPublicationJournal(),
    );
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) {
    return _request<T>(
      'GET',
      path,
      body: null,
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
    return _request<T>(
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
    String? bearerToken,
    Map<String, String>? headers,
  }) {
    return _request<T>(
      'POST',
      path,
      body: body,
      queryParameters: queryParameters,
      decoder: decoder,
      authenticated: authenticated,
      bearerToken: bearerToken,
      headers: headers,
    );
  }

  @override
  Future<T> postMultipart<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) async {
    final normalizedPath = _normalizePath(path);
    if (authenticated &&
        const {'posts', 'lost-pets', 'adoption-posts'}
            .contains(normalizedPath)) {
      final session = PublicationSession(_tokenStore);
      try {
        await session.credentials();
        final scope = session.scope;
        final fingerprint =
            await publicationFingerprint(normalizedPath, formData);
        await session.credentials();
        final inFlightKey = '$scope:$fingerprint';
        final existing = _publicationInFlight[inFlightKey];
        if (existing != null) return (await existing) as T;
        final future = _postPublication<T>(
            normalizedPath, formData, session, fingerprint,
            decoder: decoder, queryParameters: queryParameters);
        _publicationInFlight[inFlightKey] = future;
        try {
          return await future;
        } finally {
          if (identical(_publicationInFlight[inFlightKey], future)) {
            _publicationInFlight.remove(inFlightKey);
          }
        }
      } finally {
        await session.dispose();
      }
    }
    return _request<T>(
      'POST',
      path,
      body: formData,
      queryParameters: queryParameters,
      decoder: decoder,
      authenticated: authenticated,
    );
  }

  Future<T> _postPublication<T>(String path, FormData form,
      PublicationSession session, String fingerprint,
      {required T Function(Object?) decoder,
      Map<String, dynamic>? queryParameters}) async {
    final scope = session.scope;
    String? previous;
    late String key;
    try {
      previous = await _publicationJournal.read(scope, fingerprint);
      key = previous ?? newPublicationKey();
      await _publicationJournal.write(scope, fingerprint, key);
    } catch (error) {
      logPublicationFailure('preserve_attempt', error);
      throw const MushukistanApiException(
          kind: ApiFailureKind.unknown,
          code: 'PUBLICATION_JOURNAL_UNAVAILABLE',
          message: 'Could not preserve the publication attempt. Try again.');
    }
    Future<void> checkAccount() async {
      await session.credentials();
    }

    Future<T> finish(T value) async {
      try {
        await _publicationJournal.remove(scope, fingerprint);
      } catch (error) {
        logPublicationFailure('clear_completed_attempt', error, key: key);
      }
      return value;
    }

    if (previous != null) {
      await checkAccount();
      Map<String, Object?>? status;
      try {
        status = await _publicationGet<Map<String, Object?>>(
            'publication-operations/$key', session,
            decoder: (json) => Map<String, Object?>.from(json as Map));
      } on MushukistanApiException catch (error) {
        if (error.code == 'SESSION_CHANGED') rethrow;
        if (error.code != 'PUBLICATION_OPERATION_NOT_FOUND') {
          logPublicationFailure('reconcile_attempt', error, key: key);
          throw const MushukistanApiException(
              kind: ApiFailureKind.network,
              code: 'PUBLICATION_OUTCOME_UNKNOWN',
              message:
                  'Could not verify publication status. Check again before retrying.');
        }
      }
      if (status?['state'] == 'completed') {
        final expectedKind = switch (path) {
          'posts' => 'post',
          'lost-pets' => 'lost_pet',
          _ => 'adoption_post'
        };
        if (status?['target_kind'] != expectedKind) {
          throw const MushukistanApiException(
              kind: ApiFailureKind.parse,
              code: 'MALFORMED_RESPONSE',
              message: 'Unexpected publication status.');
        }
        final value = await _publicationGet<T>(
            '$path/${status!['target_id']}', session,
            decoder: decoder);
        return finish(value);
      }
      if (status?['state'] == 'pending' && status?['can_retry'] != true) {
        throw const MushukistanApiException(
            kind: ApiFailureKind.conflict,
            code: 'PUBLICATION_IN_PROGRESS',
            message:
                'Publication is still processing. Check its status again.');
      }
      if (status != null &&
          status['state'] != 'failed' &&
          status['can_retry'] != true) {
        throw const MushukistanApiException(
            kind: ApiFailureKind.parse,
            code: 'MALFORMED_RESPONSE',
            message: 'Unexpected publication status.');
      }
    }
    await checkAccount();
    try {
      final value = await _request<T>('POST', path,
          body: form,
          queryParameters: queryParameters,
          decoder: decoder,
          authenticated: true,
          publicationSession: session,
          headers: {'Idempotency-Key': key});
      return finish(value);
    } catch (error) {
      logPublicationFailure('submit', error, key: key);
      rethrow;
    }
  }

  Future<T> _publicationGet<T>(String path, PublicationSession session,
          {required T Function(Object?) decoder}) =>
      _request<T>('GET', path,
          body: null,
          queryParameters: null,
          decoder: decoder,
          authenticated: true,
          publicationSession: session);

  @override
  Future<T> patchMultipart<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    bool authenticated = true,
  }) {
    return _request<T>(
      'PATCH',
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
    await _request<Object?>(
      'DELETE',
      path,
      body: null,
      queryParameters: queryParameters,
      decoder: (_) => null,
      authenticated: authenticated,
    );
  }

  Future<T> _request<T>(
    String method,
    String path, {
    required Object? body,
    required Map<String, dynamic>? queryParameters,
    required T Function(Object? json) decoder,
    required bool authenticated,
    String? bearerToken,
    Map<String, String>? headers,
    bool retriedAfterRefresh = false,
    PublicationSession? publicationSession,
  }) async {
    final guarded = _tokenStore is GuardedAuthTokenStore ? _tokenStore : null;
    final revision = guarded?.revision;
    try {
      final requestBody = body is FormData ? body.clone() : body;
      final isMultipart = body is FormData;
      final response = await _dio.request<Object?>(
        _normalizePath(path),
        data: requestBody,
        cancelToken: publicationSession?.cancelToken,
        queryParameters: _normalizeQueryParameters(queryParameters),
        options: Options(
          method: method,
          responseType: ResponseType.json,
          listFormat: ListFormat.multi,
          extra: {
            'skipAuth': !authenticated || publicationSession != null,
            if (publicationSession != null)
              'publicationSession': publicationSession
          },
          headers: <String, String>{
            ...?headers,
            'X-Request-ID': newPublicationKey(),
            if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
          },
          sendTimeout: isMultipart ? _uploadRequestTimeout : null,
          receiveTimeout: isMultipart ? _uploadRequestTimeout : null,
        ),
      );

      if (publicationSession != null) await publicationSession.credentials();
      if (publicationSession == null &&
          authenticated &&
          guarded != null &&
          guarded.revision != revision) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.unauthorized,
          code: 'SESSION_CHANGED',
          message: 'Session changed during request.',
        );
      }

      final payload = _normalizePayload(response.data);
      final normalizedPayload = _normalizeMediaUrls(payload);
      final statusCode = response.statusCode ?? 0;

      if (statusCode >= 400) {
        final error = MushukistanApiException.fromEnvelope(
          payload,
          statusCode: statusCode,
        );
        if (_shouldRefreshAndRetry(
          error,
          path: path,
          authenticated: authenticated,
          retriedAfterRefresh: retriedAfterRefresh,
        )) {
          final refreshed =
              await _refreshAccessToken(publicationSession: publicationSession);
          if (publicationSession != null) {
            await publicationSession.credentials();
          }
          if (refreshed) {
            return _request<T>(
              method,
              path,
              body: body,
              queryParameters: queryParameters,
              decoder: decoder,
              authenticated: authenticated,
              bearerToken: bearerToken,
              headers: headers,
              retriedAfterRefresh: true,
              publicationSession: publicationSession,
            );
          }
        }
        throw error;
      }

      if (normalizedPayload == null) {
        return decoder(null);
      }

      if (normalizedPayload is Map<String, Object?>) {
        final success = normalizedPayload['success'];
        if (success == false) {
          throw MushukistanApiException.fromEnvelope(
            normalizedPayload,
            statusCode: statusCode,
          );
        }
        if (normalizedPayload.containsKey('data')) {
          return _decodePayload(decoder, normalizedPayload['data']);
        }
      }

      return _decodePayload(decoder, normalizedPayload);
    } on DioException catch (error) {
      if (publicationSession != null) await publicationSession.credentials();
      if (error.error case final MushukistanApiException cause) {
        if (cause.code == 'SESSION_CHANGED') throw cause;
      }
      debugPrint(
          'API transport failure: request=${error.requestOptions.headers['X-Request-ID']} type=${error.type.name} cause=${error.error.runtimeType} status=${error.response?.statusCode}');
      if (body is FormData && _isNetworkFailure(error.type)) {
        throw MushukistanApiException(
          kind: ApiFailureKind.network,
          statusCode: error.response?.statusCode,
          code: _isTimeout(error.type)
              ? 'PHOTO_UPLOAD_TIMEOUT'
              : 'PHOTO_UPLOAD_NETWORK_ERROR',
          details: {
            'transport_type': error.type.name,
            'cause_type': error.error.runtimeType.toString(),
            'request_id': error.requestOptions.headers['X-Request-ID']
          },
          message: _isTimeout(error.type)
              ? 'Photo upload took too long. Check your connection and try again.'
              : 'Photo upload failed. Check your connection and try again.',
        );
      }
      throw MushukistanApiException.fromDioException(error);
    }
  }

  bool _isNetworkFailure(DioExceptionType type) {
    return switch (type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.cancel ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        true,
      DioExceptionType.badCertificate || DioExceptionType.badResponse => false,
    };
  }

  bool _isTimeout(DioExceptionType type) {
    return type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.transformTimeout;
  }

  bool _shouldRefreshAndRetry(
    MushukistanApiException error, {
    required String path,
    required bool authenticated,
    required bool retriedAfterRefresh,
  }) {
    if (!authenticated || retriedAfterRefresh) {
      return false;
    }
    final normalizedPath = _normalizePath(path);
    if (normalizedPath == 'auth/refresh' ||
        normalizedPath == 'auth/login' ||
        normalizedPath == 'auth/google') {
      return false;
    }
    return error.kind == ApiFailureKind.unauthorized;
  }

  Future<bool> _refreshAccessToken({PublicationSession? publicationSession}) {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future =
        _performRefreshAccessToken(publicationSession: publicationSession);
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<bool> _performRefreshAccessToken(
      {PublicationSession? publicationSession}) async {
    final guarded = _tokenStore is GuardedAuthTokenStore ? _tokenStore : null;
    final revision = guarded?.revision;
    final refreshToken = await _tokenStore.readRefreshToken();
    if (publicationSession != null) await publicationSession.credentials();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      return false;
    }

    try {
      final response = await _dio.request<Object?>(
        'auth/refresh',
        data: <String, Object?>{'refresh_token': refreshToken},
        cancelToken: publicationSession?.cancelToken,
        options: Options(
          method: 'POST',
          responseType: ResponseType.json,
          extra: {
            'skipAuth': true,
            if (publicationSession != null)
              'publicationSession': publicationSession,
            'publicationRefresh': true
          },
        ),
      );
      final payload = _normalizePayload(response.data);
      if (publicationSession != null) await publicationSession.credentials();
      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 400) {
        final error = MushukistanApiException.fromEnvelope(
          payload,
          statusCode: statusCode,
        );
        if (error.isSessionInvalid) {
          if (guarded != null) {
            await guarded.deleteIfRevision(revision!);
          } else {
            await _tokenStore.delete();
          }
        }
        throw error;
      }
      final data = payload is Map ? payload['data'] : payload;
      if (data is! Map) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.parse,
          code: 'MALFORMED_RESPONSE',
          message: 'Malformed response received.',
        );
      }
      final accessToken = data['access_token'];
      if (accessToken is! String || accessToken.trim().isEmpty) {
        throw const MushukistanApiException(
          kind: ApiFailureKind.parse,
          code: 'MALFORMED_RESPONSE',
          message: 'Malformed response received.',
        );
      }
      final newRefreshToken = data['refresh_token'];
      final resultingRefreshToken =
          newRefreshToken is String && newRefreshToken.isNotEmpty
              ? newRefreshToken
              : refreshToken;
      if (guarded != null) {
        return guarded.writeTokensIfRevision(revision!,
            accessToken: accessToken, refreshToken: resultingRefreshToken);
      }
      await _tokenStore.writeTokens(
        accessToken: accessToken,
        refreshToken: resultingRefreshToken,
      );
      return true;
    } on DioException catch (error) {
      if (publicationSession != null) await publicationSession.credentials();
      throw MushukistanApiException.fromDioException(error);
    }
  }

  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
  }

  Map<String, dynamic>? _normalizeQueryParameters(
    Map<String, dynamic>? queryParameters,
  ) {
    if (queryParameters == null) {
      return null;
    }
    return queryParameters.map((key, value) => MapEntry(key, value));
  }

  Object? _normalizePayload(Object? payload) {
    if (payload is String) {
      final trimmed = payload.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        return jsonDecode(trimmed);
      } on FormatException {
        return trimmed;
      }
    }
    return payload;
  }

  Object? _normalizeMediaUrls(Object? payload) {
    final baseUri = this.baseUri;
    if (baseUri == null || payload == null) {
      return payload;
    }
    return _normalizeMediaUrlsRecursive(payload, baseUri);
  }

  Object? _normalizeMediaUrlsRecursive(Object? payload, Uri baseUri) {
    if (payload is Map) {
      final result = <String, Object?>{};
      for (final entry in payload.entries) {
        final key = entry.key.toString();
        final normalizedValue =
            _normalizeMediaUrlsRecursive(entry.value, baseUri);
        if (normalizedValue is String && _mediaUrlKeys.contains(key)) {
          result[key] = _resolveMediaUrl(normalizedValue, baseUri);
        } else if (normalizedValue is List && _mediaUrlKeys.contains(key)) {
          result[key] = normalizedValue
              .map(
                (value) =>
                    value is String ? _resolveMediaUrl(value, baseUri) : value,
              )
              .toList(growable: false);
        } else {
          result[key] = normalizedValue;
        }
      }
      return result;
    }
    if (payload is List) {
      return payload
          .map((value) => _normalizeMediaUrlsRecursive(value, baseUri))
          .toList(growable: false);
    }
    return payload;
  }

  String _resolveMediaUrl(String value, Uri baseUri) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.hasScheme) {
      return value;
    }
    return baseUri.resolve(value).toString();
  }

  T _decodePayload<T>(T Function(Object? json) decoder, Object? payload) {
    try {
      return decoder(payload);
    } on FormatException catch (_) {
      throw MushukistanApiException(
        kind: ApiFailureKind.parse,
        code: 'MALFORMED_RESPONSE',
        message: 'Malformed response received.',
        details: payload,
      );
    } on TypeError catch (_) {
      throw MushukistanApiException(
        kind: ApiFailureKind.parse,
        code: 'MALFORMED_RESPONSE',
        message: 'Malformed response received.',
        details: payload,
      );
    } on StateError catch (_) {
      throw MushukistanApiException(
        kind: ApiFailureKind.parse,
        code: 'MALFORMED_RESPONSE',
        message: 'Malformed response received.',
        details: payload,
      );
    }
  }
}

const _mediaUrlKeys = <String>{
  'avatar_url',
  'cover_photo_url',
  'photo_url',
  'photo_urls',
  'thumb_url',
};

final apiClientProvider = Provider<MushukistanApiClient>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final tokenStore = ref.watch(tokenStoreProvider);
  return DioMushukistanApiClient.fromEnvironment(
    environment: environment,
    tokenStore: tokenStore,
  );
});
