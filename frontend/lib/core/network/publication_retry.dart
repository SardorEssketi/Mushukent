import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_error.dart';

String newPublicationKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

abstract class PublicationJournal {
  Future<String?> read(String scope, String fingerprint);
  Future<void> write(String scope, String fingerprint, String key);
  Future<void> remove(String scope, String fingerprint);
}

class MemoryPublicationJournal implements PublicationJournal {
  final _keys = <String, String>{};
  @override
  Future<String?> read(String scope, String fingerprint) async =>
      _keys['$scope:$fingerprint'];
  @override
  Future<void> write(String scope, String fingerprint, String key) async {
    _keys['$scope:$fingerprint'] = key;
  }

  @override
  Future<void> remove(String scope, String fingerprint) async {
    _keys.remove('$scope:$fingerprint');
  }
}

class PreferencesPublicationJournal implements PublicationJournal {
  String _storageKey(String scope, String fingerprint) =>
      'publication_attempt_v1.${sha256.convert(utf8.encode(scope))}.$fingerprint';
  @override
  Future<String?> read(String scope, String fingerprint) async =>
      (await SharedPreferences.getInstance())
          .getString(_storageKey(scope, fingerprint));
  @override
  Future<void> write(String scope, String fingerprint, String key) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(_storageKey(scope, fingerprint), key)) {
      throw StateError('Could not preserve publication operation');
    }
  }

  @override
  Future<void> remove(String scope, String fingerprint) async {
    await (await SharedPreferences.getInstance())
        .remove(_storageKey(scope, fingerprint));
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
    error is MushukistanApiException &&
    (error.kind == ApiFailureKind.network ||
        error.kind == ApiFailureKind.server ||
        error.kind == ApiFailureKind.parse ||
        const {
          'PUBLICATION_IN_PROGRESS',
          'PUBLICATION_OUTCOME_UNKNOWN',
          'PUBLICATION_KEY_CONFLICT',
          'SESSION_CHANGED'
        }.contains(error.code));

void logPublicationFailure(String stage, Object error, {String? key}) {
  debugPrint(
      'Publication failure: stage=$stage operation=${key ?? "unassigned"} type=${error.runtimeType}');
}
