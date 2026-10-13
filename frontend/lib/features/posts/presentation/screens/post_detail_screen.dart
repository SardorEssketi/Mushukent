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
import '../../../feed/presentation/widgets/feed_card_parts.dart';
import '../widgets/publication_detail_parts.dart';
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
  final GlobalKey _commentsKey = GlobalKey();

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

  void _openComments() {
    final target = _commentsKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: AppMotion.of(target, const Duration(milliseconds: 300)),
      curve: AppMotion.curve,
      alignment: 0.04,
    );
  }

  void _report(PostDetail post) {
    context.push(
      Uri(
        path: '/report',
        queryParameters: {
          'type': 'post',
          'id': widget.postId,
          'label': post.cat.name ?? post.description ?? '',
        },
      ).toString(),
    );
  }

  List<PublicationMenuEntry<_PostAction>> _menuEntries({
    required AppStrings strings,
    required bool isOwner,
    required bool isModerator,
  }) {
    return [
      if (isOwner)
        PublicationMenuEntry(
          value: _PostAction.edit,
          label: strings.editObservation,
          icon: Icons.edit_outlined,
        ),
      if (isModerator)
        PublicationMenuEntry(
          value: _PostAction.history,
          label: strings.postHistory,
          icon: Icons.history,
        ),
      if (!isOwner)
        PublicationMenuEntry(
          value: _PostAction.report,
          label: strings.report,
          icon: Icons.flag_outlined,
        ),
      if (isOwner || isModerator)
        PublicationMenuEntry(
          value: _PostAction.delete,
          label: isOwner ? strings.deletePost : strings.removePostAsModerator,
          icon: Icons.delete_outline,
          destructive: true,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final postAsync = ref.watch(postDetailProvider(widget.postId));
    final strings = ref.watch(appStringsProvider);
    final currentUser = ref.watch(currentUserProvider);
    final loaded = postAsync.asData?.value;
    final loadedAuthorId = loaded?.author?.id;
    final isOwner = loadedAuthorId != null && loadedAuthorId == currentUser?.id;
    final isModerator = currentUser?.isModerator == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(loaded?.kind == 'needs_help'
            ? strings.needsHelp
            : strings.catObservation),
        actions: [
          if (loaded != null)
            PublicationActionsMenu<_PostAction>(
              tooltip: strings.postActions,
              entries: _menuEntries(
                strings: strings,
                isOwner: isOwner,
                isModerator: isModerator,
              ),
              onSelected: (action) {
                if (action == _PostAction.report) {
                  _report(loaded);
                  return;
                }
                _handlePostAction(
                  action: action,
                  post: loaded,
                  isOwner: isOwner,
                  isModerator: isModerator,
                  strings: strings,
                );
              },
            ),
        ],
      ),
      body: postAsync.when(
        data: (post) {
          final likeOverride = ref.watch(postLikeOverridesProvider)[post.id];
          final isLiked =
              likeOverride?.liked ?? _likedOverride ?? post.isLikedByMe;
          final likeCount =
              likeOverride?.likeCount ?? _likeCountOverride ?? post.likeCount;
          final authorId = post.author?.id;
          final needsHelp = post.kind == 'needs_help';
          final catName = post.cat.name?.trim();
          final hasName = catName != null &&
              catName.isNotEmpty &&
              catName.toLowerCase() != strings.unnamedCat.toLowerCase() &&
              catName.toLowerCase() != 'unknown';
          final location = post.location;
          final description = post.description?.trim();
          final colors = Theme.of(context).colorScheme;
          return PublicationDetailLayout(
            commentsKey: _commentsKey,
            gallery: PublicationGallery(photoUrls: post.photoUrls),
            details: [
              PublicationAuthorRow(
                author: post.author,
                createdAt: post.createdAt,
                isEdited: post.isEdited,
                strings: strings,
                onAuthorTap: authorId == null
                    ? null
                    : () => context.push('/users/$authorId'),
              ),
              const SizedBox(height: AppSpacing.md),
              PublicationTitle(
                title: hasName
                    ? catName
                    : needsHelp
                        ? strings.needsHelp
                        : strings.catObservation,
                badge: needsHelp
                    ? FeedKindBadge(
                        kind: FeedKind.needsHelp,
                        label: strings.needsHelp,
                      )
                    : null,
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                if (needsHelp)
                  PublicationCallout(
                    icon: Icons.volunteer_activism_outlined,
                    color: colors.tertiary,
                    title: strings.helpNeededSection,
                    body: description,
                  )
                else
                  Text(
                    description,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.45),
                  ),
              ],
              if (location != null) ...[
                const SizedBox(height: AppSpacing.sm),
                PublicationChip(
                  icon: Icons.location_on_outlined,
                  color: needsHelp ? colors.tertiary : colors.primary,
                  label: strings.viewOnMap,
                  onTap: () => context.go(
                    '/map?lat=${location.latitude}&lon=${location.longitude}',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              PublicationEngagementBar(
                strings: strings,
                liked: isLiked,
                likeCount: likeCount,
                commentCount: post.commentCount,
                onLike: _submittingLike ? null : () => _toggleLike(post),
                onComments: _openComments,
              ),
            ],
            comments: CommentDeepLinkFocus(
              focus: widget.focusComments,
              child: PostCommentsSection(
                postId: widget.postId,
                padding: EdgeInsets.zero,
              ),
            ),
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

enum _PostAction { edit, delete, history, report }
