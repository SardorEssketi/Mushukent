import 'package:web/web.dart' as web;

import 'token_store.dart';

class WebLocalTokenStore implements AuthTokenStore {
  static const _tokenKey = 'mushukistan_access_token';
  static const _refreshTokenKey = 'mushukistan_refresh_token';

  @override
  Future<void> delete() async {
    web.window.localStorage.removeItem(_tokenKey);
    web.window.localStorage.removeItem(_refreshTokenKey);
  }

  @override
  Future<String?> read() async {
    return web.window.localStorage.getItem(_tokenKey);
  }

  @override
  Future<String?> readRefreshToken() async {
    return web.window.localStorage.getItem(_refreshTokenKey);
  }

  @override
  Future<void> write(String token) async {
    web.window.localStorage.setItem(_tokenKey, token);
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    web.window.localStorage.setItem(_tokenKey, accessToken);
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      web.window.localStorage.removeItem(_refreshTokenKey);
    } else {
      web.window.localStorage.setItem(_refreshTokenKey, refreshToken);
    }
  }
}

AuthTokenStore createPlatformAuthTokenStore() {
  return WebLocalTokenStore();
}
