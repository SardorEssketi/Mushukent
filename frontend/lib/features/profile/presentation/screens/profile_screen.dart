import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
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
          IconButton(
            tooltip: strings.editProfile,
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<_ProfileAction>(
            tooltip: strings.settings,
            onSelected: (action) async {
              switch (action) {
                case _ProfileAction.adoptionHelp:
                  context.push('/profile/adoption-help');
                case _ProfileAction.settings:
                  context.push('/profile/settings');
                case _ProfileAction.logout:
                  if (authState.isBusy) {
                    return;
                  }
                  final confirmed = await _confirmLogout(context, strings);
                  if (confirmed) {
                    unawaited(controller.logout());
                  }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ProfileAction.adoptionHelp,
                child: Text(strings.adoptionHelpTooltip),
              ),
              PopupMenuItem(
                value: _ProfileAction.settings,
                child: Text(strings.settings),
              ),
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
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorPanel(
          message: strings.couldNotLoadProfile,
          retryLabel: strings.retry,
          onRetry: () => ref.invalidate(profileMeProvider),
        ),
      ),
    );
  }
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
                Text('@$telegram', style: Theme.of(context).textTheme.bodySmall),
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

enum _ProfileAction { adoptionHelp, settings, logout }

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

String _initials(String name, String email) {
  final source = name.trim().isEmpty ? email : name;
  final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join();
  return initials.isEmpty ? 'MU' : initials.toUpperCase();
}
