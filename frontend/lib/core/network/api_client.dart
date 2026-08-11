import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../storage/token_store.dart';
import '../storage/token_store_provider.dart';
import 'api_error.dart';

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

  Future<void> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  });
}

class DioMushukistanApiClient implements MushukistanApiClient {
  DioMushukistanApiClient({
    required Dio dio,
  }) : _dio = dio;

  final Dio _dio;

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
        headers: const {'accept': 'application/json'},
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
    return DioMushukistanApiClient(dio: dio);
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
  }) {
    return _request<T>(
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
    return _request<T>(
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
  }) async {
    try {
      final response = await _dio.request<Object?>(
        _normalizePath(path),
        data: body,
        queryParameters: _normalizeQueryParameters(queryParameters),
        options: Options(
          method: method,
          responseType: ResponseType.json,
          listFormat: ListFormat.multi,
          extra: {'skipAuth': !authenticated},
        ),
      );

      final payload = _normalizePayload(response.data);
      final normalizedPayload = _normalizeMediaUrls(payload);
      final statusCode = response.statusCode ?? 0;

      if (statusCode >= 400) {
        throw MushukistanApiException.fromEnvelope(
          payload,
          statusCode: statusCode,
        );
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
