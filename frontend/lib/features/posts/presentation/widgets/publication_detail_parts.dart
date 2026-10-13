import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../feed/presentation/widgets/feed_card_parts.dart';

/// Shared building blocks for the Post, Lost Pet and Rehoming detail screens.
///
/// Every publication reads the same way: media, author, title and text,
/// facts/contacts, engagement, then discussion. Type-specific content is
/// composed by each screen from these parts.

/// Viewport width at which media moves beside the content.
const double kPublicationSplitWidth = 960;

/// Lays the page out as one bounded column on phones and tablets, and as
/// media beside content + discussion on desktop.
class PublicationDetailLayout extends StatelessWidget {
  const PublicationDetailLayout({
    super.key,
    required this.gallery,
    required this.details,
    required this.comments,
    this.commentsKey,
  });

  final Widget gallery;
  final List<Widget> details;
  final Widget comments;
  final GlobalKey? commentsKey;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final split = width >= kPublicationSplitWidth;
    final commentsBlock = KeyedSubtree(
      key: commentsKey,
      child: comments,
    );
    final detailColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...details,
        const SizedBox(height: AppSpacing.xl),
        commentsBlock,
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        width < AppWidths.compact ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.sm,
        width < AppWidths.compact ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: split ? AppWidths.wide : AppWidths.readable,
          ),
          child: split
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: gallery),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(flex: 10, child: detailColumn),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    gallery,
                    const SizedBox(height: AppSpacing.lg),
                    detailColumn,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Swipeable media with a counter, dots and (on wide screens) arrows.
///
/// Photos are contained in a neutral frame so nothing important is cropped.
class PublicationGallery extends StatefulWidget {
  const PublicationGallery({super.key, required this.photoUrls});

  final List<String> photoUrls;

  @override
  State<PublicationGallery> createState() => _PublicationGalleryState();
}

class _PublicationGalleryState extends State<PublicationGallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final next = (_index + delta).clamp(0, widget.photoUrls.length - 1);
    _controller.animateToPage(
      next,
      duration: AppMotion.of(context, const Duration(milliseconds: 220)),
      curve: AppMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = widget.photoUrls.length;
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.medium;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: AspectRatio(
        aspectRatio: wide ? 4 / 3 : 1.15,
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) => AppRemoteImage(
                  widget.photoUrls[index],
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 48,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (count > 1) ...[
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: _GalleryCounter(current: _index + 1, total: count),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.md,
                  child: _GalleryDots(count: count, activeIndex: _index),
                ),
                if (wide) ...[
                  Positioned(
                    left: AppSpacing.sm,
                    top: 0,
                    bottom: 0,
                    child: _GalleryArrow(
                      icon: Icons.chevron_left,
                      onPressed: _index == 0 ? null : () => _move(-1),
                    ),
                  ),
                  Positioned(
                    right: AppSpacing.sm,
                    top: 0,
                    bottom: 0,
                    child: _GalleryArrow(
                      icon: Icons.chevron_right,
                      onPressed: _index == count - 1 ? null : () => _move(1),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryCounter extends StatelessWidget {
  const _GalleryCounter({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$current / $total',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _GalleryDots extends StatelessWidget {
  const _GalleryDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            width: index == activeIndex ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: index == activeIndex ? 0.95 : 0.55,
              ),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 2),
              ],
            ),
          ),
      ],
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

/// Avatar, name (opens the public profile) and date on one compact row.
class PublicationAuthorRow extends StatelessWidget {
  const PublicationAuthorRow({
    super.key,
    required this.author,
    required this.createdAt,
    required this.strings,
    required this.onAuthorTap,
    this.isEdited = false,
  });

  final PostAuthorData? author;
  final DateTime createdAt;
  final AppStrings strings;
  final VoidCallback? onAuthorTap;
  final bool isEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = author?.name?.trim().isNotEmpty == true
        ? author!.name!.trim()
        : strings.anonymous;
    final date =
        MaterialLocalizations.of(context).formatMediumDate(createdAt.toLocal());
    return Semantics(
      container: true,
      button: onAuthorTap != null,
      label: '$name, $date',
      excludeSemantics: true,
      child: InkWell(
        onTap: onAuthorTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              FeedAuthorAvatar(name: name, avatarUrl: author?.avatarUrl),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      isEdited ? '$date · ${strings.edited}' : date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Type badge + title. The badge is omitted for neutral cat posts.
class PublicationTitle extends StatelessWidget {
  const PublicationTitle({
    super.key,
    required this.title,
    this.badge,
  });

  final String title;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badge != null) ...[
          badge!,
          const SizedBox(height: AppSpacing.sm),
        ],
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
          ),
        ),
      ],
    );
  }
}

/// A tinted note for the information that matters most (help needed,
/// resolved status).
class PublicationCallout extends StatelessWidget {
  const PublicationCallout({
    super.key,
    required this.icon,
    required this.color,
    required this.body,
    this.title,
  });

  final IconData icon;
  final Color color;
  final String? title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  if (title != null) const SizedBox(height: AppSpacing.xs),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One quiet container for facts and contacts. Rows are separated by hairlines
/// instead of stacking separate cards.
class PublicationInfoGroup extends StatelessWidget {
  const PublicationInfoGroup({super.key, required this.rows});

  final List<PublicationInfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 52, color: colors.outlineVariant),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class PublicationInfoRow extends StatelessWidget {
  const PublicationInfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, color: color ?? colors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact engagement row: an optional like toggle and a comments shortcut.
/// Both targets share size, icon and type scale.
class PublicationEngagementBar extends StatelessWidget {
  const PublicationEngagementBar({
    super.key,
    required this.strings,
    required this.commentCount,
    required this.onComments,
    this.liked = false,
    this.likeCount,
    this.onLike,
  });

  final AppStrings strings;
  final int commentCount;
  final VoidCallback onComments;

  /// Null hides the like action (Lost Pet and Rehoming have no likes).
  final int? likeCount;
  final bool liked;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (likeCount != null) ...[
          _EngagementButton(
            icon: liked ? Icons.favorite : Icons.favorite_border,
            count: likeCount!,
            label: liked ? strings.unlike : strings.like,
            color: liked ? colors.error : null,
            selected: liked,
            onPressed: onLike,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        _EngagementButton(
          icon: Icons.mode_comment_outlined,
          count: commentCount,
          label: strings.comments,
          onPressed: onComments,
        ),
      ],
    );
  }
}

class _EngagementButton extends StatelessWidget {
  const _EngagementButton({
    required this.icon,
    required this.count,
    required this.label,
    required this.onPressed,
    this.color,
    this.selected = false,
  });

  final IconData icon;
  final int count;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = color ?? colors.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label, $count',
        excludeSemantics: true,
        child: Material(
          color: selected
              ? tint.withValues(alpha: 0.12)
              : colors.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: tint),
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected ? tint : colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry of the contextual overflow menu.
class PublicationMenuEntry<T> {
  const PublicationMenuEntry({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// App-bar overflow menu. Renders nothing when the viewer has no actions, so
/// callers only list actions the viewer is permitted to perform.
class PublicationActionsMenu<T> extends StatelessWidget {
  const PublicationActionsMenu({
    super.key,
    required this.tooltip,
    required this.entries,
    required this.onSelected,
  });

  final String tooltip;
  final List<PublicationMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries) ...[
          if (entry.destructive && entries.first != entry)
            const PopupMenuDivider(),
          PopupMenuItem<T>(
            value: entry.value,
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  size: 20,
                  color: entry.destructive ? colors.error : null,
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    entry.label,
                    style: entry.destructive
                        ? TextStyle(color: colors.error)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
