import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';

void main() {
  test('multipart upload is replayed safely after access-token refresh',
      () async {
    final adapter = _RefreshThenAcceptUploadAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1/',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    final tokenStore = InMemoryAuthTokenStore();
    await tokenStore.writeTokens(
      accessToken: 'expired-access-token',
      refreshToken: 'valid-refresh-token',
    );
    final client = DioMushukistanApiClient(
      dio: dio,
      tokenStore: tokenStore,
      uploadRequestTimeout: const Duration(minutes: 2),
    );
    final formData = FormData.fromMap(<String, Object>{
      'description': 'Unicode filename upload',
      'photos': <MultipartFile>[
        MultipartFile.fromBytes(
          Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]),
          filename: 'мой кот.jpg',
        ),
      ],
    });

    final result = await client.postMultipart<bool>(
      'posts',
      formData: formData,
      decoder: (json) => (json as Map<String, Object?>)['accepted'] as bool,
    );

    expect(result, isTrue);
    expect(adapter.uploadBodyLengths, hasLength(2));
    expect(adapter.uploadBodyLengths[0], greaterThan(0));
    expect(adapter.uploadBodyLengths[1], adapter.uploadBodyLengths[0]);
    expect(adapter.refreshCalls, 1);
    expect(
      adapter.uploadTimeouts,
      everyElement(const Duration(minutes: 2)),
    );
  });

  test('upload timeout produces a useful photo-specific error', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://example.test/api/v1/',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = _UploadTimeoutAdapter();
    final client = DioMushukistanApiClient(
      dio: dio,
      tokenStore: InMemoryAuthTokenStore(),
    );

    await expectLater(
      client.postMultipart<Object?>(
        'posts',
        formData: FormData.fromMap(<String, Object>{
          'photo': MultipartFile.fromBytes(<int>[1, 2, 3]),
        }),
        decoder: (json) => json,
      ),
      throwsA(
        isA<MushukistanApiException>()
            .having(
              (error) => error.code,
              'code',
              'PHOTO_UPLOAD_TIMEOUT',
            )
            .having(
              (error) => error.userMessage,
              'message',
              contains('took too long'),
            ),
      ),
    );
  });
}

class _RefreshThenAcceptUploadAdapter implements HttpClientAdapter {
  final List<int> uploadBodyLengths = <int>[];
  final List<Duration?> uploadTimeouts = <Duration?>[];
  int refreshCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bodyLength = await _consume(requestStream);
    if (options.path.endsWith('auth/refresh')) {
      refreshCalls += 1;
      return _jsonResponse(
        200,
        <String, Object?>{
          'success': true,
          'data': <String, Object?>{
            'access_token': 'fresh-access-token',
            'refresh_token': 'fresh-refresh-token',
          },
        },
      );
    }

    uploadBodyLengths.add(bodyLength);
    uploadTimeouts.add(options.receiveTimeout);
    expect(options.sendTimeout, const Duration(minutes: 2));
    if (uploadBodyLengths.length == 1) {
      return _jsonResponse(
        401,
        <String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': 'UNAUTHORIZED',
            'message': 'Access token expired.',
          },
        },
      );
    }
    return _jsonResponse(
      201,
      <String, Object?>{
        'success': true,
        'data': <String, Object?>{'accepted': true},
      },
    );
  }

  Future<int> _consume(Stream<Uint8List>? stream) async {
    if (stream == null) {
      return 0;
    }
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
    }
    return length;
  }

  ResponseBody _jsonResponse(int statusCode, Object body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _UploadTimeoutAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
    );
  }

  @override
  void close({bool force = false}) {}
}
