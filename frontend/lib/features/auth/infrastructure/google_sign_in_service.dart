import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_environment.dart';

class GoogleSignInFlowException implements Exception {
  const GoogleSignInFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class GoogleIdentityTokenProvider {
  Future<String> authenticate();
}

class GoogleSignInService implements GoogleIdentityTokenProvider {
  GoogleSignInService(this._environment);

  final AppEnvironment _environment;
  bool _initialized = false;

  @override
  Future<String> authenticate() async {
    if (!_environment.isGoogleSignInConfigured) {
      throw const GoogleSignInFlowException(
        'Google sign-in is not configured for this build.',
      );
    }

    await _ensureInitialized();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const GoogleSignInFlowException(
        'Google sign-in is not supported on this platform in the current app flow.',
      );
    }

    try {
      final user = await GoogleSignIn.instance.authenticate();
      final idToken = user.authentication.idToken;
      if (idToken == null || idToken.trim().isEmpty) {
        throw const GoogleSignInFlowException(
          'Google sign-in did not return an ID token.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (error) {
      throw GoogleSignInFlowException(
        error.description?.trim().isNotEmpty == true
            ? error.description!.trim()
            : 'Google sign-in failed.',
      );
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await GoogleSignIn.instance.initialize(
      clientId: _environment.googleClientId,
      serverClientId: _environment.googleServerClientId,
    );
    _initialized = true;
  }
}
