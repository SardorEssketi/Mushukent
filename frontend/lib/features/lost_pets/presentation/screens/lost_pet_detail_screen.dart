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
import '../../../comments/presentation/screens/comments_screen.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../feed/presentation/widgets/feed_card_parts.dart';
import '../../../posts/presentation/widgets/publication_detail_parts.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

final lostPetDetailProvider = FutureProvider.autoDispose
    .family<LostPetData, String>((ref, lostPetId) async {
  // Contact details are only sent to signed-in viewers: reload when the session changes.
  ref.watch(authControllerProvider.select((state) => state.isAuthenticated));
  try {
    return await ref.watch(mushukistanApiProvider).getLostPet(lostPetId);
  } on MushukistanApiException catch (error) {
    final override = ref.read(lostPetMutationOverridesProvider)[lostPetId];
    if (error.isRetryable && override != null) return override;
    rethrow;
  }
});

enum _LostPetDetailAction { report, edit, delete }

class LostPetDetailScreen extends ConsumerStatefulWidget {
  const LostPetDetailScreen(
      {super.key, required this.lostPetId, this.focusComments = false});

  final String lostPetId;
  final bool focusComments;

  @override
  ConsumerState<LostPetDetailScreen> createState() =>
      _LostPetDetailScreenState();
}

class _LostPetDetailScreenState extends ConsumerState<LostPetDetailScreen> {
  bool _contactInFlight = false;
  bool _statusInFlight = false;
  final GlobalKey _commentsKey = GlobalKey();

