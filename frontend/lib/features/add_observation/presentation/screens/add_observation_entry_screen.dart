import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../application/add_observation_controller.dart';

class AddObservationEntryScreen extends ConsumerWidget {
  const AddObservationEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(addObservationControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Cat observation')),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'Start with a photo',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Gallery posts are community updates. Camera posts can also place a cat on the map.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _AddOptionCard(
              icon: Icons.photo_library_outlined,
              title: 'Choose from gallery',
              subtitle:
                  'Publishes to the feed only. No map location is attached.',
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  type: FileType.image,
                  withData: true,
                  allowMultiple: true,
                );
                final files = result?.files
                        .where((file) => file.bytes != null)
                        .take(5)
                        .toList(growable: false) ??
                    const [];
                if (files.isEmpty) {
                  return;
                }
                final photos = <ObservationPhotoUpload>[];
                for (final file in files) {
                  final prepared = await prepareImageForUpload(
                    bytes: file.bytes!,
                    filename: file.name,
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
                  context.go('/add/details');
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _AddOptionCard(
              icon: Icons.photo_camera_outlined,
              title: 'Take photo',
              subtitle:
                  'Captures current location and can place the cat on the map.',
              onPressed: () async {
                final acceptedLocationUse =
                    await _confirmObservationLocationUse(context);
                if (!acceptedLocationUse) {
                  return;
                }
                final image = await ImagePicker().pickImage(
                  source: ImageSource.camera,
                  imageQuality: 90,
                );
                if (image == null) {
                  return;
                }
                final prepared = await prepareImageForUpload(
                  bytes: await image.readAsBytes(),
                  filename: image.name,
                );
                controller.reset();
                controller.setPhoto(
                  bytes: prepared.bytes,
                  filename: prepared.filename,
                  contentType: prepared.contentType,
                );
                final location =
                    await LocationService().resolveCurrentLocation();
                controller.setLocation(location);
                unawaited(controller.loadNearbyCats());
                if (context.mounted) {
                  context.go('/add/details');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmObservationLocationUse(BuildContext context) async {
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

class _AddOptionCard extends StatelessWidget {
  const _AddOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onPressed,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
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
