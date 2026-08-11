import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/validation/phone_numbers.dart';
import '../../../comments/presentation/screens/comments_screen.dart';

final adoptionPostDetailProvider = FutureProvider.autoDispose
    .family<AdoptionPostData, String>((ref, adoptionPostId) {
  return ref.watch(mushukistanApiProvider).getAdoptionPost(adoptionPostId);
});

class AdoptionPostDetailScreen extends ConsumerWidget {
  const AdoptionPostDetailScreen({super.key, required this.adoptionPostId});

  final String adoptionPostId;

  Future<void> _contactOwner(String phoneNumber) async {
    await launchUrl(Uri(scheme: 'tel', path: dialablePhoneNumber(phoneNumber)));
  }

  Future<void> _openTelegram(String username) async {
    await launchUrl(
      Uri.parse('https://t.me/$username'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adoptionAsync = ref.watch(adoptionPostDetailProvider(adoptionPostId));

    return Scaffold(
      appBar: AppBar(title: const Text('Adoption')),
      body: adoptionAsync.when(
        data: (post) {
          final info = post.additionalInfo?.trim();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _AdoptionPhotoGallery(photoUrls: post.photoUrls),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: _AdoptionBadge(label: 'Adoption'),
              ),
              const SizedBox(height: 12),
              Text(
                post.petName,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _DetailActionTile(
                icon: Icons.phone_outlined,
                title: 'Owner phone',
                subtitle: post.ownerPhoneNumber,
                onTap: () => _contactOwner(post.ownerPhoneNumber),
              ),
              if (post.ownerTelegramUsername != null) ...[
                const SizedBox(height: 10),
                _DetailActionTile(
                  icon: Icons.alternate_email,
                  title: 'Telegram',
                  subtitle: '@${post.ownerTelegramUsername}',
                  onTap: () => _openTelegram(post.ownerTelegramUsername!),
                ),
              ],
              if (info != null && info.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Additional information',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(info),
              ],
              const SizedBox(height: 24),
              AdoptionPostCommentsSection(
                adoptionPostId: adoptionPostId,
                padding: EdgeInsets.zero,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(error.toString())),
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
                child: Image.network(
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
        borderRadius: BorderRadius.circular(999),
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
        borderRadius: BorderRadius.circular(999),
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
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
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
