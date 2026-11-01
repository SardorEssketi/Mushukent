import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/publication_retry.dart';
import 'package:mushukistan_frontend/core/storage/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

FormData photoForm() => FormData.fromMap({
      'description': 'Disposable test',
      'photos': [
        MultipartFile.fromBytes([255, 216, 255, 217], filename: 'test.jpg')
      ],
    });

class Server implements HttpClientAdapter {
  final posts = <String>[];
  final requests = <RequestOptions>[];
  String state = 'completed';
  bool failStatus = false;
  bool failFirst = true;
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (stream != null) await stream.drain<void>();
    Object data;
    if (options.method == 'POST') {
      posts.add(options.headers['Idempotency-Key'] as String);
      if (gate != null) await gate!.future;
      if (failFirst && posts.length == 1) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.receiveTimeout);
      }
      data = {'id': 'post-1'};
    } else if (options.path.startsWith('publication-operations/')) {
      if (failStatus) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionError);
      }
      data = {
        'state': state,
        'target_kind': 'post',
        'target_id': 'post-1',
        'can_retry': state == 'failed'
      };
    } else {
      data = {'id': 'post-1'};
    }
    return ResponseBody.fromString(
        jsonEncode({'success': true, 'data': data}), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

Future<DioMushukistanApiClient> client(
    Server server, PublicationJournal journal,
    {String user = 'owner'}) async {
  final tokens = InMemoryAuthTokenStore();
  final payload = base64Url.encode(utf8.encode(jsonEncode({'sub': user})));
  await tokens.write('header.$payload.signature');
  final dio = Dio(BaseOptions(
      baseUrl: 'https://local.test/api/v1/', validateStatus: (_) => true))
    ..httpClientAdapter = server;
  return DioMushukistanApiClient(
      dio: dio, tokenStore: tokens, publicationJournal: journal);
}

Future<String> publish(DioMushukistanApiClient api) =>
    api.postMultipart('posts',
        formData: photoForm(),
        decoder: (json) => (json as Map)['id'] as String);

class FailingJournal extends MemoryPublicationJournal {
  bool failWrite = false;
  bool failRemove = false;
  @override
  Future<void> write(String scope, String fingerprint, String key) async {
    if (failWrite) throw StateError('Test journal unavailable');
    await super.write(scope, fingerprint, key);
  }

  @override
  Future<void> remove(String scope, String fingerprint) async {
    if (failRemove) throw StateError('Test clear unavailable');
    await super.remove(scope, fingerprint);
  }
}

void main() {
  test(
      'journal write failure prevents transport; clear failure preserves success',
      () async {
    final server = Server()..failFirst = false;
    final journal = FailingJournal()..failWrite = true;
    final api = await client(server, journal);
    await expectLater(
        publish(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_JOURNAL_UNAVAILABLE')));
    expect(server.posts, isEmpty);
    journal.failWrite = false;
    journal.failRemove = true;
    expect(await publish(api), 'post-1');
    expect(await publish(api), 'post-1');
    expect(server.posts, hasLength(1));
  });
  test(
      'lost response is reconciled after client recreation without a second upload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final server = Server();
    final first = await client(server, PreferencesPublicationJournal());
    await expectLater(publish(first), throwsA(isA<MushukistanApiException>()));
    final recovered = await client(server, PreferencesPublicationJournal());
    expect(await publish(recovered), 'post-1');
    expect(server.posts, hasLength(1));
    expect(server.requests.map((r) => r.method), ['POST', 'GET', 'GET']);
  });

  test('unknown or pending status never resends photos', () async {
    final server = Server();
    final api = await client(server, MemoryPublicationJournal());
    await expectLater(publish(api), throwsA(isA<MushukistanApiException>()));
    server.failStatus = true;
    await expectLater(
        publish(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_OUTCOME_UNKNOWN')));
    server.failStatus = false;
    server.state = 'pending';
    await expectLater(
        publish(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_IN_PROGRESS')));
    expect(server.posts, hasLength(1));
  });

  test('definitely failed operation reuses its original key', () async {
    final server = Server()..state = 'failed';
    final api = await client(server, MemoryPublicationJournal());
    await expectLater(publish(api), throwsA(isA<MushukistanApiException>()));
    expect(await publish(api), 'post-1');
    expect(server.posts, hasLength(2));
    expect(server.posts[0], server.posts[1]);
  });

  test('operation journals are isolated by account', () async {
    final journal = MemoryPublicationJournal();
    final server = Server();
    await expectLater(publish(await client(server, journal)),
        throwsA(isA<MushukistanApiException>()));
    expect(
        await publish(await client(server, journal, user: 'other')), 'post-1');
    expect(server.requests.map((r) => r.method), ['POST', 'POST']);
    expect(server.posts.toSet(), hasLength(2));
  });

  test('concurrent identical submissions share one transport attempt',
      () async {
    final server = Server()
      ..failFirst = false
      ..gate = Completer<void>();
    final api = await client(server, MemoryPublicationJournal());
    final first = publish(api);
    final second = publish(api);
    while (server.posts.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    server.gate!.complete();
    expect(await Future.wait([first, second]), ['post-1', 'post-1']);
    expect(server.posts, hasLength(1));
  });
}
