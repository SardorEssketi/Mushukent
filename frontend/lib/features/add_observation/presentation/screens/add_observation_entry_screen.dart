import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
      appBar: AppBar(title: const Text('Add Observation')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Add observation',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how to add the cat photo.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 16),
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
              final location = await LocationService().resolveCurrentLocation();
              controller.setLocation(location);
              unawaited(controller.loadNearbyCats());
              if (context.mounted) {
                context.go('/add/details');
              }
            },
          ),
        ],
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
    return Card(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle),
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
