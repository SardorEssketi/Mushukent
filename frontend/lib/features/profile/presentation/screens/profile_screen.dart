import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/navigation/settings_changes_guard.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../auth/application/auth_controller.dart';
import '../widgets/profile_components.dart';

final profileMeProvider =
    FutureProvider.autoDispose<UserProfileData>((ref) async {
  return ref.watch(mushukistanApiProvider).getMe();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final profileAsync = ref.watch(profileMeProvider);
    final currentUser = ref.watch(currentUserProvider);
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.profile),
        actions: [
          if (MediaQuery.sizeOf(context).width < AppWidths.compact)
            IconButton(
              tooltip: strings.donateToAuthor,
              onPressed: () => _showDonationDialog(context, strings),
              icon: const Icon(Icons.volunteer_activism_outlined),
            )
          else
            Tooltip(
              message: strings.donateToAuthor,
              child: TextButton.icon(
                onPressed: () => _showDonationDialog(context, strings),
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: Text(strings.donateToAuthor),
              ),
            ),
          IconButton(
            tooltip: strings.editProfile,
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<_ProfileAction>(
            tooltip: strings.settings,
            onSelected: (action) async {
              switch (action) {
                case _ProfileAction.logout:
                  if (authState.isBusy) {
                    return;
                  }
                  if (!await confirmLeavingSettings(context, ref)) {
                    return;
                  }
                  if (!context.mounted) {
                    return;
                  }
                  final confirmed = await _confirmLogout(context, strings);
                  if (confirmed) {
                    await controller.logout();
                    if (context.mounted) {
                      context.go('/feed');
                    }
                  }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ProfileAction.logout,
                enabled: !authState.isBusy,
                child: Text(strings.logout),
              ),
            ],
          ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) {
          final summary = ProfileSummaryCard(
            name: profile.name ?? currentUser?.name ?? strings.unnamedUser,
            strings: strings,
            avatarUrl: profile.avatarUrl ?? currentUser?.avatarUrl,
            bio: profile.bio,
            email: profile.email,
            phoneNumber: profile.phoneNumber,
            telegramUsername: profile.telegramUsername,
            observationCount: profile.observationCount,
            likesReceived: profile.totalLikesReceived,
            commentCount: profile.commentCount,
            onObservationsTap: () => context.push('/profile/observations'),
            onCommentsTap: () => context.push('/profile/comments'),
          );
          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileSectionHeading(title: strings.yourActivity),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  ProfileActionRow(
                    icon: Icons.search_outlined,
                    title: strings.myLostPets,
                    onTap: () => context.push('/profile/lost-pets'),
                  ),
                  const Divider(height: 1),
                  ProfileActionRow(
                    icon: Icons.home_outlined,
                    title: strings.myAdoptionPosts,
                    onTap: () => context.push('/profile/adoption-posts'),
                  ),
                ]),
              ),
              const SizedBox(height: AppSpacing.xl),
              ProfileSectionHeading(title: strings.resourcesAndAccount),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  ProfileActionRow(
                    icon: Icons.menu_book_outlined,
                    title: strings.adoptionHelpTooltip,
                    onTap: () => context.push('/profile/adoption-help'),
                  ),
                  const Divider(height: 1),
                  ProfileActionRow(
                    icon: Icons.settings_outlined,
                    title: strings.settings,
                    onTap: () => context.push('/profile/settings'),
                  ),
                ]),
              ),
              if (profile.isModerator || currentUser?.isModerator == true) ...[
                const SizedBox(height: AppSpacing.xl),
                ProfileSectionHeading(title: strings.moderationReports),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: ProfileActionRow(
                    icon: Icons.admin_panel_settings_outlined,
                    title: strings.moderationReports,
                    onTap: () => context.push('/moderation/reports'),
                  ),
                ),
              ],
            ],
          );
          return AppContentWidth(
            maxWidth: AppWidths.wide,
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= AppWidths.readable;
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (wide)
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: summary),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(flex: 6, child: actions),
                        ])
                  else ...[
                    summary,
                    const SizedBox(height: AppSpacing.xl),
                    actions,
                  ],
                ],
              );
            }),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.profile,
          message: strings.couldNotLoadProfile,
          action: FilledButton(
            onPressed: () => ref.invalidate(profileMeProvider),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }
}

Future<void> _showDonationDialog(
  BuildContext context,
  AppStrings strings,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(strings.donateToAuthor),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.supportCardIntro),
            const SizedBox(height: AppSpacing.md),
            Text(
              strings.supportRecipient,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              strings.supportCardNumber,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: strings.supportCardNumber),
              );
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.cardNumberCopied)),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(strings.copyCardNumber),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
        ],
      );
    },
  );
}

Future<bool> _confirmLogout(BuildContext context, AppStrings strings) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.confirmLogoutTitle),
      content: Text(strings.confirmLogoutMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.logout),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

enum _ProfileAction { logout }