  Future<void> _setResolution(LostPetData pet, AppStrings strings) async {
    if (_statusInFlight) return;
    final resolving = !pet.isResolved;
    if (resolving) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.markLostPetFound),
          content: Text(strings.lostPetResolutionMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.markLostPetFound),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _statusInFlight = true);
    try {
      final updated =
          await ref.read(mushukistanApiProvider).setLostPetResolution(
                pet.id,
                isResolved: resolving,
              );
      ref.read(lostPetMutationOverridesProvider.notifier).state = {
        ...ref.read(lostPetMutationOverridesProvider),
        updated.id: updated,
      };
      final resolvedIds = {...ref.read(resolvedLostPetIdsProvider)};
      if (updated.isResolved) {
        resolvedIds.add(updated.id);
      } else {
        resolvedIds.remove(updated.id);
      }
      ref.read(resolvedLostPetIdsProvider.notifier).state = resolvedIds;
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(lostPetDetailProvider(pet.id));
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

  Future<void> _editLostPet(LostPetData lostPet) async {
    final result = await context.push<bool>('/lost-pets/${lostPet.id}/edit');
    if (mounted && result == true) {
      ref.invalidate(lostPetDetailProvider(widget.lostPetId));
    }
  }

  Future<void> _deleteLostPet(
    BuildContext context,
    AppStrings strings,
    LostPetData lostPet,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.deleteLostPet),
        content: Text(strings.deleteLostPetMessage),
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
    try {
      await ref.read(mushukistanApiProvider).deleteLostPet(lostPet.id);
      ref.read(deletedLostPetIdsProvider.notifier).state = {
        ...ref.read(deletedLostPetIdsProvider),
        lostPet.id,
      };
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
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

  Future<void> _contactOwner(
      BuildContext context, AppStrings strings, LostPetData lostPet,
      {bool telegram = false}) async {
    if (_contactInFlight) return;
    if (!ref.read(authControllerProvider).isAuthenticated) {
      requestAuthentication(context);
      return;
    }
    _contactInFlight = true;
    try {
      await ref.read(mushukistanApiProvider).contactLostPetOwner(lostPet.id);
      if (!context.mounted) return;
      if (telegram) {
        final handle = lostPet.ownerTelegramUsername;
        if (handle != null) await _openTelegram(handle);
      } else {
        // Signed in but the details have not arrived yet (session still loading): the contact
        // event is recorded, and the next tap uses the reloaded number.
        final phone = lostPet.ownerPhoneNumber;
        if (phone != null) {
          await launchPublicPhone(context, phone: phone, strings: strings);
        }
      }
    } on MushukistanApiException catch (error) {
      if (error.code == 'LOST_PET_NOT_ACTIVE') {
        ref.invalidate(lostPetDetailProvider(lostPet.id));
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

  Future<void> _openTelegram(String username) async {
    await launchUrl(
      Uri.parse('https://t.me/$username'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _openMap(BuildContext context, LostPetData pet) {
    final location = pet.lastSeenLocation!;
    context.go(
      '/map?lat=${location.latitude}&lon=${location.longitude}&lostPetId=${pet.id}',
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

  void _report(LostPetData pet) {
    context.push(
      Uri(
        path: '/report',
        queryParameters: {
          'type': 'lost_pet',
          'id': widget.lostPetId,
          'label': pet.petName,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lostPetId = widget.lostPetId;
    final lostPetAsync = ref.watch(lostPetDetailProvider(lostPetId));
    final strings = ref.watch(appStringsProvider);
    final viewerId = ref.watch(currentUserProvider)?.id;
    final loaded = lostPetAsync.valueOrNull;
    final loadedIsOwner = viewerId != null && loaded?.author?.id == viewerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.lostPet),
        actions: [
          if (loaded != null)
            PublicationActionsMenu<_LostPetDetailAction>(
              tooltip: strings.postActions,
              entries: [
                if (loadedIsOwner) ...[
                  PublicationMenuEntry(
                    value: _LostPetDetailAction.edit,
                    label: strings.editLostPet,
                    icon: Icons.edit_outlined,
                  ),
                  PublicationMenuEntry(
                    value: _LostPetDetailAction.delete,
                    label: strings.deleteLostPet,
                    icon: Icons.delete_outline,
                    destructive: true,
                  ),
                ] else
                  PublicationMenuEntry(
                    value: _LostPetDetailAction.report,
                    label: strings.report,
                    icon: Icons.flag_outlined,
                  ),
              ],
              onSelected: (action) => switch (action) {
                _LostPetDetailAction.report => _report(loaded),
                _LostPetDetailAction.edit => _editLostPet(loaded),
                _LostPetDetailAction.delete =>
                  _deleteLostPet(context, strings, loaded),
              },
            ),
        ],
      ),
      body: lostPetAsync.when(
        data: (lostPet) {
          final info = lostPet.additionalInfo?.trim();
          final isOwner = viewerId != null && lostPet.author?.id == viewerId;
          final canContact = !lostPet.isResolved &&
              lostPet.contactAvailable &&
              lostPet.author?.id != null &&
              lostPet.author?.id != viewerId;
          final authorId = lostPet.author?.id;
          final colors = Theme.of(context).colorScheme;
          return PublicationDetailLayout(
            commentsKey: _commentsKey,
            gallery: PublicationGallery(photoUrls: lostPet.photoUrls),
            details: [
              PublicationAuthorRow(
                author: lostPet.author,
                createdAt: lostPet.createdAt,
                strings: strings,
                onAuthorTap: authorId == null
                    ? null
                    : () => context.push('/users/$authorId'),
              ),
              const SizedBox(height: AppSpacing.md),
              PublicationTitle(
                title: lostPet.petName,
                badge: lostPet.isResolved
                    ? AppBadge(
                        label: strings.reunitedLostPet,
                        icon: Icons.check_circle_outline,
                        color: AppPalette.found,
                      )
                    : FeedKindBadge(
                        kind: FeedKind.lostPet,
                        label: strings.lostPet,
                      ),
              ),
              if (lostPet.isResolved) ...[
                const SizedBox(height: AppSpacing.md),
                PublicationCallout(
                  icon: Icons.favorite_outline,
                  color: AppPalette.found,
                  body: strings.foundPostPrivateDetails,
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
              if (!lostPet.isResolved && lostPet.lastSeenLocation != null) ...[
                const SizedBox(height: AppSpacing.sm),
                PublicationChip(
                  icon: Icons.location_on_outlined,
                  label: strings.lastSeen,
                  onTap: () => _openMap(context, lostPet),
                ),
              ],
              if (canContact) ...[
                const SizedBox(height: AppSpacing.md),
                PublicationContactButton(
                  icon: Icons.phone_outlined,
                  label: strings.contactOwner,
                  value: lostPet.ownerPhoneNumber,
                  onPressed: () => _contactOwner(context, strings, lostPet),
                ),
                if (lostPet.ownerTelegramUsername != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PublicationContactButton(
                    primary: false,
                    icon: Icons.alternate_email,
                    label: 'Telegram',
                    value: '@${lostPet.ownerTelegramUsername}',
                    onPressed: () => _contactOwner(
                      context,
                      strings,
                      lostPet,
                      telegram: true,
                    ),
                  ),
                ],
              ],
              if (isOwner) ...[
                const SizedBox(height: AppSpacing.md),
                lostPet.isResolved
                    ? OutlinedButton.icon(
                        onPressed: _statusInFlight
                            ? null
                            : () => _setResolution(lostPet, strings),
                        icon: const Icon(Icons.replay_outlined),
                        label: Text(strings.reopenLostPet),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: _statusInFlight
                            ? null
                            : () => _setResolution(lostPet, strings),
                        icon: Icon(
                          Icons.check_circle_outline,
                          color: colors.onSecondaryContainer,
                        ),
                        label: Text(strings.markLostPetFound),
                      ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PublicationEngagementBar(
                strings: strings,
                commentCount: lostPet.commentCount,
                onComments: _openComments,
              ),
            ],
            comments: CommentDeepLinkFocus(
              focus: widget.focusComments,
              child: LostPetCommentsSection(
                lostPetId: lostPetId,
                padding: EdgeInsets.zero,
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.lostPet,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () => ref.invalidate(lostPetDetailProvider(lostPetId)),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }
}
