import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../application/auth_controller.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);
    final email = authState.pendingVerificationEmail;

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
                onPressed: () => context.go('/login'),
                child: Text(strings.backToLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
