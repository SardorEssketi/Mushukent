import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../auth/application/auth_controller.dart';

/// Which of a user's posts a [UserPostsScreen] lists.
///
/// [kind] is a backend post kind (`observation` or `needs_help`); null lists
/// every kind together.
typedef UserPostsQuery = ({String userId, String? kind});

const _userPostsPageSize = 50;

final userPostsProvider = FutureProvider.autoDispose
    .family<ApiPage<PostSummary>, UserPostsQuery>((ref, query) async {
  ref.watch(postMutationRevisionProvider);
  final includeViewerContext = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
  return ref.watch(mushukistanApiProvider).listUserPosts(
        query.userId,
        limit: _userPostsPageSize,
        includeViewerContext: includeViewerContext,
        kind: query.kind,
      );
});

final userCommentsProvider = FutureProvider.autoDispose
    .family<ApiPage<CommentData>, String>((ref, userId) async {
  ref.watch(postMutationRevisionProvider);
  final includeViewerContext = ref.watch(
    authControllerProvider.select((state) => state.isAuthenticated),
  );
  return ref.watch(mushukistanApiProvider).listUserComments(
        userId,
        limit: 50,
        includeViewerContext: includeViewerContext,
      );
});

class UserPostsScreen extends ConsumerStatefulWidget {
  const UserPostsScreen({
    super.key,
    required this.userId,
    required this.isCurrentUser,
    this.kind,
  });

  final String userId;
  final bool isCurrentUser;

  /// Backend post kind to list (`observation` or `needs_help`); null lists
  /// every kind.
  final String? kind;

  @override
  ConsumerState<UserPostsScreen> createState() => _UserPostsScreenState();
}

class _UserPostsScreenState extends ConsumerState<UserPostsScreen> {
  /// The first page that [_morePosts] and [_nextCursor] continue. When the
  /// provider delivers a different first page (refresh, mutation), the extra
  /// pages belong to a stale list and are dropped.
  ApiPage<PostSummary>? _firstPage;
  final List<PostSummary> _morePosts = [];
  String? _nextCursor;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  UserPostsQuery get _query => (userId: widget.userId, kind: widget.kind);

  void _syncWithFirstPage(ApiPage<PostSummary> page) {
    if (identical(page, _firstPage)) return;
    _firstPage = page;
    _morePosts.clear();
    _nextCursor = page.nextCursor;
    _loadMoreFailed = false;
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final firstPage = _firstPage;
    if (_loadingMore || cursor == null || firstPage == null) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await ref.read(mushukistanApiProvider).listUserPosts(
            widget.userId,
            limit: _userPostsPageSize,
            cursor: cursor,
            includeViewerContext:
                ref.read(authControllerProvider).isAuthenticated,
            kind: widget.kind,
          );
      if (!mounted || !identical(firstPage, _firstPage)) return;
      final known = {
        for (final post in firstPage.items) post.id,
        for (final post in _morePosts) post.id,
      };
      setState(() {
        _morePosts.addAll(page.items.where((post) => !known.contains(post.id)));
        _nextCursor = page.nextCursor;
      });
    } catch (_) {
      if (mounted && identical(firstPage, _firstPage)) {
        setState(() => _loadMoreFailed = true);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _title(AppStrings strings) {
    if (!widget.isCurrentUser) return strings.userObservations;
    return switch (widget.kind) {
      'observation' => strings.myCatPosts,
      'needs_help' => strings.myNeedsHelpPosts,
      _ => strings.myObservations,
    };
  }

  String _emptyMessage(AppStrings strings) => switch (widget.kind) {
        'observation' => strings.noCatPostsYet,
        'needs_help' => strings.noNeedsHelpPostsYet,
        _ => strings.noObservationsYet,
      };

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final postsAsync = ref.watch(userPostsProvider(_query));

    return Scaffold(
      appBar: AppBar(title: Text(_title(strings))),
      body: postsAsync.when(
        data: (page) {
          _syncWithFirstPage(page);
          final posts = [...page.items, ..._morePosts];
          if (posts.isEmpty) {
            return Center(child: Text(_emptyMessage(strings)));
          }
          final hasFooter = _nextCursor != null;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: posts.length + (hasFooter ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == posts.length) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: _loadingMore
                            ? const CircularProgressIndicator()
                            : TextButton(
                                onPressed: _loadMore,
                                child: Text(_loadMoreFailed
                                    ? strings.retry
                                    : strings.loadMorePosts),
                              ),
                      ),
                    );
                  }
                  final post = posts[index];
                  return FeedPostCard(
                    post: post,
                    onTap: () => context.push('/posts/${post.id}'),
                  );
                },
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ActivityError(
          error: error,
          fallbackMessage: strings.couldNotLoadSection,
          onRetry: () => ref.invalidate(userPostsProvider(_query)),
        ),
      ),
    );
  }
}

class UserCommentsScreen extends ConsumerWidget {
  const UserCommentsScreen({
    super.key,
    required this.userId,
    required this.isCurrentUser,
  });

  final String userId;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final commentsAsync = ref.watch(userCommentsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(isCurrentUser ? strings.myComments : strings.userComments),
      ),
      body: commentsAsync.when(
        data: (page) {
          if (page.items.isEmpty) {
            return Center(child: Text(strings.noCommentsYet));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: page.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final comment = page.items[index];
              final route = commentActivityRoute(comment);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(
                    comment.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatDate(comment.createdAt)),
                  trailing:
                      route == null ? null : const Icon(Icons.chevron_right),
                  onTap: route == null ? null : () => context.push(route),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ActivityError(
          error: error,
          fallbackMessage: strings.couldNotLoadSection,
          onRetry: () => ref.invalidate(userCommentsProvider(userId)),
        ),
      ),
    );
  }
}

class _ActivityError extends ConsumerWidget {
  const _ActivityError({
    required this.error,
    required this.fallbackMessage,
    required this.onRetry,
  });

  final Object error;
  final String fallbackMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final message = error is MushukistanApiException &&
            (error as MushukistanApiException).code == 'ACTIVITY_PRIVATE'
        ? strings.noActivityVisible
        : fallbackMessage;
    return AppStatePanel(
      icon: Icons.error_outline,
      title: message,
      action: message == strings.noActivityVisible
          ? null
          : FilledButton(onPressed: onRetry, child: Text(strings.retry)),
    );
  }
}

/// Detail route of the publication a comment belongs to.
///
/// A comment targets exactly one of an ordinary/Needs Help post, a Lost Pet
/// or an Adoption post; the other identifiers are null. Returns null when no
/// target identifier is present, so no `/posts/null` route is ever built.
/// Deleted, private or blocked targets are handled by the detail screens.
String? commentActivityRoute(CommentData comment) {
  String? present(String? id) {
    final value = id?.trim();
    return value == null || value.isEmpty ? null : Uri.encodeComponent(value);
  }

  final postId = present(comment.postId);
  if (postId != null) return '/posts/$postId';
  final lostPetId = present(comment.lostPetId);
  if (lostPetId != null) return '/lost-pets/$lostPetId';
  final adoptionPostId = present(comment.adoptionPostId);
  if (adoptionPostId != null) return '/adoption-posts/$adoptionPostId';
  return null;
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
