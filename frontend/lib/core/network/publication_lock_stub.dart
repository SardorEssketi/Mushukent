import 'dart:async';

// Shared by every journal/client in the application isolate, not instance-local.
final _pending = <String, Future<void>>{};

Future<T> withPublicationLock<T>(String id, Future<T> Function() action) async {
  final previous = _pending[id] ?? Future<void>.value();
  final release = Completer<void>();
  _pending[id] = release.future;
  await previous;
  try {
    return await action();
  } finally {
    release.complete();
    if (identical(_pending[id], release.future)) _pending.remove(id);
  }
}
