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
        data: (profile) => AppContentWidth(
          maxWidth: AppWidths.readable,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Header(
                name: profile.name ?? currentUser?.name ?? strings.unnamedUser,
                email: profile.email,
                avatarUrl: profile.avatarUrl ?? currentUser?.avatarUrl,
                phoneNumber: profile.phoneNumber,
                telegramUsername: profile.telegramUsername,
                bio: profile.bio,
              ),
              const SizedBox(height: 16),
              _StatGrid(
                profile: profile,
                strings: strings,
                onObservationsTap: () => context.push('/profile/observations'),
                onCommentsTap: () => context.push('/profile/comments'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_outlined),
                title: Text(strings.adoptionHelpTooltip),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/adoption-help'),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_outlined),
                title: Text(strings.settings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/settings'),
              ),
              if (profile.isModerator || currentUser?.isModerator == true) ...[
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(strings.moderationReports),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/moderation/reports'),
                ),
              ],
            ],
          ),
        ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.phoneNumber,
    required this.telegramUsername,
    required this.bio,
  });

  final String name;
  final String email;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? telegramUsername;
  final String? bio;

  @override
  Widget build(BuildContext context) {
    final phone = phoneNumber?.trim();
    final telegram = telegramUsername?.trim();
    final profileBio = bio?.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
          child: avatarUrl == null ? Text(_initials(name, email)) : null,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (phone != null && phone.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(phone, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (telegram != null && telegram.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text('@$telegram',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (profileBio != null && profileBio.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(profileBio, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.profile,
    required this.strings,
    required this.onObservationsTap,
    required this.onCommentsTap,
  });

  final UserProfileData profile;
  final AppStrings strings;
  final VoidCallback onObservationsTap;
  final VoidCallback onCommentsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: strings.observations,
            value: profile.observationCount.toString(),
            onTap: onObservationsTap,
          ),
        ),
        const SizedBox(
          height: 44,
          child: VerticalDivider(width: AppSpacing.xl),
        ),
        Expanded(
          child: _StatCard(
            label: strings.likesReceived,
            value: profile.totalLikesReceived.toString(),
          ),
        ),
        const SizedBox(
          height: 44,
          child: VerticalDivider(width: AppSpacing.xl),
        ),
        Expanded(
          child: _StatCard(
            label: strings.comments,
            value: profile.commentCount.toString(),
            onTap: onCommentsTap,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProfileAction { logout }

String _initials(String name, String email) {
  final source = name.trim().isEmpty ? email : name;
  final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}
