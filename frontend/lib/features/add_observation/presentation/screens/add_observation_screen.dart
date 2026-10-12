import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/validation/phone_numbers.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';

class AddObservationScreen extends ConsumerStatefulWidget {
  const AddObservationScreen({super.key});

  @override
  ConsumerState<AddObservationScreen> createState() =>
      _AddObservationScreenState();
}

class _AddObservationScreenState extends ConsumerState<AddObservationScreen> {
  Future<void> _openContactRequiredFlow({
    required String path,
    required String requirementMessage,
  }) async {
    final strings = ref.read(appStringsProvider);
    try {
      final profile = await ref.read(mushukistanApiProvider).getMe();
      final phone = profile.phoneNumber?.trim() ?? '';
      if (!mounted) {
        return;
      }
      if (phone.isNotEmpty && isValidUzbekPhoneNumber(phone)) {
        context.go(path);
        return;
      }
      final editProfile = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.phoneNumberRequired),
          content: Text(requirementMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.editProfile),
            ),
          ],
        ),
      );
      if (editProfile == true && mounted) {
        context.go('/profile/edit');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotLoadProfile)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addObservationControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.create)),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: AppContentWidth(
        maxWidth: AppWidths.wide,
        child: ListView(
          padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < AppWidths.compact
                  ? AppSpacing.lg
                  : AppSpacing.xl),
          children: [
            Text(strings.createInMushukistan,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.chooseShareType,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(builder: (context, constraints) {
              final colors = Theme.of(context).colorScheme;
              final cards = [
                _CreateActionCard(
                  icon: Icons.add_a_photo_outlined,
                  title: strings.catObservation,
                  description: strings.catObservationAddSubtitle,
                  accent: colors.primary,
                  onTap: () {
                    ref
                        .read(addObservationControllerProvider.notifier)
                        .reset(kind: 'observation');
                    context.go('/add/details');
                  },
                ),
                _CreateActionCard(
                  icon: Icons.volunteer_activism_outlined,
                  title: strings.needsHelp,
                  description: strings.needsHelpCreateSubtitle,
                  accent: colors.secondary,
                  onTap: () {
                    ref
                        .read(addObservationControllerProvider.notifier)
                        .reset(kind: 'needs_help');
                    context.go('/add/details');
                  },
                ),
                _CreateActionCard(
                  icon: Icons.search_outlined,
                  title: strings.lostPet,
                  description: strings.lostPetAlertSubtitle,
                  accent: colors.error,
                  onTap: () => unawaited(_openContactRequiredFlow(
                    path: '/add/lost-pet',
                    requirementMessage: strings.phoneNumberRequiredForLostPet,
                  )),
                ),
                _CreateActionCard(
                  icon: Icons.home_outlined,
                  title: strings.findANewHome,
                  description: strings.findANewHomeSubtitle,
                  accent: AppPalette.adoption,
                  onTap: () => unawaited(_openContactRequiredFlow(
                    path: '/add/adoption',
                    requirementMessage: strings.phoneNumberRequiredForAdoption,
                  )),
                ),
              ];
              if (constraints.maxWidth < AppWidths.readable - AppSpacing.xl) {
                return Column(children: [
                  for (final card in cards) ...[
                    card.asCompact(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ]);
              }
              return Column(children: [
                for (var row = 0; row < 2; row++) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[row * 2]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: cards[row * 2 + 1]),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ]);
            }),
            if (state.hasDraft) ...[
              const SizedBox(height: AppSpacing.xl),
              Text(strings.continueDraft,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: LayoutBuilder(builder: (context, constraints) {
                  final content = Row(children: [
                    const Icon(Icons.edit_note_outlined),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(strings.draftStatus)),
                  ]);
                  final action = FilledButton.tonal(
                    onPressed: () => context.go('/add/details'),
                    child: Text(strings.continueAction),
                  );
                  if (constraints.maxWidth < AppWidths.compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        content,
                        const SizedBox(height: AppSpacing.md),
                        action,
                      ],
                    );
                  }
                  return Row(children: [Expanded(child: content), action]);
                }),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final shouldDelete =
                        await _confirmDeleteDraft(context, strings);
                    if (!shouldDelete) return;
                    ref.read(addObservationControllerProvider.notifier).reset();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.draftDeleted)),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(strings.deleteDraft),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateActionCard extends StatelessWidget {
  const _CreateActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  /// Phones get a one-handed horizontal tile; wide layouts get a grid card.
  final bool compact;

  _CreateActionCard asCompact() => _CreateActionCard(
        icon: icon,
        title: title,
        description: description,
        accent: accent,
        onTap: onTap,
        compact: true,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Icon(icon, color: accent, size: 28),
      ),
    );
    final text = [
      Text(title, style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpacing.xs),
      Text(
        description,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
    return Semantics(
      button: true,
      label: title,
      child: AppCard(
        onTap: onTap,
        child: compact
            ? Row(
                children: [
                  badge,
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: text,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 138),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    badge,
                    const SizedBox(height: AppSpacing.lg),
                    ...text,
                  ],
                ),
              ),
      ),
    );
  }
}

Future<bool> _confirmDeleteDraft(
    BuildContext context, AppStrings strings) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.deleteDraftTitle),
      content: Text(strings.deleteDraftMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}
