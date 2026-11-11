import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/mushukistan_api.dart';
import '../../auth/domain/auth_models.dart';

/// Page size of the profile's Saved posts list.
const savedPostsPageSize = 50;

/// First page of the viewer's saved posts, loaded fresh each time Saved posts
/// opens (auto-dispose). It does not reload on save/unsave or other post
/// changes while the screen is open, which would drop pages loaded with
/// Load more: unsaved posts are hidden through [savedPostOverridesProvider]
/// instead, and pull to refresh reloads.
final savedPostsProvider =
    FutureProvider.autoDispose<ApiPage<PostSummary>>((ref) async {
  return ref
      .watch(mushukistanApiProvider)
      .listSavedPosts(limit: savedPostsPageSize);
});

/// Only signed-in viewers can save, only cat posts (not Needs help), and not
/// their own posts (those are already under "My posts"). Same rule as the
/// server: a post whose author account is gone can still be saved.
///
/// Private posts (which only moderators see) cannot be saved either: the
/// server refuses them because the saved list would never show them.
bool canSavePost(PostSummary post, MushukistanUser? viewer) =>
    viewer != null &&
    post.kind == 'observation' &&
    post.author?.id != viewer.id &&
    !(post is PostDetail && !post.isPublic);

/// Saved state as the viewer last set it, falling back to the server value.
/// Watches only this post's entry, so toggling one post does not rebuild
/// every other card's menu.
bool isPostSaved(WidgetRef ref, PostSummary post) =>
    ref.watch(savedPostOverridesProvider.select((map) => map[post.id])) ??
    post.isSavedByMe;

/// Saves or unsaves [post] and confirms with a snack bar.
Future<void> toggleSavedPost(
  BuildContext context,
  WidgetRef ref,
  PostSummary post,
) async {
  // The menu that called this may be gone when the request finishes (card
  // scrolled away, page closed), so everything used after the request comes
  // from the app-wide container and messenger, not from the widget's ref.
  final container = ProviderScope.containerOf(context, listen: false);
  final strings = container.read(appStringsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final api = container.read(mushukistanApiProvider);
  final save = !(container.read(savedPostOverridesProvider)[post.id] ??
      post.isSavedByMe);
  try {
    if (save) {
      await api.savePost(post.id);
    } else {
      await api.unsavePost(post.id);
    }
    container.read(savedPostOverridesProvider.notifier).state = {
      ...container.read(savedPostOverridesProvider),
      post.id: save,
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(save ? strings.postSaved : strings.postRemovedFromSaved),
      ));
  } on MushukistanApiException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.userMessage)));
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text(strings.couldNotSaveChanges)),
    );
  }
}
