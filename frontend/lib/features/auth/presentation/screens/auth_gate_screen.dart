import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/widgets/empty_screen.dart';
import '../../application/auth_controller.dart';

class AuthGateScreen extends ConsumerWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);

    if (authState.phase == AuthPhase.failure) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Mushukistan',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  const Icon(Icons.pets, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    authState.message ?? strings.sessionCheckFailed,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: authState.retryable
                        ? () {
                            unawaited(controller.restoreSession(force: true));
                          }
                        : null,
                    child: Text(strings.retry),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(strings.continueToLogin),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (authState.phase == AuthPhase.restoring ||
        authState.phase == AuthPhase.initial) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pets, size: 64),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(strings.restoringSession),
            ],
          ),
        ),
      );
    }

    return const EmptyScreen(title: 'Auth Gate');
  }
}
