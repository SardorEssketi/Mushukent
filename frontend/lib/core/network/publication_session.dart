import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'api_error.dart';
import 'publication_retry.dart';

const publicationSessionChanged = MushukistanApiException(
  kind: ApiFailureKind.unauthorized,
  code: 'SESSION_CHANGED',
  message:
      'Session changed during publication. Sign in to the original account to recover it.',
);

/// Lives for one call, including reconciliation and token-refresh replay.
/// Refresh changes credentials; login/logout changes the session epoch.
class PublicationSession {
  PublicationSession(this.store)
      : epoch = store is GuardedAuthTokenStore ? store.sessionEpoch : null {
    if (store case final GuardedAuthTokenStore guarded) {
      _changes = guarded.sessionChanges.listen((_) {
        cancelToken.cancel(publicationSessionChanged);
      });
    }
  }

  final AuthTokenStore store;
  final int? epoch;
  final cancelToken = CancelToken();
  StreamSubscription<void>? _changes;
  String? _scope;
  String get scope => _scope!;

  Future<String> credentials() async {
    final token = await store.read();
    final current = publicationScope(token);
    if (cancelToken.isCancelled ||
        (store is GuardedAuthTokenStore &&
            (store as GuardedAuthTokenStore).sessionEpoch != epoch) ||
        (_scope != null && current != _scope)) {
      throw publicationSessionChanged;
    }
    if (token == null || token.isEmpty) {
      throw const MushukistanApiException(
        kind: ApiFailureKind.unauthorized,
        code: 'UNAUTHORIZED',
        message: 'Sign in before publishing.',
      );
    }
    _scope ??= current;
    return token;
  }

  Future<void> dispose() async => _changes?.cancel();
}
