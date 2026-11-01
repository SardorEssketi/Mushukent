import 'dart:convert';

import 'package:web/web.dart' as web;

import 'token_store.dart';

class WebLocalTokenStore implements AuthTokenStore, ExternalAuthSessionChanges {
  static const _tokenKey = 'mushukistan_access_token';
  static const _refreshTokenKey = 'mushukistan_refresh_token';
  String? _memoryAccessToken;
  String? _memoryRefreshToken;

  String? _account(String? token) {
    if (token == null) return null;
    try {
      return (jsonDecode(utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1]))))
          as Map)['sub'] as String;
    } catch (_) {
      return token;
    }
  }

  @override
  Stream<void> get externalSessionChanges =>
      web.EventStreamProviders.storageEvent
          .forTarget(web.window)
          .where((event) =>
              event.key == null ||
              event.key == _tokenKey ||
              event.key == _refreshTokenKey)
          .map((event) {
            _memoryAccessToken = null;
            _memoryRefreshToken = null;
            return event;
          })
          .where((event) =>
              event.key == null ||
              (event.key == _tokenKey &&
                  _account(event.oldValue) != _account(event.newValue)))
          .map((_) {});

  @override
  Future<void> delete() async {
    _memoryAccessToken = null;
    _memoryRefreshToken = null;
    try {
      web.window.localStorage.removeItem(_tokenKey);
      web.window.localStorage.removeItem(_refreshTokenKey);
    } on Object {
      // Safari privacy settings can make localStorage unavailable. The
      // in-memory session is still cleared and public browsing remains usable.
    }
  }

  @override
  Future<String?> read() async {
    try {
      return web.window.localStorage.getItem(_tokenKey) ?? _memoryAccessToken;
    } on Object {
      return _memoryAccessToken;
    }
  }

  @override
  Future<String?> readRefreshToken() async {
    try {
      return web.window.localStorage.getItem(_refreshTokenKey) ??
          _memoryRefreshToken;
    } on Object {
      return _memoryRefreshToken;
    }
  }

  @override
  Future<void> write(String token) async {
    _memoryAccessToken = token;
    try {
      web.window.localStorage.setItem(_tokenKey, token);
    } on Object {
      // Keep the session in memory when persistent browser storage is blocked.
    }
  }

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    _memoryAccessToken = accessToken;
    _memoryRefreshToken =
        refreshToken?.trim().isEmpty == true ? null : refreshToken;
    try {
      web.window.localStorage.setItem(_tokenKey, accessToken);
      if (_memoryRefreshToken == null) {
        web.window.localStorage.removeItem(_refreshTokenKey);
      } else {
        web.window.localStorage.setItem(
          _refreshTokenKey,
          _memoryRefreshToken!,
        );
      }
    } on Object {
      // Keep the session in memory when persistent browser storage is blocked.
    }
  }
}

AuthTokenStore createPlatformAuthTokenStore() {
  return WebLocalTokenStore();
}
