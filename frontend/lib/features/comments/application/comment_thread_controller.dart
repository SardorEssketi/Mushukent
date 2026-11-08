import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/mushukistan_api.dart';

/// Loads one page of a publication's comments, oldest first.
typedef CommentPageLoader = Future<ApiPage<CommentData>> Function(
  MushukistanApi api,
  String targetId,
  String? cursor,
);

/// The comments loaded so far for one publication.
///
/// [items] are unique by id and ordered like the API (`created_at`, then id,
/// ascending), so pages, refreshes and locally applied mutations can be
/// merged without duplicates. Visibility (deleted, blocked, private) is
/// decided by the API; this state only holds what it returned.
class CommentThread {
  const CommentThread({
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<CommentData> items;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  CommentThread copyWith({
    List<CommentData>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return CommentThread(
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Paginated comment thread with explicit continuation.
///
/// Refreshing (invalidation) reloads the first page only. Create, edit and
/// delete are applied to the loaded items instead of reloading the thread,
/// so the pages already loaded and the comment identities stay intact.
class CommentThreadController
    extends AutoDisposeFamilyAsyncNotifier<CommentThread, String> {
  CommentThreadController(this._loadPage);

  final CommentPageLoader _loadPage;
  int _generation = 0;

  @override
  Future<CommentThread> build(String targetId) async {
    // A refresh or disposal invalidates continuation loads started before
    // it; their late results are dropped without touching the state.
    _generation++;
    ref.onDispose(() => _generation++);
    final page = await _loadPage(
      ref.watch(mushukistanApiProvider),
      targetId,
      null,
    );
    return CommentThread(
      items: mergeComments(const <CommentData>[], page.items),
      nextCursor: page.nextCursor,
    );
  }

  /// Loads the next page; no-op while a load runs or at the end.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    final generation = _generation;
    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final page = await _loadPage(
        ref.read(mushukistanApiProvider),
        arg,
        current.nextCursor,
      );
      if (generation != _generation) return;
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          items: mergeComments(latest.items, page.items),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          loadingMore: false,
          clearLoadMoreError: true,
        ),
      );
    } catch (error) {
      if (generation != _generation) return;
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(loadingMore: false, loadMoreError: error),
      );
    }
  }

  /// Shows a comment the viewer just created, then loads any pages still
  /// between the loaded ones and it, so it appears in its real position.
  Future<void> addCreated(CommentData comment, {int maxPages = 20}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final generation = _generation;
    state = AsyncData(
      current.copyWith(items: mergeComments(current.items, [comment])),
    );
    for (var pages = 0; pages < maxPages; pages++) {
      if (generation != _generation) return;
      final latest = state.valueOrNull;
      if (latest == null || !latest.hasMore || latest.loadMoreError != null) {
        return;
      }
      await loadMore();
    }
  }

  void replace(CommentData comment) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: [
          for (final item in current.items)
            item.id == comment.id ? comment : item,
        ],
      ),
    );
  }

  void remove(String commentId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: current.items
            .where((item) => item.id != commentId)
            .toList(growable: false),
      ),
    );
  }
}

/// Merges [incoming] into [existing]: unique by id (incoming wins), ordered
/// by creation time then id, matching the API's ascending keyset order.
List<CommentData> mergeComments(
  List<CommentData> existing,
  List<CommentData> incoming,
) {
  final byId = <String, CommentData>{
    for (final comment in existing) comment.id: comment,
  };
  for (final comment in incoming) {
    byId[comment.id] = comment;
  }
  final merged = byId.values.toList();
  merged.sort((a, b) {
    final byTime = a.createdAt.toUtc().compareTo(b.createdAt.toUtc());
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return List<CommentData>.unmodifiable(merged);
}
