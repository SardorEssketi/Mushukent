import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';

class FeedCardFrame extends StatelessWidget {
  const FeedCardFrame({
    super.key,
    required this.onTap,
    required this.children,
    this.accent,
  });

  final VoidCallback onTap;
  final List<Widget> children;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null)
              SizedBox(height: 3, child: ColoredBox(color: accent!)),
            ...children,
          ],
        ),
      ),
    );
  }
}

class FeedAuthorHeader extends StatelessWidget {
  const FeedAuthorHeader({
    super.key,
    required this.author,
    required this.createdAt,
    required this.strings,
    required this.onAuthorTap,
  });

  final PostAuthorData? author;
  final DateTime createdAt;
  final AppStrings strings;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = author?.name?.trim().isNotEmpty == true
        ? author!.name!.trim()
        : strings.anonymous;
    final date =
        MaterialLocalizations.of(context).formatMediumDate(createdAt.toLocal());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        InkWell(
          onTap: onAuthorTap,
          borderRadius: BorderRadius.circular(24),
          child: FeedAuthorAvatar(name: name, avatarUrl: author?.avatarUrl),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: InkWell(
            onTap: onAuthorTap,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    date,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class FeedAuthorAvatar extends StatelessWidget {
  const FeedAuthorAvatar({super.key, required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = CircleAvatar(
      radius: 19,
      backgroundColor: colors.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class FeedMedia extends StatefulWidget {
  const FeedMedia({
    super.key,
    required this.photoUrl,
    required this.photoUrls,
    required this.strings,
    this.thumbUrl,
  });

  final String photoUrl;
  final String? thumbUrl;
  final List<String> photoUrls;
  final AppStrings strings;

  @override
  State<FeedMedia> createState() => _FeedMediaState();
}

class _FeedMediaState extends State<FeedMedia> {
  final PageController _controller = PageController();
  int _index = 0;

  List<String> get _photos {
    final urls =
        widget.photoUrls.where((url) => url.trim().isNotEmpty).toList();
    if (urls.isEmpty) urls.add(widget.photoUrl);
    final thumb = widget.thumbUrl?.trim();
    if (thumb != null && thumb.isNotEmpty) urls[0] = thumb;
    return urls;
  }

  @override
  void didUpdateWidget(covariant FeedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl ||
        oldWidget.photoUrls != widget.photoUrls) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final next = (_index + delta).clamp(0, _photos.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photos = _photos;
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return LayoutBuilder(builder: (context, constraints) {
      final height = math.min(constraints.maxWidth * (mobile ? 0.84 : 0.58),
          mobile ? 380.0 : 420.0);
      return SizedBox(
        key: const ValueKey('feed-media'),
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          PageView.builder(
            controller: _controller,
            itemCount: photos.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => ColoredBox(
              color: colors.surfaceContainerLow,
              child: Image.network(
                photos[index],
                fit: BoxFit.contain,
                width: double.infinity,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 36, color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ),
          if (photos.length > 1) ...[
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: Semantics(
                label:
                    '${widget.strings.photos}: ${_index + 1}/${photos.length}',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.inverseSurface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Text(
                      '${_index + 1}/${photos.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colors.onInverseSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            if (_index > 0)
              Positioned(
                left: AppSpacing.sm,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _GalleryArrow(
                    icon: Icons.chevron_left,
                    tooltip: widget.strings.previousPhoto,
                    onPressed: () => _move(-1),
                  ),
                ),
              ),
            if (_index < photos.length - 1)
              Positioned(
                right: AppSpacing.sm,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _GalleryArrow(
                    icon: Icons.chevron_right,
                    tooltip: widget.strings.nextPhoto,
                    onPressed: () => _move(1),
                  ),
                ),
              ),
          ],
        ]),
      );
    });
  }
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

enum FeedKind { needsHelp, lostPet, rehoming }

class FeedKindBadge extends StatelessWidget {
  const FeedKindBadge({super.key, required this.kind, required this.label});

  final FeedKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (kind) {
      FeedKind.needsHelp => (
          colors.tertiaryContainer,
          colors.onTertiaryContainer,
          Icons.warning_amber_rounded,
        ),
      FeedKind.lostPet => (
          colors.errorContainer,
          colors.onErrorContainer,
          Icons.search_rounded,
        ),
      FeedKind.rehoming => (
          colors.tertiaryContainer,
          colors.onTertiaryContainer,
          Icons.home_outlined,
        ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ]),
      ),
    );
  }
}

class FeedPetTitle extends StatelessWidget {
  const FeedPetTitle({super.key, required this.name, this.badge});

  final String name;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (badge != null) badge!,
        ],
      );
}

class FeedBodyText extends StatefulWidget {
  const FeedBodyText({super.key, required this.text, required this.strings});

  final String text;
  final AppStrings strings;

  @override
  State<FeedBodyText> createState() => _FeedBodyTextState();
}

class _FeedBodyTextState extends State<FeedBodyText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant FeedBodyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final textStyle = Theme.of(context).textTheme.bodyMedium!;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 3,
          ellipsis: '…',
        )..layout(maxWidth: constraints.maxWidth);
        final truncated = painter.didExceedMaxLines;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: textStyle,
          ),
          if (truncated || _expanded)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded
                  ? widget.strings.showLess
                  : widget.strings.readMore),
            ),
        ]);
      });
}

class FeedCountAction extends StatelessWidget {
  const FeedCountAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 21,
                  color: active ? colors.error : colors.onSurfaceVariant),
              const SizedBox(width: 5),
              Text('$count', style: Theme.of(context).textTheme.labelLarge),
            ]),
          ),
        ),
      ),
    );
  }
}
