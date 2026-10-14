import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/auth_controller.dart';

/// Shown instead of the sign-in flow when a protected page is opened while a stored session could
/// not be confirmed because the server is unreachable. The user is still signed in as far as the
/// app knows; the router moves on by itself as soon as the session is confirmed.
class SessionUnavailableScreen extends ConsumerWidget {
  const SessionUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final authState = ref.watch(authControllerProvider);
    final reconnecting = authState.reconnecting;

    return Scaffold(
      appBar: AppBar(title: Text(strings.sessionUnavailableTitle)),
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
                    Icons.cloud_off_outlined,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    strings.sessionUnavailableTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    strings.sessionUnavailableMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (reconnecting)
                    Column(
                      children: [
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          strings.sessionReconnecting,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  else ...[
                    FilledButton(
                      onPressed: () => unawaited(
                        ref
                            .read(authControllerProvider.notifier)
                            .retrySession(),
                      ),
                      child: Text(strings.retry),
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

/// Compact notice for public pages (feed) while a stored session is unconfirmed. It replaces the
/// signed-out welcome card, which would wrongly suggest the user had been logged out.
class SessionUnavailableBanner extends ConsumerWidget {
  const SessionUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final reconnecting = ref.watch(
      authControllerProvider.select((state) => state.reconnecting),
    );
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: colors.onSecondaryContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.sessionUnavailableTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                  ),
                  Text(
                    reconnecting
                        ? strings.sessionReconnecting
                        : strings.sessionUnavailableMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                  ),
                ],
              ),
            ),
            if (!reconnecting)
              TextButton(
                onPressed: () => unawaited(
                  ref.read(authControllerProvider.notifier).retrySession(),
                ),
                child: Text(strings.retry),
              ),
          ],
        ),
      ),
    );
  }
}
