import 'dart:async';

abstract class AuthTokenStore {
  Future<String?> read();
  Future<String?> readRefreshToken();
  Future<void> write(String token);
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  });
  Future<void> delete();
}

abstract interface class ExternalAuthSessionChanges {
  Stream<void> get externalSessionChanges;
}

/// Serializes credential mutations and rejects responses from an older session.
class GuardedAuthTokenStore implements AuthTokenStore {
  GuardedAuthTokenStore(this._delegate) {
    if (_delegate case final ExternalAuthSessionChanges external) {
      _externalChanges = external.externalSessionChanges
          .listen((_) => invalidatePendingWrites());
    }
  }

  final AuthTokenStore _delegate;
  StreamSubscription<void>? _externalChanges;
  Future<void> dispose() async {
    await _externalChanges?.cancel();
  }

  Future<void> _pending = Future<void>.value();
  int _revision = 0;
  int _sessionEpoch = 0;
  final _sessionChanges = StreamController<void>.broadcast(sync: true);
  final StreamController<void> _invalidations =
      StreamController<void>.broadcast(sync: true);

  int get revision => _revision;
  int get sessionEpoch => _sessionEpoch;
  Stream<void> get sessionChanges => _sessionChanges.stream;
  Stream<void> get invalidations => _invalidations.stream;

  void _changeSession() {
    _sessionEpoch++;
    _sessionChanges.add(null);
  }

  void invalidatePendingWrites() {
    _revision++;
    _changeSession();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<String?> read() => _serial(_delegate.read);

  @override
  Future<String?> readRefreshToken() => _serial(_delegate.readRefreshToken);

  @override
  Future<void> write(String token) {
    _revision++;
    _changeSession();
    return _serial(() => _delegate.write(token));
  }

  @override
  Future<void> writeTokens(
      {required String accessToken, required String? refreshToken}) {
    _revision++;
    _changeSession();
    return _serial(() => _delegate.writeTokens(
        accessToken: accessToken, refreshToken: refreshToken));
  }

  Future<bool> writeTokensIfRevision(
    int expected, {
    required String accessToken,
    required String? refreshToken,
    bool newSession = true,
  }) {
    if (_revision != expected) return Future<bool>.value(false);
    _revision++;
    if (newSession) _changeSession();
    return _serial(() async {
      await _delegate.writeTokens(
          accessToken: accessToken, refreshToken: refreshToken);
      return true;
    });
  }

  Future<bool> deleteIfRevision(int expected) {
    if (_revision != expected) return Future<bool>.value(false);
    _revision++;
    _changeSession();
    return _serial(() async {
      await _delegate.delete();
      _invalidations.add(null);
      return true;
    });
  }

  @override
  Future<void> delete() {
    _revision++;
    _changeSession();
    return _serial(() async {
      await _delegate.delete();
      _invalidations.add(null);
    });
  }
}

class InMemoryAuthTokenStore implements AuthTokenStore {
  String? _token;
  String? _refreshToken;

  @override
  Future<void> delete() async {
    _token = null;
    _refreshToken = null;
  }

  @override
  Future<String?> read() async {
    return _token;
  }

  @override
  Future<String?> readRefreshToken() async {
    return _refreshToken;
  }

  @override
  Future<void> write(String token) async {
    _token = token;
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    _token = accessToken;
    _refreshToken = refreshToken;
  }
}
