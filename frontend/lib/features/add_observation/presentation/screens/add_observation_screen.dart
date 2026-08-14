import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';

class AddObservationScreen extends ConsumerStatefulWidget {
  const AddObservationScreen({super.key});

  @override
  ConsumerState<AddObservationScreen> createState() =>
      _AddObservationScreenState();
}

class _AddObservationScreenState extends ConsumerState<AddObservationScreen> {
  bool _preparingPhotos = false;

  Future<void> _chooseGalleryPhoto(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (_preparingPhotos) {
      return;
    }
    final controller = ref.read(addObservationControllerProvider.notifier);
    final images = await ImagePicker().pickMultiImage(
      imageQuality: 90,
      limit: 5,
    );
    if (images.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _preparePickedImages(
      context,
      controller,
      images.take(5).toList(growable: false),
    );
  }

  Future<void> _preparePickedImages(
    BuildContext context,
    AddObservationController controller,
    List<XFile> images,
  ) async {
    setState(() {
      _preparingPhotos = true;
    });
    try {
      final photos = <ObservationPhotoUpload>[];
      for (final image in images) {
        final prepared = await prepareImageForUpload(
          bytes: await image.readAsBytes(),
          filename: image.name,
        );
        photos.add(
          ObservationPhotoUpload(
            bytes: prepared.bytes,
            filename: prepared.filename,
            contentType: prepared.contentType,
          ),
        );
      }
      controller.reset();
      controller.setPhotos(photos);
      if (context.mounted) {
        context.go('/add/location');
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not prepare photo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _preparingPhotos = false;
        });
      }
    }
  }

  Future<void> _takePhoto(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (_preparingPhotos) {
      return;
    }
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final controller = ref.read(addObservationControllerProvider.notifier);
    await _preparePickedImages(
      context,
      controller,
      [image],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addObservationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create')),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'What are you creating?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Choose the right type first so Mushukistan can ask only for the details that matter.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _AddCategoryCard(
              icon: Icons.add_a_photo_outlined,
              title: 'Cat observation',
              subtitle:
                  'Add one to five cat photos, then choose whether to attach a location.',
              color: Theme.of(context).colorScheme.primary,
              onTap: _preparingPhotos
                  ? null
                  : () => unawaited(_openObservationPhotoSource(context, ref)),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddCategoryCard(
              icon: Icons.search_outlined,
              title: 'Lost pet alert',
              subtitle:
                  'Pet photos, last-seen map point, status, and owner contact.',
              color: Theme.of(context).colorScheme.error,
              onTap: () => context.go('/add/lost-pet'),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddCategoryCard(
              icon: Icons.home_outlined,
              title: 'Find a new home',
              subtitle:
                  'A separate rehoming post with photos, description, and owner contact. No map required.',
              color: AppPalette.adoption,
              onTap: () => context.go('/add/adoption'),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_preparingPhotos) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Preparing photo for upload...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _SummaryCard(state: state),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed:
                  state.hasPhoto ? () => context.go('/add/location') : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue draft'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openObservationPhotoSource(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final source = await showModalBottomSheet<_ObservationPhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add cat photos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  subtitle: const Text('Select up to five photos.'),
                  onTap: () => Navigator.of(context)
                      .pop(_ObservationPhotoSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  subtitle: const Text('Use the camera, then choose location.'),
                  onTap: () =>
                      Navigator.of(context).pop(_ObservationPhotoSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || source == null) {
      return;
    }
    switch (source) {
      case _ObservationPhotoSource.gallery:
        await _chooseGalleryPhoto(context, ref);
        break;
      case _ObservationPhotoSource.camera:
        await _takePhoto(context, ref);
        break;
    }
  }
}

enum _ObservationPhotoSource { gallery, camera }

Future<bool> confirmObservationLocationUse(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Use current location?'),
      content: const Text(
        'Mushukistan will read your current location and attach it to this observation. If you publish the post, that cat location can be visible to other users.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _AddCategoryCard extends StatelessWidget {
  const _AddCategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final AddObservationState state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Draft status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _SummaryRow(
              label: 'Photo', value: state.hasPhoto ? 'Selected' : 'Missing'),
          _SummaryRow(
            label: 'Location',
            value: state.hasLocation ? 'Set' : 'Missing',
          ),
          _SummaryRow(
            label: 'Cat choice',
            value: state.useNewCat ? 'New cat' : 'Existing cat',
          ),
          _SummaryRow(
            label: 'Visibility',
            value: state.isPublic ? 'Public' : 'Private',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
