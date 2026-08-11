abstract class AuthTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class InMemoryAuthTokenStore implements AuthTokenStore {
  String? _token;

  @override
  Future<void> delete() async {
    _token = null;
  }

  @override
  Future<String?> read() async {
    return _token;
  }

  @override
  Future<void> write(String token) async {
    _token = token;
  }
}
