import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_store.dart';

class FlutterSecureTokenStore implements AuthTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'mushukistan_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete() {
    return _storage.delete(key: _tokenKey);
  }

  @override
  Future<String?> read() {
    return _storage.read(key: _tokenKey);
  }

  @override
  Future<void> write(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }
}
