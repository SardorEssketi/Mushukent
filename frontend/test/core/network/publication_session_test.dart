import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/publication_retry.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';

String token(String owner, [String signature = 'signature']) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
          'sub': owner
        })))}.$signature';

ResponseBody response(Object data, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode({'success': true, 'data': data}), status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });

class Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  late Future<ResponseBody> Function(RequestOptions) answer;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (stream != null) await stream.drain<void>();
    return answer(options);
  }

  @override
  void close({bool force = false}) {}
}

Future<String> submit(DioMushukistanApiClient client) =>
    client.postMultipart('posts',
        publicationId: '11111111-1111-4111-8111-111111111111',
        formData: FormData.fromMap({
          'photos': MultipartFile.fromBytes([1, 2, 3])
        }),
        decoder: (json) => (json as Map)['id'] as String);

class ChangingJournal extends MemoryPublicationJournal {
  ChangingJournal(this.change);
  final Future<void> Function() change;
  @override
  Future<void> write(String id, PublicationRecord record) async {
    await super.write(id, record);
    await change();
  }
}

class ReadFailureStore extends InMemoryAuthTokenStore {
  bool failReads = false;
  @override
  Future<String?> read() async {
    if (failReads) throw StateError('Synthetic credential store failure');
    return super.read();
  }
}

