import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
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
            tooltip: strings.adoptionHelpTooltip,
            onPressed: () => context.push('/profile/adoption-help'),
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: strings.editProfile,
            onPressed: () => context.push('/profile/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: strings.settings,
            onPressed: () => context.push('/profile/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: strings.logout,
            onPressed: authState.isBusy
                ? null
                : () async {
                    final confirmed = await _confirmLogout(context, strings);
                    if (!confirmed) {
                      return;
                    }
                    unawaited(controller.logout());
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: profileAsync.when(
        data: (profile) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _Header(
                  name:
                      profile.name ?? currentUser?.name ?? strings.unnamedUser,
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
                  onObservationsTap: () =>
                      context.push('/profile/observations'),
                  onCommentsTap: () => context.push('/profile/comments'),
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorPanel(
          message: error.toString(),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage:
                avatarUrl == null ? null : NetworkImage(avatarUrl!),
            child: avatarUrl == null ? Text(_initials(name, email)) : null,
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (telegram != null && telegram.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '@$telegram',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (profileBio != null && profileBio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    profileBio,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 680 ? 3 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: crossAxisCount == 4 ? 1.35 : 1.35,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _StatCard(
              icon: Icons.pets_outlined,
              label: strings.observations,
              value: profile.observationCount.toString(),
              color: colorScheme.tertiary,
              onTap: onObservationsTap,
            ),
            _StatCard(
              icon: Icons.favorite_outline,
              label: strings.likesReceived,
              value: profile.totalLikesReceived.toString(),
              color: colorScheme.error,
            ),
            _StatCard(
              icon: Icons.chat_bubble_outline,
              label: strings.comments,
              value: profile.commentCount.toString(),
              color: colorScheme.secondary,
              onTap: onCommentsTap,
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              if (onTap != null) ...[
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );
  }
}

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
