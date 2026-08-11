import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../localization/app_strings.dart';
import '../localization/language_controller.dart';
import '../network/mushukistan_api.dart';
import 'authenticated_onboarding_store.dart';

class AuthenticatedOnboardingFlow extends ConsumerStatefulWidget {
  const AuthenticatedOnboardingFlow({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<AuthenticatedOnboardingFlow> createState() =>
      _AuthenticatedOnboardingFlowState();
}

class _AuthenticatedOnboardingFlowState
    extends ConsumerState<AuthenticatedOnboardingFlow> {
  bool _isRunning = false;
  String? _handledUserId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userId = user?.id;
    if (userId != null && userId != _handledUserId && !_isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runOnboarding(userId));
      });
    }

    return widget.child;
  }

  Future<void> _runOnboarding(String userId) async {
    if (!mounted || _isRunning) {
      return;
    }

    _isRunning = true;
    try {
      final store = ref.read(authenticatedOnboardingStoreProvider);
      if (await store.hasSeen(userId)) {
        _handledUserId = userId;
        return;
      }
      if (!mounted) {
        return;
      }

      final currentLanguage = ref.read(appLanguageProvider);
      final selectedLanguage = await _showLanguageDialog(
        context,
        initialLanguage: currentLanguage,
      );
      if (!mounted) {
        return;
      }

      ref.read(appLanguageProvider.notifier).state = selectedLanguage;
      try {
        await ref.read(mushukistanApiProvider).updateMe(
              preferredLanguage: selectedLanguage.code,
            );
        ref.invalidate(profileMeProvider);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppStrings.forLanguage(selectedLanguage).couldNotSaveChanges,
              ),
            ),
          );
        }
      }

      if (!mounted) {
        return;
      }
      await _showWelcomeDialog(
        context,
        AppStrings.forLanguage(selectedLanguage),
      );
      await store.markSeen(userId);
      _handledUserId = userId;
    } finally {
      _isRunning = false;
    }
  }
}

Future<AppLanguage> _showLanguageDialog(
  BuildContext context, {
  required AppLanguage initialLanguage,
}) async {
  final selected = await showDialog<AppLanguage>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      var pendingLanguage = initialLanguage;
      return StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final strings = AppStrings.forLanguage(pendingLanguage);

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.language_outlined, size: 30),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      strings.chooseYourLanguage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.chooseLanguageSubtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final language in AppLanguage.values) ...[
                      _LanguageOption(
                        language: language,
                        selected: pendingLanguage == language,
                        onTap: () {
                          setState(() {
                            pendingLanguage = language;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(
                        pendingLanguage,
                      ),
                      icon: const Icon(Icons.check_outlined),
                      label: Text(strings.continueAction),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  return selected ?? initialLanguage;
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.primaryContainer : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  language.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showWelcomeDialog(BuildContext context, AppStrings strings) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;

      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: colorScheme.secondaryContainer,
                  foregroundColor: colorScheme.onSecondaryContainer,
                  child: const Icon(Icons.favorite_outline, size: 32),
                ),
                const SizedBox(height: 18),
                Text(
                  strings.welcomeToMushukistan,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      strings.welcomeSupportMessage,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.supportMyWork,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.supportCardIntro,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '5614 6810 1028 4564 ☕️🙂',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(strings.startExploring),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