void main() {
  test(
      'credential read failure after server success retains the operation for recovery',
      () async {
    final delegate = ReadFailureStore();
    final store = GuardedAuthTokenStore(delegate);
    await store.write(token('A'));
    final adapter = Adapter();
    int uploads = 0;
    adapter.answer = (o) async {
      if (o.path == 'posts') {
        uploads++;
        delegate.failReads = true;
        return response({'id': 'post-1'});
      }
      if (o.path.startsWith('publication-operations/')) {
        return response({
          'state': 'completed',
          'target_kind': 'post',
          'target_id': 'post-1',
          'can_retry': false
        });
      }
      return response({'id': 'post-1'});
    };
    final dio = Dio(BaseOptions(
        baseUrl: 'https://local.test/api/v1/', validateStatus: (_) => true))
      ..httpClientAdapter = adapter;
    final api = DioMushukistanApiClient(dio: dio, tokenStore: store);
    await expectLater(
        submit(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_SESSION_UNAVAILABLE')));
    delegate.failReads = false;
    expect(await submit(api), 'post-1');
    expect(uploads, 1);
  });
  test(
      'account switch while journaling prevents dispatch and cross-account recovery',
      () async {
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    await store.write(token('A'));
    final adapter = Adapter()
      ..answer = (_) => Future.value(response({'id': 'post-1'}));
    final dio = Dio(BaseOptions(
        baseUrl: 'https://local.test/api/v1/', validateStatus: (_) => true))
      ..httpClientAdapter = adapter;
    final journal = ChangingJournal(() => store.write(token('B')));
    final api = DioMushukistanApiClient(
        dio: dio, tokenStore: store, publicationJournal: journal);
    await expectLater(
        submit(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'SESSION_CHANGED')));
    await expectLater(
        submit(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'SESSION_CHANGED')));
    expect(adapter.requests, isEmpty);
  });
  for (final stage in [
    'post_dispatch',
    'guarded_login',
    'post_reply',
    'status_dispatch',
    'status_reply',
    'detail_dispatch',
    'detail_reply',
    'refresh_dispatch',
    'refresh_reply',
    'replay_dispatch',
    'logout_then_same_account',
  ]) {
    test('publication is bound to its session during $stage', () async {
      final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
      await store.writeTokens(
          accessToken: token('A'), refreshToken: 'synthetic-refresh-A');
      final adapter = Adapter();
      final dio = Dio(BaseOptions(
          baseUrl: 'https://local.test/api/v1/', validateStatus: (_) => true))
        ..httpClientAdapter = adapter;
      bool armed = false;
      int dispatchPosts = 0;
      Future<void> change() async {
        if (stage == 'logout_then_same_account') await store.delete();
        if (stage == 'guarded_login') {
          await store.writeTokensIfRevision(store.revision,
              accessToken: token('B'), refreshToken: 'synthetic-B');
          return;
        }
        await store.writeTokens(
            accessToken: token(stage == 'logout_then_same_account' ? 'A' : 'B'),
            refreshToken: 'synthetic-new-session');
      }

      dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        if (options.method == 'POST' && options.path == 'posts') {
          dispatchPosts++;
        }
        if (armed &&
            (((stage == 'post_dispatch' || stage == 'guarded_login') &&
                    options.path == 'posts') ||
                (stage == 'logout_then_same_account' &&
                    options.path == 'posts') ||
                (stage == 'status_dispatch' &&
                    options.path.startsWith('publication-operations/')) ||
                (stage == 'detail_dispatch' &&
                    options.path.startsWith('posts/')) ||
                (stage == 'refresh_dispatch' &&
                    options.path == 'auth/refresh') ||
                (stage == 'replay_dispatch' &&
                    options.path == 'posts' &&
                    dispatchPosts == 2))) {
          armed = false;
          await change();
        }
        handler.next(options);
      }));
      int posts = 0;
      bool primeTimeout =
          stage.startsWith('status') || stage.startsWith('detail');
      adapter.answer = (options) async {
        if (options.path == 'auth/refresh') {
          if (armed && stage == 'refresh_reply') {
            armed = false;
            await change();
          }
          return response({
            'access_token': token('A', 'fresh'),
            'refresh_token': 'fresh-A'
          });
        }
        if (options.path.startsWith('publication-operations/')) {
          if (armed && stage == 'status_reply') {
            armed = false;
            await change();
          }
          return response({
            'state': 'completed',
            'target_kind': 'post',
            'target_id': 'post-1',
            'can_retry': false
          });
        }
        if (options.path.startsWith('posts/')) {
          if (armed && stage == 'detail_reply') {
            armed = false;
            await change();
          }
          return response({'id': 'post-1'});
        }
        posts++;
        if (primeTimeout) {
          primeTimeout = false;
          throw DioException(
              requestOptions: options, type: DioExceptionType.receiveTimeout);
        }
        if (posts == 1 &&
            (stage.startsWith('refresh') || stage == 'replay_dispatch')) {
          return ResponseBody.fromString(
              jsonEncode({
                'success': false,
                'error': {'code': 'UNAUTHORIZED'}
              }),
              401,
              headers: {
                Headers.contentTypeHeader: ['application/json']
              });
        }
        if (armed && stage == 'post_reply') {
          armed = false;
          await change();
        }
        return response({'id': 'post-1'});
      };
      final api = DioMushukistanApiClient(dio: dio, tokenStore: store);
      if (primeTimeout) {
        await expectLater(submit(api), throwsA(isA<MushukistanApiException>()));
      }
      armed = true;
      await expectLater(
          submit(api),
          throwsA(isA<MushukistanApiException>()
              .having((e) => e.code, 'code', 'SESSION_CHANGED')));
      for (final request
          in adapter.requests.where((r) => r.path != 'auth/refresh')) {
        expect(request.headers['Authorization'], 'Bearer ${token('A')}');
      }
      expect(
          adapter.requests
              .any((r) => r.headers['Authorization'] == 'Bearer ${token('B')}'),
          isFalse);
      if (stage.endsWith('reply')) {
        // A response arriving after the transition is never returned to the new session.
        expect(store.sessionEpoch, greaterThan(1));
      }
    });
  }
  test(
      'same-account refresh preserves the publication session and operation key',
      () async {
    final store = GuardedAuthTokenStore(InMemoryAuthTokenStore());
    await store.writeTokens(
        accessToken: token('A'), refreshToken: 'synthetic-refresh-A');
    final epoch = store.sessionEpoch;
    final adapter = Adapter();
    int posts = 0;
    adapter.answer = (o) async {
      if (o.path == 'auth/refresh') {
        return response(
            {'access_token': token('A', 'fresh'), 'refresh_token': 'fresh-A'});
      }
      if (++posts == 1) {
        return ResponseBody.fromString(
            '{"success":false,"error":{"code":"UNAUTHORIZED"}}', 401,
            headers: {
              Headers.contentTypeHeader: ['application/json']
            });
      }
      return response({'id': 'post-1'});
    };
    final dio = Dio(BaseOptions(
        baseUrl: 'https://local.test/api/v1/', validateStatus: (_) => true))
      ..httpClientAdapter = adapter;
    final api = DioMushukistanApiClient(dio: dio, tokenStore: store);
    expect(await submit(api), 'post-1');
    expect(store.sessionEpoch, epoch);
    final uploads = adapter.requests.where((r) => r.path == 'posts').toList();
    expect(
        uploads.last.headers['Authorization'], 'Bearer ${token('A', 'fresh')}');
    expect(
        uploads.map((r) => r.headers['Idempotency-Key']).toSet(), hasLength(1));
  });
}
