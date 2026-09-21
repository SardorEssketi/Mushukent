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
