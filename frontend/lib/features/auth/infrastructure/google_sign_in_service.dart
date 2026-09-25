import 'dart:developer' as developer;

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
  Future<void>? _initialization;
  bool _authenticating = false;

  @override
  Future<String> authenticate() async {
    if (_authenticating) {
      throw const GoogleSignInFlowException(
          'Google sign-in is already in progress.');
    }
    if (!_environment.isGoogleSignInConfigured) {
      throw const GoogleSignInFlowException(
        'Google sign-in is not configured for this build.',
      );
    }

    _authenticating = true;
    try {
      await _ensureInitialized();

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const GoogleSignInFlowException(
          'Google sign-in is not supported on this platform in the current app flow.',
        );
      }

      final user = await GoogleSignIn.instance.authenticate();
      final idToken = user.authentication.idToken;
      if (idToken == null || idToken.trim().isEmpty) {
        throw const GoogleSignInFlowException(
          'Google sign-in did not return an ID token.',
        );
      }
      return idToken;
    } on GoogleSignInFlowException {
      rethrow;
    } on GoogleSignInException catch (error) {
      developer.log(
        'Google Sign-In failed: code=${error.code}',
        name: 'Mushukistan.GoogleSignIn',
      );
      throw GoogleSignInFlowException(
        error.description?.trim().isNotEmpty == true
            ? error.description!.trim()
            : 'Google sign-in failed.',
      );
    } on Object {
      developer.log(
        'Google Sign-In initialization failed.',
        name: 'Mushukistan.GoogleSignIn',
      );
      throw const GoogleSignInFlowException(
        'Google sign-in could not be initialized for this build.',
      );
    } finally {
      _authenticating = false;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await (_initialization ??= GoogleSignIn.instance.initialize(
      clientId: _environment.googleClientId,
      serverClientId: _environment.googleServerClientId,
    ));
    _initialized = true;
  }
}
