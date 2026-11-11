import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../posts/application/saved_posts.dart';
import '../../../posts/presentation/widgets/publication_detail_parts.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/presentation/screens/user_activity_screen.dart';
import '../screens/feed_screen.dart';

enum FeedCardAction { save, edit, history, report, delete }

/// The "more" menu at the top right of a feed card. It offers the same
/// actions as the app-bar menu on the publication's detail screen: the owner
/// can edit or delete, others can report, moderators can also remove (and see
/// a cat post's history). Renders nothing when the viewer has no actions.
class FeedCardMenu extends ConsumerWidget {
  const FeedCardMenu({super.key, required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Map-only items never appear as feed cards.
    if (item is! PostSummary &&
        item is! LostPetData &&
        item is! AdoptionPostData) {
      return const SizedBox.shrink();
    }
    final strings = ref.watch(appStringsProvider);
    final viewer = ref.watch(currentUserProvider);
    final authorId = _authorId(item);
    final isOwner = viewer != null && authorId != null && authorId == viewer.id;
    final isModerator = viewer?.isModerator == true;
    return PublicationActionsMenu<FeedCardAction>(
      key: ValueKey('feed-card-menu:${item.itemType}:${item.id}'),
      tooltip: strings.postActions,
      entries: [
        if (item case final PostSummary post when canSavePost(post, viewer))
          isPostSaved(ref, post)
              ? PublicationMenuEntry(
                  value: FeedCardAction.save,
                  label: strings.removeFromSaved,
                  icon: Icons.bookmark_remove_outlined,
                )
              : PublicationMenuEntry(
                  value: FeedCardAction.save,
                  label: strings.savePost,
                  icon: Icons.bookmark_add_outlined,
                ),
        if (isOwner)
          PublicationMenuEntry(
            value: FeedCardAction.edit,
            label: switch (item) {
              LostPetData() => strings.editLostPet,
              AdoptionPostData() => strings.editAdoptionPost,
              _ => strings.editObservation,
            },
            icon: Icons.edit_outlined,
          ),
        if (isModerator && item is PostSummary)
          PublicationMenuEntry(
            value: FeedCardAction.history,
            label: strings.postHistory,
            icon: Icons.history,
          ),
        if (!isOwner)
          PublicationMenuEntry(
            value: FeedCardAction.report,
            label: strings.report,
            icon: Icons.flag_outlined,
          ),
        if (isOwner || isModerator)
          PublicationMenuEntry(
            value: FeedCardAction.delete,
            label: !isOwner
                ? strings.removePostAsModerator
                : switch (item) {
                    LostPetData() => strings.deleteLostPet,
                    AdoptionPostData() => strings.deleteAdoptionPost,
                    _ => strings.deletePost,
                  },
            icon: Icons.delete_outline,
            destructive: true,
          ),
      ],
      onSelected: (action) => switch (action) {
        FeedCardAction.save =>
          toggleSavedPost(context, ref, item as PostSummary),
        FeedCardAction.edit => _edit(context, ref),
        FeedCardAction.history =>
          context.push('/moderation/posts/${item.id}/history'),
        FeedCardAction.report => _report(context),
        FeedCardAction.delete =>
          _delete(context, ref, strings, asModerator: !isOwner),
      },
    );
  }

  static String? _authorId(FeedItem item) => switch (item) {
        PostSummary(:final author) => author?.id,
        LostPetData(:final author) => author?.id,
        AdoptionPostData(:final author) => author?.id,
        _ => null,
      };

  String get _detailPath => switch (item) {
        LostPetData() => '/lost-pets/${item.id}',
        AdoptionPostData() => '/adoption-posts/${item.id}',
        _ => '/posts/${item.id}',
      };

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    // The card may be rebuilt or gone when the edit screen closes, so use the
    // app-wide container afterwards, not this widget's ref.
    final container = ProviderScope.containerOf(context, listen: false);
    final saved = await context.push<bool>('$_detailPath/edit');
    if (saved == true) {
      container.read(postMutationRevisionProvider.notifier).state++;
      container.invalidate(feedPostsProvider);
    }
  }

  void _report(BuildContext context) {
    final (type, label) = switch (item) {
      LostPetData(:final petName) => ('lost_pet', petName),
      AdoptionPostData(:final petName) => ('adoption_post', petName),
      PostSummary(:final cat, :final description) => (
          'post',
          cat.name ?? description ?? ''
        ),
      _ => ('', ''),
    };
    if (type.isEmpty) return;
    context.push(Uri(
      path: '/report',
      queryParameters: {'type': type, 'id': item.id, 'label': label},
    ).toString());
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings, {
    required bool asModerator,
  }) async {
    final (title, message) = switch (item) {
      LostPetData() => (strings.deleteLostPet, strings.deleteLostPetMessage),
      AdoptionPostData() => (
          strings.deleteAdoptionPost,
          strings.deleteAdoptionPostMessage
        ),
      _ => (strings.deletePost, strings.deleteCommentMessage),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(asModerator ? strings.removePostAsModerator : title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // The card can scroll away or be rebuilt during the request: everything
    // after it goes through the app-wide container, not this widget's ref.
    final container = ProviderScope.containerOf(context, listen: false);
    final api = container.read(mushukistanApiProvider);
    try {
      switch (item) {
        case LostPetData():
          await api.deleteLostPet(item.id);
          container.read(deletedLostPetIdsProvider.notifier).state = {
            ...container.read(deletedLostPetIdsProvider),
            item.id,
          };
        case AdoptionPostData():
          await api.deleteAdoptionPost(item.id);
          container.read(deletedAdoptionIdsProvider.notifier).state = {
            ...container.read(deletedAdoptionIdsProvider),
            item.id,
          };
        case PostSummary():
          if (asModerator) {
            await api.deleteModerationPost(item.id);
          } else {
            await api.deleteObservation(item.id);
          }
          container.invalidate(userPostsProvider);
          // Also drop it from the Saved posts list if it is open.
          container.read(savedPostOverridesProvider.notifier).state = {
            ...container.read(savedPostOverridesProvider),
            item.id: false,
          };
        default:
          return;
      }
      container.read(postMutationRevisionProvider.notifier).state++;
      container.invalidate(feedPostsProvider);
      container.invalidate(profileMeProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.postDeleted)));
    } on MushukistanApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.couldNotSaveChanges)),
      );
    }
  }
}
