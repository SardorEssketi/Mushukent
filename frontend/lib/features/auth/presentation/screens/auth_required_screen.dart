import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/auth_controller.dart';

class AuthRequiredScreen extends ConsumerWidget {
  const AuthRequiredScreen({super.key, this.redirect});

  final String? redirect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final authState = ref.watch(authControllerProvider);
    final checkingSession = authState.phase == AuthPhase.restoring;

    return Scaffold(
      appBar: AppBar(title: Text(strings.signInToMushukistan)),
      body: Center(
        child: AppContentWidth(
          maxWidth: 440,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    strings.signInRequiredTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    checkingSession
                        ? strings.restoringSession
                        : strings.signInRequiredMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (checkingSession)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    FilledButton(
                      onPressed: () => context.go(
                        authEntryLocation('/login', redirect),
                      ),
                      child: Text(strings.login),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () => context.go(
                        authEntryLocation('/register', redirect),
                      ),
                      child: Text(strings.createAccount),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () => context.go('/feed'),
                      child: Text(strings.continueBrowsing),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
