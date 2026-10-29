import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_remote_image.dart';

/// Horizontal gutter shared by the Feed header, filters and cards so they all
/// align on one column edge. Phones use a narrower gutter to give photos room.
double feedGutter(BuildContext context) =>
    MediaQuery.sizeOf(context).width < AppWidths.compact
        ? AppSpacing.md
        : AppSpacing.lg;

/// Inset of the text block under the media; aligns with the author header.
const feedBodyPadding =
    EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0);

/// Inset of the action row; the 48px targets carry their own breathing room,
/// so the first icon still lines up with the body text.
const feedActionsPadding =
    EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.xs);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
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
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(children: [
        InkWell(
          onTap: onAuthorTap,
          borderRadius: BorderRadius.circular(24),
          child: FeedAuthorAvatar(name: name, avatarUrl: author?.avatarUrl),
        ),
        const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
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
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.2,
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
      radius: 18,
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
      child: AppRemoteImage(
        url,
        width: 36,
        height: 36,
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
      // The API has no photo dimensions, so the frame is fixed (no layout
      // shift when images arrive): near-square on phones, height-capped on
      // wider layouts. Photos stay contained, never cropped; a blurred copy
      // of the same photo fills the remaining space.
      final height = math.min(
          constraints.maxWidth * (mobile ? 0.9 : 0.6), mobile ? 380.0 : 420.0);
      return SizedBox(
        key: const ValueKey('feed-media'),
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          PageView.builder(
            controller: _controller,
            itemCount: photos.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => ColoredBox(
              color: colors.surfaceContainer,
              child: Stack(fit: StackFit.expand, children: [
                _PhotoBackdrop(url: photos[index]),
                AppRemoteImage(
                  photos[index],
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        size: 36, color: colors.onSurfaceVariant),
                  ),
                ),
              ]),
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

/// Soft, blurred fill behind a contained photo so letterbox space reads as
/// part of the picture instead of an empty band.
///
/// It listens to the same [NetworkImage] the foreground [Image.network] uses,
/// so the bytes and decoded frame come from the shared image cache (no extra
/// request or decode). The blurred fill is rendered once per photo and frame
/// size into a tiny bitmap (see [renderFeedBackdrop]) and then drawn as a
/// plain scaled image: a live blur layer would cost two offscreen passes per
/// visible photo on every frame. Failed loads simply leave the neutral frame.
class _PhotoBackdrop extends StatefulWidget {
  const _PhotoBackdrop({required this.url});

  final String url;

  @override
  State<_PhotoBackdrop> createState() => _PhotoBackdropState();
}

class _PhotoBackdropState extends State<_PhotoBackdrop> {
  ImageStream? _stream;
  ImageInfo? _info;
  ui.Image? _blurred;
  Size? _blurredSize;
  double? _blurredRatio;
  int _renderGeneration = 0;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      if (!mounted) {
        info.dispose();
        return;
      }
      setState(() {
        _info?.dispose();
        _info = info;
        _clearBlurred();
      });
    },
    onError: (_, __) {},
  );

  void _clearBlurred() {
    _renderGeneration++;
    _blurred?.dispose();
    _blurred = null;
    _blurredSize = null;
    _blurredRatio = null;
  }

  /// Renders the fill for [size] once; rebuilds draw the cached bitmap.
  void _ensureBlurred(Size size, double pixelRatio) {
    final info = _info;
    if (info == null ||
        size.isEmpty ||
        (_blurredSize == size && _blurredRatio == pixelRatio)) {
      return;
    }
    _blurredSize = size;
    _blurredRatio = pixelRatio;
    final generation = ++_renderGeneration;
    renderFeedBackdrop(info.image, size, pixelRatio).then((image) {
      if (!mounted || generation != _renderGeneration) {
        image.dispose();
        return;
      }
      setState(() {
        _blurred?.dispose();
        _blurred = image;
      });
    }, onError: (Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PhotoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _info?.dispose();
      _info = null;
      _clearBlurred();
      _resolve();
    }
  }

  void _resolve() {
    final stream = NetworkImage(widget.url)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    _clearBlurred();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_info == null) return const SizedBox.shrink();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scrim = dark
        ? Colors.black.withValues(alpha: 0.4)
        : Theme.of(context).colorScheme.surface.withValues(alpha: 0.35);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: ClipRect(
          child: LayoutBuilder(builder: (context, constraints) {
            _ensureBlurred(constraints.biggest, pixelRatio);
            final blurred = _blurred;
            if (blurred == null) return const SizedBox.shrink();
            return Stack(fit: StackFit.expand, children: [
              // Overscaled so the blur's soft edge falls outside the clip.
              OverflowBox(
                maxWidth: constraints.maxWidth * feedBackdropOverscale,
                maxHeight: constraints.maxHeight * feedBackdropOverscale,
                child: RawImage(
                  image: blurred,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.low,
                ),
              ),
              ColoredBox(color: scrim),
            ]);
          }),
        ),
      ),
    );
  }
}

/// The backdrop is drawn at 1/8 of the frame, blurred there, and enlarged
/// with bilinear filtering; [feedBackdropOverscale] pushes its soft edge
/// outside the clip.
const feedBackdropDownscale = 8.0;
const feedBackdropOverscale = 1.3;
const feedBackdropSigma = 4.0;

/// Renders the blurred fill for a frame of [frameSize] (logical pixels) once:
/// [source] is cover-fitted into a 1/[feedBackdropDownscale] surface and
/// blurred with [feedBackdropSigma] logical pixels, at device resolution.
@visibleForTesting
Future<ui.Image> renderFeedBackdrop(
  ui.Image source,
  Size frameSize,
  double pixelRatio,
) {
  final small = frameSize / feedBackdropDownscale * pixelRatio;
  final width = math.max(1, small.width.ceil());
  final height = math.max(1, small.height.ceil());
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final sigma = feedBackdropSigma * pixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, rect);
  canvas.saveLayer(
    rect,
    Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
  );
  paintImage(
    canvas: canvas,
    rect: rect,
    image: source,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
  );
  canvas.restore();
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
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
    // A 36px disc keeps the control light over the photo; the padded tap
    // target still gives a 48px hit area.
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: colors.surface.withValues(alpha: 0.88),
        foregroundColor: colors.onSurface,
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: AppSpacing.xs),
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
              // Flush with the description and no taller than a text line
              // plus a comfortable target, instead of a full button row.
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: AlignmentDirectional.centerStart,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded
                  ? widget.strings.showLess
                  : widget.strings.readMore),
            ),
        ]);
      });
}

/// How many people opened the post (ADR-0024). Display only, so it is not a
/// tap target; it lines up with the like and comment counts.
class FeedViewCount extends StatelessWidget {
  const FeedViewCount({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        label: '$label: $count',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.visibility_outlined,
                  size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ]),
          ),
        ),
      ),
    );
  }
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
              const SizedBox(width: 6),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color:
                          active ? colors.onSurface : colors.onSurfaceVariant,
                    ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
