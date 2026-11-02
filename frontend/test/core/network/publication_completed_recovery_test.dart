import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/api_client.dart';
import 'package:mushukistan_frontend/core/network/publication_retry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'publication_retry_test.dart' as support;

class RemovedPublicationServer extends support.Server {
  RemovedPublicationServer(this.kind, this.detailStatus);
  final String kind;
  final int detailStatus;
  bool missingStatus = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    if (options.method == 'POST') {
      return super.fetch(options, stream, cancelFuture);
    }
    requests.add(options);
    if (options.path.startsWith('publication-operations/')) {
      if (failStatus) {
        return reply(503, {
          'success': false,
          'error': {'code': 'UNAVAILABLE', 'message': 'Unavailable'}
        });
      }
      if (missingStatus) {
        return reply(404, {
          'success': false,
          'error': {
            'code': 'PUBLICATION_OPERATION_NOT_FOUND',
            'message': 'Absent'
          }
        });
      }
      return reply(200, {
        'success': true,
        'data': {
          'state': state,
          'target_kind': kind,
          'target_id': '11111111-2222-4333-8444-555555555555',
          'can_retry': state == 'failed',
        }
      });
    }
    return reply(detailStatus, {
      'success': false,
      'error': {
        'code': detailStatus == 404 ? 'POST_NOT_FOUND' : 'FORBIDDEN',
        'message': 'SYNTHETIC_RESTRICTED_MODERATION_DETAIL'
      }
    });
  }

  ResponseBody reply(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
}

void main() {
  test(
      'completion is terminal, distinct from uncertainty and validation rejection',
      () {
    const terminal = PublicationCompletedUnavailable();
    expect(publicationOutcomeUncertain(terminal), isFalse);
    expect(publicationAllowsReplacement(terminal), isFalse);
    expect(terminal.isSessionInvalid, isFalse);
    expect(terminal.isRetryable, isFalse);
  });
  test('completion journal write failure blocks before detail/retry', () async {
    final server = RemovedPublicationServer('post', 404);
    final journal = support.FailingJournal();
    final api = await support.client(server, journal);
    await expectLater(
        support.publish(api), throwsA(isA<MushukistanApiException>()));
    journal.failWrite = true;
    await expectLater(
        support.publish(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_JOURNAL_UNAVAILABLE')));
    expect(server.posts, [support.operationId]);
    expect(server.requests.where((r) => r.path.startsWith('posts/')), isEmpty);
    journal.failWrite = false;
    await expectLater(
        support.publish(api), throwsA(isA<PublicationCompletedUnavailable>()));
    expect(server.posts, [support.operationId]);
  });
  for (final (type, path, kind) in [
    ('observation', 'posts', 'post'),
    ('needs_help', 'posts', 'post'),
    ('lost_pet', 'lost-pets', 'lost_pet'),
    ('adoption', 'adoption-posts', 'adoption_post'),
  ]) {
    Future<Object?> submitWith(DioMushukistanApiClient api) =>
        api.postMultipart<Object?>(path,
            publicationId: support.operationId,
            formData: FormData.fromMap({'kind': type}),
            decoder: (data) => data);
    test('$type: unavailable status never permits creation', () async {
      SharedPreferences.setMockInitialValues({});
      final server = RemovedPublicationServer(kind, 404);
      var api = await support.client(server, PreferencesPublicationJournal());
      await expectLater(
          submitWith(api), throwsA(isA<MushukistanApiException>()));
      server.failStatus = true;
      for (var i = 0; i < 2; i++) {
        api = await support.client(server, PreferencesPublicationJournal());
        await expectLater(
            submitWith(api),
            throwsA(isA<MushukistanApiException>()
                .having((e) => e.code, 'code', 'PUBLICATION_OUTCOME_UNKNOWN')));
      }
      expect(server.posts, [support.operationId]);
    });
    test('$type: temporary detail failure preserves authoritative completion',
        () async {
      SharedPreferences.setMockInitialValues({});
      final server = RemovedPublicationServer(kind, 503);
      var api = await support.client(server, PreferencesPublicationJournal());
      await expectLater(
          submitWith(api), throwsA(isA<MushukistanApiException>()));
      await expectLater(
          submitWith(api), throwsA(isA<MushukistanApiException>()));
      server.missingStatus = true;
      api = await support.client(server, PreferencesPublicationJournal());
      await expectLater(
          submitWith(api), throwsA(isA<MushukistanApiException>()));
      expect(server.posts, [support.operationId]);
      expect(
          server.requests
              .where((r) => r.path.startsWith('publication-operations/')),
          hasLength(1));
    });
    for (final detailStatus in [404, 403, 401, 422]) {
      test(
          '$type: completed with detail $detailStatus is terminal across clients',
          () async {
        SharedPreferences.setMockInitialValues({});
        final server = RemovedPublicationServer(kind, detailStatus);
        var api = await support.client(server, PreferencesPublicationJournal());
        Future<Object?> submit() => api.postMultipart(path,
            publicationId: support.operationId,
            formData: FormData.fromMap({
              'kind': type,
              'photos': MultipartFile.fromBytes([255, 216, 255, 217],
                  filename: 'synthetic.jpg')
            }),
            decoder: (data) => data);
        // The server accepted the POST, but its acknowledgement was lost.
        await expectLater(submit(), throwsA(isA<MushukistanApiException>()));
        final before =
            await PreferencesPublicationJournal().read(support.operationId);
        // Content is now removed/inaccessible before reconciliation.
        api = await support.client(server, PreferencesPublicationJournal());
        final terminal = isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_COMPLETED_UNAVAILABLE')
            .having((e) => e.message.contains('SYNTHETIC_RESTRICTED'),
                'privacy', false);
        await expectLater(submit(), throwsA(terminal));
        // Remembered completion forbids POST even if status subsequently vanishes.
        server.missingStatus = true;
        for (var i = 0; i < 2; i++) {
          api = await support.client(server, PreferencesPublicationJournal());
          await expectLater(submit(), throwsA(terminal));
        }
        final after =
            await PreferencesPublicationJournal().read(support.operationId);
        expect(
            after?.completedTargetId, '11111111-2222-4333-8444-555555555555');
        expect(after?.owner, before?.owner);
        expect(after?.fingerprint, before?.fingerprint);
        expect(server.posts, [support.operationId]);
        expect(
            server.requests
                .where((r) => r.path.startsWith('publication-operations/')),
            hasLength(1));
        // Account B cannot use account A's completion or read its detail.
        final count = server.requests.length;
        api = await support.client(server, PreferencesPublicationJournal(),
            user: 'other');
        await expectLater(
            submit(),
            throwsA(isA<MushukistanApiException>()
                .having((e) => e.code, 'code', 'SESSION_CHANGED')));
        expect(server.requests, hasLength(count));
      });
    }
  }
}
