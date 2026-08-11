import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/validation/phone_numbers.dart';
import '../../../comments/presentation/screens/comments_screen.dart';

final lostPetDetailProvider =
    FutureProvider.autoDispose.family<LostPetData, String>((ref, lostPetId) {
  return ref.watch(mushukistanApiProvider).getLostPet(lostPetId);
});

class LostPetDetailScreen extends ConsumerWidget {
  const LostPetDetailScreen({super.key, required this.lostPetId});

  final String lostPetId;

  Future<void> _contactOwner(String phoneNumber) async {
    await launchUrl(Uri(scheme: 'tel', path: dialablePhoneNumber(phoneNumber)));
  }

  Future<void> _openTelegram(String username) async {
    await launchUrl(
      Uri.parse('https://t.me/$username'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _openMap(BuildContext context, GeoPoint location) {
    context.go('/map?lat=${location.latitude}&lon=${location.longitude}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lostPetAsync = ref.watch(lostPetDetailProvider(lostPetId));
    final strings = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.lostPet)),
      body: lostPetAsync.when(
        data: (lostPet) {
          final info = lostPet.additionalInfo?.trim();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _LostPetPhotoGallery(photoUrls: lostPet.photoUrls),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: _LostPetDetailBadge(label: strings.lostPet),
              ),
              const SizedBox(height: 12),
              Text(
                lostPet.petName,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _DetailActionTile(
                icon: Icons.location_on_outlined,
                title: strings.lastSeen,
                subtitle: strings.viewOnMap,
                onTap: () => _openMap(context, lostPet.lastSeenLocation),
              ),
              const SizedBox(height: 10),
              _DetailActionTile(
                icon: Icons.phone_outlined,
                title: strings.ownerPhone,
                subtitle: lostPet.ownerPhoneNumber,
                onTap: () => _contactOwner(lostPet.ownerPhoneNumber),
              ),
              if (lostPet.ownerTelegramUsername != null) ...[
                const SizedBox(height: 10),
                _DetailActionTile(
                  icon: Icons.alternate_email,
                  title: 'Telegram',
                  subtitle: '@${lostPet.ownerTelegramUsername}',
                  onTap: () => _openTelegram(lostPet.ownerTelegramUsername!),
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
              const SizedBox(height: 24),
              LostPetCommentsSection(
                lostPetId: lostPetId,
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
        borderRadius: BorderRadius.circular(999),
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
              borderRadius: BorderRadius.circular(999),
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
        borderRadius: BorderRadius.circular(999),
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
