import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';

void main() {
  test('logout sends captured bearer proof after local deletion', () async {
    final adapter = _DelayedAdapter();
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.test/api/v1/',
      validateStatus: (_) => true,
    ))
      ..httpClientAdapter = adapter;
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    final client = DioMushukistanApiClient(dio: dio, tokenStore: store);
    final request = client.postJson<Object?>(
      'auth/logout',
      authenticated: false,
      bearerToken: 'captured-access',
      body: {'refresh_token': 'captured-refresh'},
      decoder: (_) => null,
    );
    await adapter.started.future;
    expect(adapter.options?.headers['Authorization'], 'Bearer captured-access');
    adapter.finish.complete(ResponseBody.fromString('', 204));
    await request;
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('a protected response started before logout is discarded', () async {
    final adapter = _DelayedAdapter();
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.test/api/v1/',
      validateStatus: (_) => true,
    ))
      ..httpClientAdapter = adapter;
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    await store.writeTokens(accessToken: 'access-a', refreshToken: 'refresh-a');
    final client = DioMushukistanApiClient(dio: dio, tokenStore: store);
    final request = client.get<Object?>('users/me', decoder: (json) => json);
    await adapter.started.future;
    await store.delete();
    adapter.finish.complete(ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {'id': 'user-a'}
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    ));
    await expectLater(
        request,
        throwsA(isA<MushukistanApiException>()
            .having((error) => error.code, 'code', 'SESSION_CHANGED')));
  });
}

class _DelayedAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final finish = Completer<ResponseBody>();
  RequestOptions? options;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    this.options = options;
    started.complete();
    return finish.future;
  }

  @override
  void close({bool force = false}) {}
}
