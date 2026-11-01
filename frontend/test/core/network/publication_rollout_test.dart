import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';
import 'package:mushukistan_frontend/core/network/publication_retry.dart';

import 'publication_retry_test.dart' as support;

/// Models an old node that accepted a POST without recording an operation.
/// This deliberately exposes the deployment hazard; it is not an application fix.
class MixedBackends extends support.Server {
  bool legacyOnly = false;
  bool missingOperation = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    if (options.path.startsWith('publication-operations/') &&
        (legacyOnly || missingOperation)) {
      return ResponseBody.fromString(
          jsonEncode({
            'success': false,
            'error': {
              'code':
                  legacyOnly ? 'HTTP_ERROR' : 'PUBLICATION_OPERATION_NOT_FOUND',
              'message': 'Not found',
            }
          }),
          404,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    return super.fetch(options, stream, cancelFuture);
  }
}

void main() {
  test(
      'mixed nodes can duplicate an old-node commit: backend-first gate is required',
      () async {
    final server = MixedBackends()..missingOperation = true;
    final api = await support.client(server, MemoryPublicationJournal());
    await expectLater(
        support.publish(api), throwsA(isA<MushukistanApiException>()));
    expect(await support.publish(api), 'post-1');
    // Old-node commit (lost response), then new-node creation: same key, no old ledger record.
    expect(server.posts, [support.operationId, support.operationId]);
  });

  test(
      'rollback without status support blocks retries until supported service returns',
      () async {
    final server = MixedBackends();
    final journal = MemoryPublicationJournal();
    final api = await support.client(server, journal);
    await expectLater(
        support.publish(api), throwsA(isA<MushukistanApiException>()));
    server.legacyOnly = true;
    await expectLater(
        support.publish(api),
        throwsA(isA<MushukistanApiException>()
            .having((e) => e.code, 'code', 'PUBLICATION_OUTCOME_UNKNOWN')));
    expect(server.posts, hasLength(1));
    server.legacyOnly = false;
    expect(
        await support.publish(await support.client(server, journal)), 'post-1');
    expect(server.posts, hasLength(1));
  });
}
