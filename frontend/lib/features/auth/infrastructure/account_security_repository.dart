import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final accountSecurityRepositoryProvider =
    Provider<AccountSecurityRepository>((ref) {
  return AccountSecurityRepository(ref.watch(apiClientProvider));
});

class SignInMethods {
  const SignInMethods(
      {required this.hasPassword, required this.googleConnected});

  final bool hasPassword;
  final bool googleConnected;

  factory SignInMethods.fromJson(Object? json) {
    final map = (json as Map).cast<String, Object?>();
    return SignInMethods(
      hasPassword: map['has_password'] == true,
      googleConnected: map['google_connected'] == true,
    );
  }
}

class AccountSecurityRepository {
  const AccountSecurityRepository(this._client);

  final MushukistanApiClient _client;

  Future<SignInMethods> getMethods() => _client
      .get<SignInMethods>('auth/methods', decoder: SignInMethods.fromJson);

  Future<void> setPassword(String password, String confirmation) async {
    await _client.postJson<Object?>(
      'auth/set-password',
      body: {'new_password': password, 'confirm_password': confirmation},
      decoder: (_) => null,
    );
  }

  Future<void> changePassword(
      String current, String password, String confirmation) async {
    await _client.postJson<Object?>(
      'auth/change-password',
      body: {
        'current_password': current,
        'new_password': password,
        'confirm_password': confirmation,
      },
      decoder: (_) => null,
    );
  }

  Future<void> connectGoogle(String idToken) async {
    await _client.postJson<Object?>(
      'auth/connect-google',
      body: {'id_token': idToken},
      decoder: (_) => null,
    );
  }
}
