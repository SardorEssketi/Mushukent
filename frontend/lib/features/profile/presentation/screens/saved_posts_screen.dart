import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../posts/application/saved_posts.dart';

/// The signed-in user's saved cat posts, most recently saved first. Private:
/// only the owner can open it (Profile → Saved posts).
class SavedPostsScreen extends ConsumerStatefulWidget {
  const SavedPostsScreen({super.key});

  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen> {
  ApiPage<PostSummary>? _firstPage;
  final List<PostSummary> _more = [];
  String? _nextCursor;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  void _syncWithFirstPage(ApiPage<PostSummary> page) {
    if (identical(page, _firstPage)) return;
    _forgetOverridesConfirmedBy(page.items);
    _firstPage = page;
    _more.clear();
    _nextCursor = page.nextCursor;
    _loadMoreFailed = false;
  }

  /// A fresh server page is the truth for the posts in it: they are saved
  /// (perhaps again, from another device), so local "unsaved" marks for them
  /// are dropped instead of hiding them.
  void _forgetOverridesConfirmedBy(List<PostSummary> posts) {
    final overrides = ref.read(savedPostOverridesProvider);
    final stale = {
      for (final post in posts)
        if (overrides[post.id] == false) post.id,
    };
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(savedPostOverridesProvider);
      ref.read(savedPostOverridesProvider.notifier).state = {
        for (final entry in current.entries)
          if (!stale.contains(entry.key)) entry.key: entry.value,
      };
    });
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
      final page = await ref
          .read(mushukistanApiProvider)
          .listSavedPosts(limit: savedPostsPageSize, cursor: cursor);
      if (!mounted || !identical(firstPage, _firstPage)) return;
      final known = {
        for (final post in firstPage.items) post.id,
        for (final post in _more) post.id,
      };
      setState(() {
        _more.addAll(page.items.where((post) => !known.contains(post.id)));
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

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final overrides = ref.watch(savedPostOverridesProvider);
    final postsAsync = ref.watch(savedPostsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.savedPosts)),
      body: postsAsync.when(
        skipLoadingOnReload: true,
        data: (page) {
          _syncWithFirstPage(page);
          // A post unsaved here disappears at once, before the list reloads.
          final posts = [
            for (final post in [...page.items, ..._more])
              if (overrides[post.id] != false) post,
          ];
          if (posts.isEmpty && _nextCursor == null) {
            return RefreshIndicator(
              onRefresh: () => ref.refresh(savedPostsProvider.future),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          strings.noSavedPostsYet,
                          key: const ValueKey('saved-posts-empty'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final hasFooter = _nextCursor != null;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(savedPostsProvider.future),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
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
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.couldNotLoadSection),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(savedPostsProvider),
                child: Text(strings.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
