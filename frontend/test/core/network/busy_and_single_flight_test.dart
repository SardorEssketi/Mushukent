import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:mushukistan_frontend/core/widgets/busy_retry_action.dart';

/// Load audit FIX-7 (busy handling) and LT-21 (single in-flight GET users/me).
void main() {
  DioMushukistanApiClient clientWith(_CountingAdapter adapter,
      [AuthTokenStore? store]) {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://example.test/api/v1/',
      validateStatus: (_) => true,
    ))
      ..httpClientAdapter = adapter;
    return DioMushukistanApiClient(
        dio: dio, tokenStore: store ?? InMemoryAuthTokenStore());
  }

  test('concurrent GET users/me share one HTTP request', () async {
    final adapter = _CountingAdapter();
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    await store.writeTokens(accessToken: 'a', refreshToken: 'r');
    final client = clientWith(adapter, store);

    final first = client.get<Object?>('users/me', decoder: (json) => json);
    final second =
        client.get<String>('users/me', decoder: (json) => (json as Map)['id']);
    final third = client.get<Object?>('users/me', decoder: (json) => json);
    await adapter.waitForCalls();
    adapter.complete(_json({'id': 'user-a'}));

    expect(await second, 'user-a');
    expect((await first as Map)['id'], 'user-a');
    expect((await third as Map)['id'], 'user-a');
    expect(adapter.calls, 1);
  });

  test('a later GET users/me is a new request, not a cached answer', () async {
    final adapter = _CountingAdapter();
    final client = clientWith(adapter);
    final first = client.get<Object?>('users/me', decoder: (json) => json);
    await adapter.waitForCalls();
    adapter.complete(_json({'id': 'one'}));
    await first;
    final second = client.get<Object?>('users/me', decoder: (json) => json);
    await adapter.waitForCalls();
    adapter.complete(_json({'id': 'two'}));
    expect((await second as Map)['id'], 'two');
    expect(adapter.calls, 2);
  });

  test('429 and 503 SERVICE_BUSY are busy errors with Retry-After', () async {
    for (final status in [429, 503]) {
      final adapter = _CountingAdapter();
      final client = clientWith(adapter);
      final request = client.get<Object?>('feed', decoder: (json) => json);
      await adapter.waitForCalls();
      adapter.complete(_json({
        'success': false,
        'error': {
          'code': status == 429 ? 'RATE_LIMIT_EXCEEDED' : 'SERVICE_BUSY',
          'message': 'busy',
        },
      }, status: status, retryAfter: '12'));
      await expectLater(
        request,
        throwsA(isA<MushukistanApiException>()
            .having((error) => error.isBusy, 'isBusy', isTrue)
            .having((error) => error.retryAfter, 'retryAfter',
                const Duration(seconds: 12))),
      );
    }
  });

  test('other 503s are not busy', () {
    const error = MushukistanApiException(
      kind: ApiFailureKind.server,
      code: 'PUBLICATION_OUTCOME_UNKNOWN',
      message: 'x',
      statusCode: 503,
    );
    expect(error.isBusy, isFalse);
    expect(isBusyError(error), isFalse);
  });

  test('busy retry delay honours Retry-After and backs off to at most 60 s', () {
    const busy = MushukistanApiException(
      kind: ApiFailureKind.unknown,
      code: 'RATE_LIMIT_EXCEEDED',
      message: 'x',
      statusCode: 429,
      retryAfter: Duration(seconds: 9),
    );
    expect(busyRetryDelay(busy, 0), const Duration(seconds: 9));
    expect(busyRetryDelay(busy, 2), const Duration(seconds: 9));
    expect(busyRetryDelay(busy, 3), const Duration(seconds: 16));
    expect(busyRetryDelay(busy, 10), const Duration(seconds: 60));
  });
}

ResponseBody _json(Map<String, Object?> body,
    {int status = 200, String? retryAfter}) {
  return ResponseBody.fromString(jsonEncode(body), status, headers: {
    Headers.contentTypeHeader: ['application/json'],
    if (retryAfter != null) 'retry-after': [retryAfter],
  });
}

class _CountingAdapter implements HttpClientAdapter {
  int calls = 0;
  final List<Completer<ResponseBody>> _pending = [];

  void complete(ResponseBody body) => _pending.removeAt(0).complete(body);

  /// Waits until a request is waiting for an answer (interceptors run asynchronously first).
  Future<void> waitForCalls() async {
    for (var i = 0; i < 200 && _pending.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Let any concurrent callers reach the adapter too.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    calls++;
    final completer = Completer<ResponseBody>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  void close({bool force = false}) {}
}
