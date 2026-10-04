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
import '../../../auth/application/auth_controller.dart';
import '../../../comments/presentation/screens/comments_screen.dart';
import '../../../feed/presentation/screens/feed_screen.dart';

final adoptionPostDetailProvider = FutureProvider.autoDispose
    .family<AdoptionPostData, String>((ref, adoptionPostId) {
  final override = ref.watch(adoptionMutationOverridesProvider)[adoptionPostId];
  if (override != null) return override;
  return ref.watch(mushukistanApiProvider).getAdoptionPost(adoptionPostId);
});

class AdoptionPostDetailScreen extends ConsumerStatefulWidget {
  const AdoptionPostDetailScreen({super.key, required this.adoptionPostId});

  final String adoptionPostId;

  @override
  ConsumerState<AdoptionPostDetailScreen> createState() =>
      _AdoptionPostDetailScreenState();
}

class _AdoptionPostDetailScreenState
    extends ConsumerState<AdoptionPostDetailScreen> {
  bool _contactInFlight = false;

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
            phone: post.ownerPhoneNumber, strings: strings);
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

  @override
  Widget build(BuildContext context) {
    final adoptionPostId = widget.adoptionPostId;
    final adoptionAsync = ref.watch(adoptionPostDetailProvider(adoptionPostId));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.adoption)),
      body: adoptionAsync.when(
        data: (post) {
          final info = post.additionalInfo?.trim();
          final viewerId = ref.watch(currentUserProvider)?.id;
          final isOwner = viewerId != null && post.author?.id == viewerId;
          final canContact = !post.isResolved &&
              post.author?.id != null &&
              post.author?.id != viewerId;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AdoptionPhotoGallery(photoUrls: post.photoUrls),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: _AdoptionBadge(
                    label: post.isResolved
                        ? strings.rehomedAdoptionPost
                        : strings.adoption),
              ),
              const SizedBox(height: 12),
              Text(
                post.petName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (canContact)
                _DetailActionTile(
                  icon: Icons.phone_outlined,
                  title: strings.contactOwner,
                  subtitle: post.ownerPhoneNumber,
                  onTap: () => _contactOwner(context, strings, post),
                ),
              if (canContact && post.ownerTelegramUsername != null) ...[
                const SizedBox(height: 10),
                _DetailActionTile(
                  icon: Icons.alternate_email,
                  title: 'Telegram',
                  subtitle: '@${post.ownerTelegramUsername}',
                  onTap: () =>
                      _contactOwner(context, strings, post, telegram: true),
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
                Wrap(spacing: 12, runSpacing: 12, children: [
                  OutlinedButton.icon(
                    onPressed: () => _editPost(post),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(strings.editAdoptionPost),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _deletePost(context, strings, post),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(strings.deleteAdoptionPost),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                    Uri(
                      path: '/report',
                      queryParameters: {
                        'type': 'adoption_post',
                        'id': adoptionPostId,
                        'label': post.petName,
                      },
                    ).toString(),
                  ),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(strings.report),
                ),
              ),
              const SizedBox(height: 24),
              AdoptionPostCommentsSection(
                adoptionPostId: adoptionPostId,
                padding: EdgeInsets.zero,
              ),
            ],
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

class _AdoptionPhotoGallery extends StatefulWidget {
  const _AdoptionPhotoGallery({required this.photoUrls});

  final List<String> photoUrls;

  @override
  State<_AdoptionPhotoGallery> createState() => _AdoptionPhotoGalleryState();
}

class _AdoptionPhotoGalleryState extends State<_AdoptionPhotoGallery> {
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
        child: Text(
          '$current / $total',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
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

class _AdoptionBadge extends StatelessWidget {
  const _AdoptionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined,
                size: 16, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
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
