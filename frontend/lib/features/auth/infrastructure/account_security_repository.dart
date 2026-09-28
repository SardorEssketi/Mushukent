import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final accountSecurityRepositoryProvider =
    Provider<AccountSecurityRepository>((ref) {
  return AccountSecurityRepository(ref.watch(apiClientProvider));
});

class SignInMethods {
  const SignInMethods({required this.hasPassword, required this.emailVerified});

  final bool hasPassword;
  final bool emailVerified;

  factory SignInMethods.fromJson(Object? json) {
    final map = (json as Map).cast<String, Object?>();
    return SignInMethods(
      hasPassword: map['has_password'] == true,
      emailVerified: map['email_verified'] == true,
    );
  }
}

class AccountSecurityRepository {
  const AccountSecurityRepository(this._client);

  final MushukistanApiClient _client;

  Future<SignInMethods> getMethods() => _client
      .get<SignInMethods>('auth/methods', decoder: SignInMethods.fromJson);

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
}
