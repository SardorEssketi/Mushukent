import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_error.dart';
import 'publication_lock_stub.dart'
    if (dart.library.js_interop) 'publication_lock_web.dart' as coordination;

String newPublicationKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

abstract class PublicationJournal {
  Future<T> coordinate<T>(String id, Future<T> Function() action) =>
      coordination.withPublicationLock(id, action);
  Future<PublicationRecord?> read(String id);
  Future<void> write(String id, PublicationRecord record);
}

class PublicationRecord {
  const PublicationRecord(this.owner, this.fingerprint);
  final String owner;
  final String fingerprint;
  String encode() => jsonEncode({'owner': owner, 'fingerprint': fingerprint});
  factory PublicationRecord.decode(String value) {
    final data = jsonDecode(value) as Map;
    return PublicationRecord(
        data['owner'] as String, data['fingerprint'] as String);
  }
}

String publicationOwner(String scope) =>
    sha256.convert(utf8.encode(scope)).toString();

class MemoryPublicationJournal extends PublicationJournal {
  final _records = <String, PublicationRecord>{};
  @override
  Future<PublicationRecord?> read(String id) async => _records[id];
  @override
  Future<void> write(String id, PublicationRecord record) async {
    _records[id] = record;
  }
}

class PreferencesPublicationJournal extends PublicationJournal {
  String _storageKey(String id) => 'publication_attempt_v2.$id';
  @override
  Future<PublicationRecord?> read(String id) async {
    final preferences = await SharedPreferences.getInstance();
    // Another engine/tab may have written since this instance loaded its cache.
    // coordinate() holds the process/browser lock across this read and binding.
    await preferences.reload();
    final value = preferences.getString(_storageKey(id));
    return value == null ? null : PublicationRecord.decode(value);
  }

  @override
  Future<void> write(String id, PublicationRecord record) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(_storageKey(id), record.encode())) {
      throw StateError('Could not preserve publication operation');
    }
  }
}

String publicationScope(String? token) {
  if (token == null) return 'unauthenticated';
  try {
    final payload = jsonDecode(utf8
        .decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))));
    if (payload is Map && payload['sub'] is String) {
      return payload['sub'] as String;
    }
  } catch (_) {/* Opaque test tokens remain scoped without being persisted. */}
  return sha256.convert(utf8.encode(token)).toString();
}

Future<String> publicationFingerprint(String path, FormData form) async {
  final fields = [...form.fields]..sort((a, b) => a.key.compareTo(b.key));
  final files = <Object>[];
  for (final entry in form.files) {
    final digest = await sha256.bind(entry.value.clone().finalize()).first;
    files.add([
      entry.key,
      entry.value.contentType?.toString(),
      entry.value.length,
      digest.toString()
    ]);
  }
  return sha256
      .convert(utf8.encode(jsonEncode([
        path,
        fields.map((e) => [e.key, e.value]).toList(),
        files
      ])))
      .toString();
}

bool publicationOutcomeUncertain(Object error) =>
    error is! MushukistanApiException ||
    (error.kind == ApiFailureKind.network ||
        error.kind == ApiFailureKind.server ||
        error.kind == ApiFailureKind.parse ||
        const {
          'PUBLICATION_IN_PROGRESS',
          'PUBLICATION_OUTCOME_UNKNOWN',
          'PUBLICATION_KEY_CONFLICT',
          'PUBLICATION_ID_REQUIRED',
          'PUBLICATION_COORDINATION_UNAVAILABLE',
          'PUBLICATION_JOURNAL_UNAVAILABLE',
          'SESSION_CHANGED'
        }.contains(error.code));

void logPublicationFailure(String stage, Object error, {String? key}) {
  debugPrint(
      'Publication failure: stage=$stage operation=${key ?? "unassigned"} type=${error.runtimeType}');
}
