import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_remote_image.dart';

class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    super.key,
    required this.name,
    required this.strings,
    required this.observationCount,
    required this.likesReceived,
    required this.commentCount,
    this.avatarUrl,
    this.bio,
    this.email,
    this.phoneNumber,
    this.telegramUsername,
    this.onObservationsTap,
    this.onCommentsTap,
    this.onAvatarTap,
    this.avatarBusy = false,
  });

  final String name;
  final AppStrings strings;
  final String? avatarUrl;
  final String? bio;
  final String? email;
  final String? phoneNumber;
  final String? telegramUsername;
  final int observationCount;
  final int likesReceived;
  final int commentCount;
  final VoidCallback? onObservationsTap;
  final VoidCallback? onCommentsTap;

  /// Set on the user's own profile: the avatar opens the photo actions.
  final VoidCallback? onAvatarTap;
  final bool avatarBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final contacts = [
      if (email?.trim().isNotEmpty == true) email!.trim(),
      if (phoneNumber?.trim().isNotEmpty == true) phoneNumber!.trim(),
      if (telegramUsername?.trim().isNotEmpty == true)
        '@${telegramUsername!.trim().replaceFirst('@', '')}',
    ];
    final description = bio?.trim();

    return AppCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              onAvatarTap == null
                  ? ProfileAvatar(name: name, avatarUrl: avatarUrl)
                  : _EditableAvatar(
                      label: strings.changePhoto,
                      busy: avatarBusy,
                      onTap: onAvatarTap!,
                      child: ProfileAvatar(name: name, avatarUrl: avatarUrl),
                    ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (contacts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      for (final contact in contacts)
                        Text(
                          contact,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondaryStyle,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ProfileStat(
                    value: observationCount,
                    label: strings.observations,
                    onTap: onObservationsTap,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ProfileStat(
                    value: likesReceived,
                    label: strings.likesReceived,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ProfileStat(
                    value: commentCount,
                    label: strings.comments,
                    onTap: onCommentsTap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The own-profile avatar: tappable, with a small camera badge.
class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.label,
    required this.busy,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              if (busy)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('profile-avatar-button'),
                    onTap: busy ? null : onTap,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: IgnorePointer(
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                    child: Icon(Icons.photo_camera,
                        size: 14, color: colors.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final initials = parts.take(2).map((part) => part[0]).join().toUpperCase();
    final fallback = CircleAvatar(
      radius: 36,
      backgroundColor: colors.primaryContainer,
      child: Text(
        initials.isEmpty ? 'MU' : initials,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: AppRemoteImage(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tappable = onTap != null;
    final tile = Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.xs,
            ),
            child: Column(
              children: [
                Text(
                  '$value',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  maxLines: 3,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ));
    if (!tappable) return tile;
    // Tappable tiles get an "open" arrow in the corner so they do not look
    // like the static Likes received count next to them.
    return Semantics(
      button: true,
      child: Stack(
        // Passes the row's stretched height through, so the tile keeps the
        // same height as the static Likes tile.
        fit: StackFit.passthrough,
        children: [
          tile,
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: IgnorePointer(
              child: Icon(
                Icons.arrow_outward,
                key: const ValueKey('profile-stat-open-icon'),
                size: 16,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileSectionHeading extends StatelessWidget {
  const ProfileSectionHeading({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

class ProfileActionRow extends StatelessWidget {
  const ProfileActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Optional short label (for example "Beta") shown before the chevron.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 56,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: colors.onPrimaryContainer),
        ),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      trailing: badge == null
          ? const Icon(Icons.chevron_right_rounded)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      badge!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
      onTap: onTap,
    );
  }
}
