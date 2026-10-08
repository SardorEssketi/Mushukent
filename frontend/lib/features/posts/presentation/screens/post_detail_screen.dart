import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../comments/presentation/screens/comments_screen.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/presentation/screens/user_activity_screen.dart';

final postDetailProvider =
    FutureProvider.autoDispose.family<PostDetail, String>((ref, postId) async {
  ref.watch(postMutationRevisionProvider);
  final includeViewerContext = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
  return ref.watch(mushukistanApiProvider).getPost(
        postId,
        includeViewerContext: includeViewerContext,
      );
});

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen(
      {super.key, required this.postId, this.focusComments = false});

  final String postId;
  final bool focusComments;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  bool _submittingLike = false;
  bool? _likedOverride;
  int? _likeCountOverride;

  Future<void> _handlePostAction({
    required _PostAction action,
    required PostDetail post,
    required bool isOwner,
    required bool isModerator,
    required AppStrings strings,
  }) async {
    if (action == _PostAction.edit) {
      await context.push<bool>('/posts/${post.id}/edit');
      if (mounted) {
        ref.invalidate(postDetailProvider(widget.postId));
      }
      return;
    }
    if (action == _PostAction.history) {
      await context.push('/moderation/posts/${post.id}/history');
      return;
    }

    final deletingAsModerator = !isOwner && isModerator;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          deletingAsModerator
              ? strings.removePostAsModerator
              : strings.deletePost,
        ),
        content: Text(strings.deleteCommentMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      if (deletingAsModerator) {
        await ref.read(mushukistanApiProvider).deleteModerationPost(post.id);
      } else {
        await ref.read(mushukistanApiProvider).deleteObservation(post.id);
      }
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        ref.invalidate(userPostsProvider(userId));
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.pop(true);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(strings.postDeleted)));
      }
    } on MushukistanApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    }
  }

  Future<void> _toggleLike(PostDetail post) async {
    if (_submittingLike) {
      return;
    }
    if (!ref.read(authControllerProvider).isAuthenticated) {
      requestAuthentication(context);
      return;
    }

    final isLiked = _likedOverride ?? post.isLikedByMe;
    final currentLikeCount = _likeCountOverride ?? post.likeCount;

    setState(() {
      _submittingLike = true;
    });

    try {
      if (isLiked) {
        await ref.read(mushukistanApiProvider).unlikePost(widget.postId);
        final nextCount = (currentLikeCount - 1).clamp(0, 1 << 30);
        setState(() {
          _likedOverride = false;
          _likeCountOverride = nextCount;
        });
        setPostLikeOverride(
          ref,
          widget.postId,
          liked: false,
          likeCount: nextCount,
        );
      } else {
        final result =
            await ref.read(mushukistanApiProvider).likePost(widget.postId);
        setState(() {
          _likedOverride = result.liked;
          _likeCountOverride = result.likeCount;
        });
        setPostLikeOverride(
          ref,
          widget.postId,
          liked: result.liked,
          likeCount: result.likeCount,
        );
      }

      ref.invalidate(postDetailProvider(widget.postId));
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      ref.invalidate(leaderboardProvider);
    } on MushukistanApiException catch (error) {
      if (!isLiked && error.code == 'ALREADY_LIKED') {
        final nextCount = currentLikeCount + 1;
        setState(() {
          _likedOverride = true;
          _likeCountOverride = nextCount;
        });
        setPostLikeOverride(
          ref,
          widget.postId,
          liked: true,
          likeCount: nextCount,
        );
      } else {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submittingLike = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final postAsync = ref.watch(postDetailProvider(widget.postId));
    final strings = ref.watch(appStringsProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(postAsync.asData?.value.kind == 'needs_help'
            ? strings.needsHelp
            : strings.catObservation),
      ),
      body: postAsync.when(
        data: (post) {
          final likeOverride = ref.watch(postLikeOverridesProvider)[post.id];
          final isLiked =
              likeOverride?.liked ?? _likedOverride ?? post.isLikedByMe;
          final likeCount =
              likeOverride?.likeCount ?? _likeCountOverride ?? post.likeCount;
          final author = post.author;
          final authorId = author?.id;
          final authorName = author?.name ?? strings.anonymous;
          final isOwner = authorId != null && authorId == currentUser?.id;
          final isModerator = currentUser?.isModerator == true;
          final isEdited = post.isEdited;
          final kindBadge =
              post.kind == 'needs_help' ? strings.needsHelp : null;
          final needsHelp = post.kind == 'needs_help';
          final catName = post.cat.name?.trim();
          final hasName = catName != null &&
              catName.isNotEmpty &&
              catName.toLowerCase() != strings.unnamedCat.toLowerCase() &&
              catName.toLowerCase() != 'unknown';
          final location = post.location;
          final description = post.description?.trim();
          return AppContentWidth(
              maxWidth: AppWidths.readable,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        child: _PostDetailGallery(photoUrls: post.photoUrls),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (kindBadge != null) ...[
                              _StatusBadge(label: kindBadge),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            Text(
                                hasName
                                    ? catName
                                    : needsHelp
                                        ? strings.needsHelp
                                        : strings.catObservation,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _AuthorLink(
                                        authorName: authorName,
                                        onTap: authorId == null
                                            ? null
                                            : () => context.push(
                                                  '/users/$authorId',
                                                ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${strings.published}: ${_formatDate(post.createdAt)}${isEdited ? ' • ${strings.edited}' : ''}',
                                        softWrap: true,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (location != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              Card(
                                child: ListTile(
                                  leading: Icon(Icons.location_on_outlined,
                                      color: needsHelp
                                          ? Theme.of(context)
                                              .colorScheme
                                              .tertiary
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary),
                                  title: Text(strings.location),
                                  subtitle: Text(strings.viewOnMap),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => context.go(
                                    '/map?lat=${location.latitude}&lon=${location.longitude}',
                                  ),
                                ),
                              ),
                            ],
                            if (description != null &&
                                description.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.lg),
                              if (needsHelp) ...[
                                Text(strings.helpNeededSection,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                              Text(description),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isOwner || isModerator) ...[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (isOwner)
                          OutlinedButton.icon(
                            onPressed: () => _handlePostAction(
                              action: _PostAction.edit,
                              post: post,
                              isOwner: isOwner,
                              isModerator: isModerator,
                              strings: strings,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(strings.editObservation),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _handlePostAction(
                            action: _PostAction.delete,
                            post: post,
                            isOwner: isOwner,
                            isModerator: isModerator,
                            strings: strings,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(isOwner
                              ? strings.deletePost
                              : strings.removePostAsModerator),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                        ),
                        if (isModerator)
                          OutlinedButton.icon(
                            onPressed: () => _handlePostAction(
                              action: _PostAction.history,
                              post: post,
                              isOwner: isOwner,
                              isModerator: isModerator,
                              strings: strings,
                            ),
                            icon: const Icon(Icons.history),
                            label: Text(strings.postHistory),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _submittingLike ? null : () => _toggleLike(post),
                        icon: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_outline,
                        ),
                        label: Text(
                            '${isLiked ? strings.unlike : strings.like} $likeCount'),
                      ),
                      Chip(
                        avatar:
                            const Icon(Icons.mode_comment_outlined, size: 18),
                        label: Text('${strings.comments} ${post.commentCount}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.push(
                          Uri(
                            path: '/report',
                            queryParameters: {
                              'type': 'post',
                              'id': widget.postId,
                              'label': post.cat.name ?? post.description ?? '',
                            },
                          ).toString(),
                        ),
                        icon: const Icon(Icons.flag_outlined),
                        label: Text(strings.report),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  CommentDeepLinkFocus(
                    focus: widget.focusComments,
                    child: PostCommentsSection(
                        postId: widget.postId, padding: EdgeInsets.zero),
                  ),
                ],
              ));
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.post,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () => ref.invalidate(postDetailProvider(widget.postId)),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }
}

enum _PostAction { edit, delete, history }

class _AuthorLink extends StatelessWidget {
  const _AuthorLink({
    required this.authorName,
    required this.onTap,
  });

  final String authorName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    if (onTap == null) {
      return Text(
        authorName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PostDetailGallery extends StatefulWidget {
  const _PostDetailGallery({required this.photoUrls});

  final List<String> photoUrls;

  @override
  State<_PostDetailGallery> createState() => _PostDetailGalleryState();
}

class _PostDetailGalleryState extends State<_PostDetailGallery> {
  late final PageController _controller = PageController();
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 700;
    return AspectRatio(
      aspectRatio: desktop ? 4 / 3 : 1.2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photoUrls.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) {
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: AppRemoteImage(
                  widget.photoUrls[index],
                  fit: desktop ? BoxFit.contain : BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.image_not_supported_outlined, size: 48),
                  ),
                ),
              );
            },
          ),
          if (widget.photoUrls.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: _GalleryArrow(
                icon: Icons.chevron_left,
                onPressed: _index == 0 ? null : () => _move(-1),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: _GalleryArrow(
                icon: Icons.chevron_right,
                onPressed: _index == widget.photoUrls.length - 1
                    ? null
                    : () => _move(1),
              ),
            ),
          ],
        ],
      ),
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
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
