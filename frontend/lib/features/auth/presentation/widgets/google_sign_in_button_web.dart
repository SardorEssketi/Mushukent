import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as gis_web;

import '../../../../core/config/app_environment.dart';
import '../../application/auth_controller.dart';

class GoogleSignInEntryButton extends ConsumerStatefulWidget {
  const GoogleSignInEntryButton({
    super.key,
    required this.enabled,
    this.acceptTerms = false,
    this.acceptPrivacy = false,
  });

  final bool enabled;
  final bool acceptTerms;
  final bool acceptPrivacy;

  @override
  ConsumerState<GoogleSignInEntryButton> createState() =>
      _GoogleSignInEntryButtonState();
}

class _GoogleSignInEntryButtonState
    extends ConsumerState<GoogleSignInEntryButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    _subscription = GoogleSignIn.instance.authenticationEvents.listen(
      _handleAuthenticationEvent,
      onError: _handleAuthenticationError,
    );
    _initialization = _initialize();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _initialize() async {
    final environment = ref.read(appEnvironmentProvider);
    final clientId = environment.googleClientId;
    if (clientId == null || clientId.isEmpty) {
      return;
    }
    await GoogleSignIn.instance.initialize(clientId: clientId);
  }

  Future<void> _handleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) async {
    if (event case GoogleSignInAuthenticationEventSignIn(:final user)) {
      final idToken = user.authentication.idToken;
      if (idToken == null || idToken.trim().isEmpty) {
        ref.read(authControllerProvider.notifier).showUnauthenticatedMessage(
              'Google sign-in did not return an ID token.',
            );
        return;
      }
      try {
        await ref.read(authControllerProvider.notifier).loginWithGoogleIdToken(
              idToken,
              acceptTerms: widget.acceptTerms,
              acceptPrivacy: widget.acceptPrivacy,
            );
      } on Object {
        // Surface handled by auth state.
      }
    }
  }

  void _handleAuthenticationError(Object error, StackTrace stackTrace) {
    final message = switch (error) {
      GoogleSignInException(:final description)
          when description != null && description.trim().isNotEmpty =>
        description.trim(),
      _ => 'Google sign-in failed.',
    };
    ref
        .read(authControllerProvider.notifier)
        .showUnauthenticatedMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(appEnvironmentProvider);
    if (!environment.isGoogleSignInConfigured) {
      return const Text('Google sign-in is not configured for this build.');
    }

    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Google sign-in is unavailable.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !widget.enabled) {
          return const SizedBox(
            height: 40,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return SizedBox(
          height: 40,
          child: gis_web.renderButton(),
        );
      },
    );
  }
}
