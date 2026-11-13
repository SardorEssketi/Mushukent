import 'package:flutter/material.dart';

import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_remote_image.dart';

/// What a marker's post card shows. The marker itself knows only a little
/// (name, date); the rest arrives once the post has been loaded.
class MapPostPreviewData {
  const MapPostPreviewData({
    required this.title,
    this.dateLine,
    this.badge,
    this.photoUrl,
    this.description,
    this.authorName,
    this.likeCount,
    this.commentCount,
    this.viewCount,
  });

  final String title;

  /// For example "Last seen: Nov 7, 2026".
  final String? dateLine;

  /// The kind of post, shown next to the title when it adds something.
  final Widget? badge;
  final String? photoUrl;
  final String? description;
  final String? authorName;
  final int? likeCount;
  final int? commentCount;

  /// The view count as a widget, so its number can update while the card is
  /// open. It inherits the text style of the other counts.
  final Widget? viewCount;
}

/// The card in the sheet that opens from a cat or Lost Pet marker: a short
/// preview of the post, which opens in full when tapped.
class MapPostPreview extends StatelessWidget {
  const MapPostPreview({
    super.key,
    required this.data,
    required this.fallbackIcon,
    required this.accent,
    required this.onAccent,
    required this.openLabel,
    required this.likesLabel,
    required this.commentsLabel,
    required this.viewsLabel,
    required this.onOpen,
  });

  final MapPostPreviewData data;

  /// Shown in place of the photo when the post has none or it fails to load.
  final IconData fallbackIcon;
  final Color accent;
  final Color onAccent;
  final String openLabel;
  final String likesLabel;
  final String commentsLabel;
  final String viewsLabel;
  final VoidCallback onOpen;

  static const _photoSize = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final description = data.description?.trim();
    final meta = [
      data.dateLine?.trim(),
      data.authorName?.trim(),
    ].where((part) => part != null && part.isNotEmpty).join(' · ');
    final fallback = ColoredBox(
      color: accent,
      child: Center(child: Icon(fallbackIcon, size: 36, color: onAccent)),
    );
    final photoUrl = data.photoUrl?.trim();
    final stats = <Widget>[
      if (data.likeCount != null)
        _Stat(Icons.favorite_border, Text('${data.likeCount}'), likesLabel),
      if (data.commentCount != null)
        _Stat(
          Icons.chat_bubble_outline,
          Text('${data.commentCount}'),
          commentsLabel,
        ),
      if (data.viewCount != null)
        _Stat(Icons.visibility_outlined, data.viewCount!, viewsLabel),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: SizedBox.square(
                  dimension: _photoSize,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? fallback
                      : AppRemoteImage(
                          photoUrl,
                          width: _photoSize,
                          height: _photoSize,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => fallback,
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (data.badge != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      data.badge!,
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
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
                  ],
                ),
              ),
            ],
          ),
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.lg, children: stats),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new),
          label: Text(openLabel),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.count, this.label);

  final IconData icon;
  final Widget count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    // Read aloud as "Views 31": the label, then the number.
    return MergeSemantics(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color, semanticLabel: label),
        const SizedBox(width: AppSpacing.xs),
        DefaultTextStyle.merge(
          style: theme.textTheme.labelLarge?.copyWith(color: color),
          child: count,
        ),
      ]),
    );
  }
}
