import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_store.dart';

class FlutterSecureTokenStore implements AuthTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'mushukistan_access_token';
  static const _refreshTokenKey = 'mushukistan_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete() {
    return Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]).then((_) {});
  }

  @override
  Future<String?> read() {
    return _storage.read(key: _tokenKey);
  }

  @override
  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  @override
  Future<void> write(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    await _storage.write(key: _tokenKey, value: accessToken);
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      await _storage.delete(key: _refreshTokenKey);
    } else {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }
}
