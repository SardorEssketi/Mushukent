import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../feed/presentation/widgets/feed_card_parts.dart';

/// Shared building blocks for the Post, Lost Pet and Rehoming detail screens.
///
/// Every publication reads the same way: media, author, title and text,
/// facts and contacts, engagement, then discussion. Type-specific content is
/// composed by each screen from these parts.

/// Viewport width at which media moves beside the content.
const double kPublicationSplitWidth = 960;

/// Below this width media runs edge to edge.
const double kPublicationBleedWidth = 560;

/// Phone: full-bleed media, then content, then discussion. Tablet: the same,
/// in a bounded column. Desktop: media beside the summary, with the
/// discussion in a readable column underneath.
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
    final bleed = width < kPublicationBleedWidth;
    final commentsBlock = KeyedSubtree(key: commentsKey, child: comments);
    final detailColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: details,
    );

    if (split) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.huge,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppWidths.wide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: gallery),
                    const SizedBox(width: AppSpacing.xxl),
                    Expanded(flex: 5, child: detailColumn),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: AppWidths.readable),
                    child: commentsBlock,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final gutter = width < AppWidths.compact ? AppSpacing.lg : AppSpacing.xl;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppWidths.readable),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: bleed
                    ? EdgeInsets.zero
                    : EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
                child: gallery,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.lg, gutter, 0),
                child: detailColumn,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    gutter, AppSpacing.xl, gutter, AppSpacing.huge),
                child: commentsBlock,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipeable media with a counter, dots and (on wide screens) arrows.
///
/// The photo is contained so nothing important is cropped; a blurred copy of
/// it fills the frame so there are no empty bars.
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
    final size = MediaQuery.sizeOf(context);
    final count = widget.photoUrls.length;
    final split = size.width >= kPublicationSplitWidth;
    final bleed = size.width < kPublicationBleedWidth;
    final aspect = split || bleed ? 1.0 : 4 / 3;
    final backdrop = widget.photoUrls.isEmpty
        ? null
        : widget.photoUrls[_index.clamp(0, count - 1)];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * 0.62),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(bleed ? 0 : AppRadii.card),
        child: AspectRatio(
          aspectRatio: aspect,
          child: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdrop != null) ...[
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 28,
                      sigmaY: 28,
                      tileMode: TileMode.clamp,
                    ),
                    child: AppRemoteImage(
                      backdrop,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
                ],
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
                  if (size.width >= AppBreakpoints.medium) ...[
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

/// A small tappable pill for a single fact, such as the location.
class PublicationChip extends StatelessWidget {
  const PublicationChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: tint.withValues(alpha: 0.28)),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: tint),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tint,
                          fontWeight: FontWeight.w700,
                        ),
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

/// The page's primary call to action (contact the owner). The value, such as
/// a phone number, is shown under the label so people see what they will call.
class PublicationContactButton extends StatelessWidget {
  const PublicationContactButton({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    required this.onPressed,
    this.primary = true,
  });

  final IconData icon;
  final String label;

  /// Shown under the label (the phone number or handle); null when the viewer may not see it yet.
  final String? value;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (value != null)
                Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
    );
    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

/// Flat engagement strip between two hairlines: an optional like toggle and a
/// comments shortcut. Both targets share size, icon and type scale.
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
    final line =
        BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7));
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: line, bottom: line)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            if (likeCount != null)
              _EngagementButton(
                icon: liked ? Icons.favorite : Icons.favorite_border,
                count: likeCount!,
                label: liked ? strings.unlike : strings.like,
                color: liked ? colors.error : null,
                selected: liked,
                onPressed: onLike,
              ),
            _EngagementButton(
              icon: Icons.mode_comment_outlined,
              count: commentCount,
              label: strings.comments,
              onPressed: onComments,
            ),
          ],
        ),
      ),
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
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: tint),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: theme.textTheme.titleSmall?.copyWith(
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
