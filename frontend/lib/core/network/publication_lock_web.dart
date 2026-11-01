import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'api_error.dart';

@JS('navigator.locks')
external web.LockManager? get _locks;

/// Exclusive same-origin browser lock; it also spans distinct Flutter tabs.
/// Never emulate this using a cached localStorage flag or expiring lease.
Future<T> withPublicationLock<T>(String id, Future<T> Function() action) async {
  final manager = _locks;
  if (manager == null) {
    throw const MushukistanApiException(
      kind: ApiFailureKind.unknown,
      code: 'PUBLICATION_COORDINATION_UNAVAILABLE',
      message:
          'This browser cannot safely coordinate publication retries. Use a supported browser or the Android app.',
    );
  }
  late T result;
  Object? failure;
  StackTrace? trace;
  await manager
      .request(
          'mushukistan-publication-v2:$id',
          ((web.Lock lock) {
            return (() async {
              try {
                result = await action();
              } catch (error, stack) {
                failure = error;
                trace = stack;
              }
              return null;
            })()
                .toJS;
          }).toJS)
      .toDart;
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result;
}
