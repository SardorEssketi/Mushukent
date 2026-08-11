import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../application/auth_controller.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.token,
  });

  final String? token;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _verificationStarted = false;
  bool _verificationComplete = false;
  String? _verificationError;

  bool get _hasToken => widget.token?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    if (_hasToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_verifyLinkToken());
      });
    }
  }

  Future<void> _verifyLinkToken() async {
    if (_verificationStarted) {
      return;
    }

    setState(() {
      _verificationStarted = true;
      _verificationError = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyEmail(widget.token!.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _verificationComplete = true;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      final message = ref.read(authControllerProvider).message;
      setState(() {
        _verificationError = message ?? 'Could not verify this email link.';
      });
    }
  }

  void _goBackToLogin(BuildContext context) {
    ref.read(authControllerProvider.notifier).returnToLogin();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);
    final email = authState.pendingVerificationEmail;

    if (_hasToken) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.verifyEmail)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  strings.confirmYourEmail,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (!_verificationComplete && _verificationError == null) ...[
                  const Text('Confirming your email...'),
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ] else if (_verificationComplete) ...[
                  const Text('Email verified. You can sign in now.'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: Text(strings.continueToLogin),
                  ),
                ] else ...[
                  Text(
                    _verificationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _verificationStarted = false;
                      });
                      unawaited(_verifyLinkToken());
                    },
                    child: Text(strings.retry),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _goBackToLogin(context),
                    child: Text(strings.backToLogin),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.verifyEmail)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                strings.confirmYourEmail,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                email == null || email.isEmpty
                    ? strings.verifyEmailWithoutAddress
                    : strings.verifyEmailWithAddress.replaceAll(
                        '{email}',
                        email,
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                strings.devVerificationHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (authState.hasError) ...[
                const SizedBox(height: 16),
                Text(
                  authState.message!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (authState.devVerificationToken != null) ...[
                FilledButton(
                  onPressed: () async {
                    try {
                      await controller
                          .verifyEmail(authState.devVerificationToken!);
                      if (context.mounted) {
                        context.go('/login');
                      }
                    } on Object {
                      // Surface handled by auth state.
                    }
                  },
                  child: Text(strings.verifyNow),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.tonal(
                onPressed: email == null || email.isEmpty
                    ? null
                    : () {
                        unawaited(controller.resendVerification(email));
                      },
                child: Text(strings.resendVerification),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _goBackToLogin(context),
                child: Text(strings.backToLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
