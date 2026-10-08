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
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/marker_detail_actions.dart';
import '../../../comments/presentation/screens/comments_screen.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

final lostPetDetailProvider = FutureProvider.autoDispose
    .family<LostPetData, String>((ref, lostPetId) async {
  try {
    return await ref.watch(mushukistanApiProvider).getLostPet(lostPetId);
  } on MushukistanApiException catch (error) {
    final override = ref.read(lostPetMutationOverridesProvider)[lostPetId];
    if (error.isRetryable && override != null) return override;
    rethrow;
  }
});

enum _LostPetDetailAction { report }

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
        await _openTelegram(lostPet.ownerTelegramUsername!);
      } else {
        await launchPublicPhone(
          context,
          phone: lostPet.ownerPhoneNumber!,
          strings: strings,
        );
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

  @override
  Widget build(BuildContext context) {
    final lostPetId = widget.lostPetId;
    final lostPetAsync = ref.watch(lostPetDetailProvider(lostPetId));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.lostPet),
        actions: [
          if (lostPetAsync.valueOrNull != null)
            PopupMenuButton<_LostPetDetailAction>(
              tooltip: strings.postActions,
              onSelected: (_) {
                final pet = lostPetAsync.valueOrNull!;
                context.push(
                  Uri(
                    path: '/report',
                    queryParameters: {
                      'type': 'lost_pet',
                      'id': lostPetId,
                      'label': pet.petName,
                    },
                  ).toString(),
                );
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _LostPetDetailAction.report,
                  child: Text(strings.report),
                ),
              ],
            ),
        ],
      ),
      body: lostPetAsync.when(
        data: (lostPet) {
          final info = lostPet.additionalInfo?.trim();
          final viewerId = ref.watch(currentUserProvider)?.id;
          final isOwner = viewerId != null && lostPet.author?.id == viewerId;
          final canContact = !lostPet.isResolved &&
              lostPet.ownerPhoneNumber != null &&
              lostPet.author?.id != null &&
              lostPet.author?.id != viewerId;
          return AppContentWidth(
            maxWidth: AppWidths.readable,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _LostPetPhotoGallery(photoUrls: lostPet.photoUrls),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LostPetDetailBadge(
                    label: lostPet.isResolved
                        ? strings.reunitedLostPet
                        : strings.lostPet,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  lostPet.petName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (lostPet.isResolved) ...[
                  const SizedBox(height: 8),
                  Text(strings.foundPostPrivateDetails),
                ],
                const SizedBox(height: 16),
                if (!lostPet.isResolved &&
                    lostPet.lastSeenLocation != null) ...[
                  _DetailActionTile(
                    icon: Icons.location_on_outlined,
                    title: strings.lastSeen,
                    subtitle: strings.viewOnMap,
                    onTap: () => _openMap(context, lostPet),
                  ),
                ],
                if (canContact) ...[
                  const SizedBox(height: 10),
                  _DetailActionTile(
                    icon: Icons.phone_outlined,
                    title: strings.contactOwner,
                    subtitle: lostPet.ownerPhoneNumber!,
                    onTap: () => _contactOwner(context, strings, lostPet),
                  ),
                ],
                if (canContact && lostPet.ownerTelegramUsername != null) ...[
                  const SizedBox(height: 10),
                  _DetailActionTile(
                    icon: Icons.alternate_email,
                    title: 'Telegram',
                    subtitle: '@${lostPet.ownerTelegramUsername}',
                    onTap: () => _contactOwner(
                      context,
                      strings,
                      lostPet,
                      telegram: true,
                    ),
                  ),
                ],
                if (info != null && info.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    strings.additionalInformation,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(info),
                ],
                if (isOwner) ...[
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _statusInFlight
                            ? null
                            : () => _setResolution(lostPet, strings),
                        icon: Icon(lostPet.isResolved
                            ? Icons.replay_outlined
                            : Icons.check_circle_outline),
                        label: Text(lostPet.isResolved
                            ? strings.reopenLostPet
                            : strings.markLostPetFound),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _editLostPet(lostPet),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(strings.editLostPet),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            _deleteLostPet(context, strings, lostPet),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(strings.deleteLostPet),
                        style: FilledButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                const SizedBox(height: 24),
                CommentDeepLinkFocus(
                  focus: widget.focusComments,
                  child: LostPetCommentsSection(
                    lostPetId: lostPetId,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
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

class _LostPetPhotoGallery extends StatefulWidget {
  const _LostPetPhotoGallery({required this.photoUrls});

  final List<String> photoUrls;

  @override
  State<_LostPetPhotoGallery> createState() => _LostPetPhotoGalleryState();
}

class _LostPetPhotoGalleryState extends State<_LostPetPhotoGallery> {
  late final PageController _controller = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final next = (_currentIndex + delta).clamp(0, widget.photoUrls.length - 1);
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoCount = widget.photoUrls.length;
    final desktop = MediaQuery.sizeOf(context).width >= 700;
    return SizedBox(
      height: desktop ? 420 : 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: photoCount,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppRemoteImage(
                  widget.photoUrls[index],
                  fit: desktop ? BoxFit.contain : BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const _GalleryImageUnavailable(),
                ),
              );
            },
          ),
          if (photoCount > 1) ...[
            Positioned(
              top: 12,
              right: 12,
              child: _GalleryCounter(
                current: _currentIndex + 1,
                total: photoCount,
              ),
            ),
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: _GalleryArrow(
                icon: Icons.chevron_left,
                onPressed: _currentIndex == 0 ? null : () => _move(-1),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: _GalleryArrow(
                icon: Icons.chevron_right,
                onPressed:
                    _currentIndex == photoCount - 1 ? null : () => _move(1),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: _GalleryDots(
                count: photoCount,
                activeIndex: _currentIndex,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GalleryCounter extends StatelessWidget {
  const _GalleryCounter({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              '$current / $total',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
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

class _GalleryDots extends StatelessWidget {
  const _GalleryDots({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: index == activeIndex ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: index == activeIndex ? 0.95 : 0.58,
              ),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
      ],
    );
  }
}

class _GalleryImageUnavailable extends StatelessWidget {
  const _GalleryImageUnavailable();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 48,
      ),
    );
  }
}

class _LostPetDetailBadge extends StatelessWidget {
  const _LostPetDetailBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 16, color: colorScheme.onErrorContainer),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailActionTile extends StatelessWidget {
  const _DetailActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
