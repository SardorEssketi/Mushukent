import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/routing/auth_navigation.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/marker_detail_actions.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../comments/presentation/screens/comments_screen.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../feed/presentation/widgets/feed_card_parts.dart';
import '../../../posts/presentation/widgets/publication_detail_parts.dart';

final adoptionPostDetailProvider = FutureProvider.autoDispose
    .family<AdoptionPostData, String>((ref, adoptionPostId) async {
  try {
    return await ref
        .watch(mushukistanApiProvider)
        .getAdoptionPost(adoptionPostId);
  } on MushukistanApiException catch (error) {
    final override =
        ref.read(adoptionMutationOverridesProvider)[adoptionPostId];
    if (error.isRetryable && override != null) return override;
    rethrow;
  }
});

class AdoptionPostDetailScreen extends ConsumerStatefulWidget {
  const AdoptionPostDetailScreen(
      {super.key, required this.adoptionPostId, this.focusComments = false});

  final String adoptionPostId;
  final bool focusComments;

  @override
  ConsumerState<AdoptionPostDetailScreen> createState() =>
      _AdoptionPostDetailScreenState();
}

class _AdoptionPostDetailScreenState
    extends ConsumerState<AdoptionPostDetailScreen> {
  bool _contactInFlight = false;
  bool _statusInFlight = false;
  final GlobalKey _commentsKey = GlobalKey();

  Future<void> _setResolution(AdoptionPostData post, AppStrings strings) async {
    if (_statusInFlight) return;
    final resolving = !post.isResolved;
    if (resolving) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.markRehomed),
          content: Text(strings.adoptionResolutionMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.markRehomed),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _statusInFlight = true);
    try {
      final updated =
          await ref.read(mushukistanApiProvider).setAdoptionResolution(
                post.id,
                isResolved: resolving,
              );
      ref.read(adoptionMutationOverridesProvider.notifier).state = {
        ...ref.read(adoptionMutationOverridesProvider),
        updated.id: updated,
      };
      final resolvedIds = {...ref.read(resolvedAdoptionIdsProvider)};
      if (updated.isResolved) {
        resolvedIds.add(updated.id);
      } else {
        resolvedIds.remove(updated.id);
      }
      ref.read(resolvedAdoptionIdsProvider.notifier).state = resolvedIds;
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(adoptionPostDetailProvider(post.id));
      ref.invalidate(feedPostsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.changesSaved)),
        );
      }
    } on MushukistanApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSaveChanges)),
        );
      }
    } finally {
      if (mounted) setState(() => _statusInFlight = false);
    }
  }

  Future<void> _contactOwner(
      BuildContext context, AppStrings strings, AdoptionPostData post,
      {bool telegram = false}) async {
    if (_contactInFlight) return;
    if (!ref.read(authControllerProvider).isAuthenticated) {
      requestAuthentication(context);
      return;
    }
    _contactInFlight = true;
    try {
      await ref.read(mushukistanApiProvider).contactAdoptionOwner(post.id);
      if (!context.mounted) return;
      if (telegram) {
        await _openTelegram(post.ownerTelegramUsername!);
      } else {
        await launchPublicPhone(context,
            phone: post.ownerPhoneNumber!, strings: strings);
      }
    } on MushukistanApiException catch (error) {
      if (error.code == 'ADOPTION_POST_NOT_ACTIVE') {
        ref.invalidate(adoptionPostDetailProvider(post.id));
        ref.read(postMutationRevisionProvider.notifier).state++;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSaveChanges)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSaveChanges)),
        );
      }
    } finally {
      _contactInFlight = false;
    }
  }

  Future<void> _editPost(AdoptionPostData post) async {
    final result = await context.push<bool>('/adoption-posts/${post.id}/edit');
    if (mounted && result == true) {
      ref.invalidate(adoptionPostDetailProvider(widget.adoptionPostId));
    }
  }

  Future<void> _deletePost(
      BuildContext context, AppStrings strings, AdoptionPostData post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteAdoptionPost),
        content: Text(strings.deleteAdoptionPostMessage),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.delete)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(mushukistanApiProvider).deleteAdoptionPost(post.id);
      ref.read(deletedAdoptionIdsProvider.notifier).state = {
        ...ref.read(deletedAdoptionIdsProvider),
        post.id,
      };
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(feedPostsProvider);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.pop(true);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(strings.postDeleted)));
      }
    } on MushukistanApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSaveChanges)),
        );
      }
    }
  }

  Future<void> _openTelegram(String username) async {
    await launchUrl(
      Uri.parse('https://t.me/$username'),
      mode: LaunchMode.externalApplication,
    );
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

  void _report(AdoptionPostData post) {
    context.push(
      Uri(
        path: '/report',
        queryParameters: {
          'type': 'adoption_post',
          'id': widget.adoptionPostId,
          'label': post.petName,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adoptionPostId = widget.adoptionPostId;
    final adoptionAsync = ref.watch(adoptionPostDetailProvider(adoptionPostId));
    final strings = ref.watch(appStringsProvider);
    final viewerId = ref.watch(currentUserProvider)?.id;
    final loaded = adoptionAsync.valueOrNull;
    final loadedIsOwner = viewerId != null && loaded?.author?.id == viewerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.adoption),
        actions: [
          if (loaded != null)
            PublicationActionsMenu<_AdoptionDetailAction>(
              tooltip: strings.postActions,
              entries: [
                if (loadedIsOwner) ...[
                  PublicationMenuEntry(
                    value: _AdoptionDetailAction.edit,
                    label: strings.editAdoptionPost,
                    icon: Icons.edit_outlined,
                  ),
                  PublicationMenuEntry(
                    value: _AdoptionDetailAction.delete,
                    label: strings.deleteAdoptionPost,
                    icon: Icons.delete_outline,
                    destructive: true,
                  ),
                ] else
                  PublicationMenuEntry(
                    value: _AdoptionDetailAction.report,
                    label: strings.report,
                    icon: Icons.flag_outlined,
                  ),
              ],
              onSelected: (action) => switch (action) {
                _AdoptionDetailAction.report => _report(loaded),
                _AdoptionDetailAction.edit => _editPost(loaded),
                _AdoptionDetailAction.delete =>
                  _deletePost(context, strings, loaded),
              },
            ),
        ],
      ),
      body: adoptionAsync.when(
        data: (post) {
          final info = post.additionalInfo?.trim();
          final isOwner = viewerId != null && post.author?.id == viewerId;
          final canContact = !post.isResolved &&
              post.ownerPhoneNumber != null &&
              post.author?.id != null &&
              post.author?.id != viewerId;
          final authorId = post.author?.id;
          final rows = [
            if (canContact)
              PublicationInfoRow(
                icon: Icons.phone_outlined,
                title: strings.contactOwner,
                subtitle: post.ownerPhoneNumber!,
                onTap: () => _contactOwner(context, strings, post),
              ),
            if (canContact && post.ownerTelegramUsername != null)
              PublicationInfoRow(
                icon: Icons.alternate_email,
                title: 'Telegram',
                subtitle: '@${post.ownerTelegramUsername}',
                onTap: () =>
                    _contactOwner(context, strings, post, telegram: true),
              ),
          ];
          return PublicationDetailLayout(
            commentsKey: _commentsKey,
            gallery: PublicationGallery(photoUrls: post.photoUrls),
            details: [
              PublicationAuthorRow(
                author: post.author,
                createdAt: post.createdAt,
                strings: strings,
                onAuthorTap: authorId == null
                    ? null
                    : () => context.push('/users/$authorId'),
              ),
              const SizedBox(height: AppSpacing.md),
              PublicationTitle(
                title: post.petName,
                badge: post.isResolved
                    ? AppBadge(
                        label: strings.rehomedAdoptionPost,
                        icon: Icons.check_circle_outline,
                        color: AppPalette.found,
                      )
                    : FeedKindBadge(
                        kind: FeedKind.rehoming,
                        label: strings.adoption,
                      ),
              ),
              if (post.isResolved) ...[
                const SizedBox(height: AppSpacing.md),
                PublicationCallout(
                  icon: Icons.home_outlined,
                  color: AppPalette.found,
                  body: strings.rehomedPostPrivateDetails,
                ),
              ],
              if (info != null && info.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  strings.additionalInformation,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  info,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.45),
                ),
              ],
              if (rows.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                PublicationInfoGroup(rows: rows),
              ],
              if (isOwner) ...[
                const SizedBox(height: AppSpacing.md),
                post.isResolved
                    ? OutlinedButton.icon(
                        onPressed: _statusInFlight
                            ? null
                            : () => _setResolution(post, strings),
                        icon: const Icon(Icons.replay_outlined),
                        label: Text(strings.reopenRehoming),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: _statusInFlight
                            ? null
                            : () => _setResolution(post, strings),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(strings.markRehomed),
                      ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PublicationEngagementBar(
                strings: strings,
                commentCount: post.commentCount,
                onComments: _openComments,
              ),
            ],
            comments: CommentDeepLinkFocus(
              focus: widget.focusComments,
              child: AdoptionPostCommentsSection(
                adoptionPostId: adoptionPostId,
                padding: EdgeInsets.zero,
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.adoption,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () => ref.invalidate(
              adoptionPostDetailProvider(adoptionPostId),
            ),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }
}

enum _AdoptionDetailAction { report, edit, delete }
