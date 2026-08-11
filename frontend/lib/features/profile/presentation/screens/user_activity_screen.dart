import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../feed/presentation/screens/feed_screen.dart';

final userPostsProvider = FutureProvider.autoDispose
    .family<ApiPage<PostSummary>, String>((ref, userId) async {
  return ref.watch(mushukistanApiProvider).listUserPosts(userId, limit: 50);
});

final userCommentsProvider = FutureProvider.autoDispose
    .family<ApiPage<CommentData>, String>((ref, userId) async {
  return ref.watch(mushukistanApiProvider).listUserComments(userId, limit: 50);
});

class UserPostsScreen extends ConsumerWidget {
  const UserPostsScreen({
    super.key,
    required this.userId,
    required this.isCurrentUser,
  });

  final String userId;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final postsAsync = ref.watch(userPostsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
            isCurrentUser ? strings.myObservations : strings.userObservations),
      ),
      body: postsAsync.when(
        data: (page) {
          if (page.items.isEmpty) {
            return Center(child: Text(strings.noObservationsYet));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: page.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final post = page.items[index];
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
          fallbackMessage: error.toString(),
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
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(
                    comment.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatDate(comment.createdAt)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/posts/${comment.postId}'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ActivityError(
          error: error,
          fallbackMessage: error.toString(),
        ),
      ),
    );
  }
}

class _ActivityError extends ConsumerWidget {
  const _ActivityError({
    required this.error,
    required this.fallbackMessage,
  });

  final Object error;
  final String fallbackMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final message = error is MushukistanApiException &&
            (error as MushukistanApiException).code == 'ACTIVITY_PRIVATE'
        ? strings.noActivityVisible
        : fallbackMessage;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
