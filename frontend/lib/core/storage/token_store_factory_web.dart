import 'package:web/web.dart' as web;

import 'token_store.dart';

class WebLocalTokenStore implements AuthTokenStore {
  static const _tokenKey = 'mushukistan_access_token';

  @override
  Future<void> delete() async {
    web.window.localStorage.removeItem(_tokenKey);
  }

  @override
  Future<String?> read() async {
    return web.window.localStorage.getItem(_tokenKey);
  }

  @override
  Future<void> write(String token) async {
    web.window.localStorage.setItem(_tokenKey, token);
  }
}

AuthTokenStore createPlatformAuthTokenStore() {
  return WebLocalTokenStore();
}
