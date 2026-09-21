import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
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
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

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
        context.pop(true);
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
      appBar: AppBar(title: Text(strings.observation)),
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PostDetailGallery(photoUrls: post.photoUrls),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  post.cat.name ?? strings.unnamedCat,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                ),
                              ),
                              if (kindBadge != null) ...[
                                const SizedBox(width: 8),
                                _StatusBadge(label: kindBadge),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(post.description?.trim().isNotEmpty == true
                              ? post.description!.trim()
                              : strings.noDescription),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _StatCard(
                                label: strings.likes,
                                value: likeCount.toString(),
                              ),
                              _StatCard(
                                label: strings.comments,
                                value: post.commentCount.toString(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                        foregroundColor: Theme.of(context).colorScheme.error,
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
                    onPressed: _submittingLike ? null : () => _toggleLike(post),
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_outline,
                    ),
                    label: Text(isLiked ? strings.unlike : strings.like),
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
              PostCommentsSection(
                  postId: widget.postId, padding: EdgeInsets.zero),
            ],
          );
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
                child: Image.network(
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
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
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
