import 'dart:developer' as developer;

import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_environment.dart';

/// Why the native Google flow ended without an ID token.
enum GoogleSignInFailure {
  /// The person closed or backed out of the Google sheet: not an error.
  cancelled,

  /// The build has no (or a rejected) Google client configuration.
  notConfigured,

  /// The account picker cannot be shown on this device right now.
  unavailable,

  /// Anything else; worth another try.
  failed,
}

class GoogleSignInFlowException implements Exception {
  const GoogleSignInFlowException(
    this.message, {
    this.failure = GoogleSignInFailure.failed,
  });

  /// Developer description for logs; never shown as is (it can be a raw
  /// provider message such as "[16] Cancelled by user.").
  final String message;
  final GoogleSignInFailure failure;

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
      // A second tap while the sheet is open: nothing to report.
      throw const GoogleSignInFlowException(
        'Google sign-in is already in progress.',
        failure: GoogleSignInFailure.cancelled,
      );
    }
    if (!_environment.isGoogleSignInConfigured) {
      throw const GoogleSignInFlowException(
        'Google sign-in is not configured for this build.',
        failure: GoogleSignInFailure.notConfigured,
      );
    }

    _authenticating = true;
    try {
      await _ensureInitialized();

      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const GoogleSignInFlowException(
          'Google sign-in is not supported on this platform in the current app flow.',
          failure: GoogleSignInFailure.unavailable,
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
        failure: googleSignInFailureFor(error.code),
      );
    } on Object {
      developer.log(
        'Google Sign-In initialization failed.',
        name: 'Mushukistan.GoogleSignIn',
      );
      throw const GoogleSignInFlowException(
        'Google sign-in could not be initialized for this build.',
        failure: GoogleSignInFailure.notConfigured,
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

/// Maps the plugin's error code to what the person should be told.
GoogleSignInFailure googleSignInFailureFor(GoogleSignInExceptionCode code) =>
    switch (code) {
      GoogleSignInExceptionCode.canceled => GoogleSignInFailure.cancelled,
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        GoogleSignInFailure.notConfigured,
      GoogleSignInExceptionCode.uiUnavailable =>
        GoogleSignInFailure.unavailable,
      _ => GoogleSignInFailure.failed,
    };
