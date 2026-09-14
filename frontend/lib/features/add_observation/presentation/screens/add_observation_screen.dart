import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/language_controller.dart';
import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/validation/phone_numbers.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';

class AddObservationScreen extends ConsumerStatefulWidget {
  const AddObservationScreen({super.key, this.observationOnly = false});

  final bool observationOnly;

  @override
  ConsumerState<AddObservationScreen> createState() =>
      _AddObservationScreenState();
}

class _AddObservationScreenState extends ConsumerState<AddObservationScreen> {
  bool _preparingPhotos = false;

  @override
  void initState() {
    super.initState();
    if (widget.observationOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openObservationPhotoSource(context, ref));
        }
      });
    }
  }

  Future<void> _chooseGalleryPhoto(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (_preparingPhotos) {
      return;
    }
    final strings = ref.read(appStringsProvider);
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
      strings,
    );
  }

  Future<void> _preparePickedImages(
    BuildContext context,
    AddObservationController controller,
    List<XFile> images,
    AppStrings strings,
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
        SnackBar(content: Text(strings.couldNotPreparePhoto(error))),
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
    final strings = ref.read(appStringsProvider);
    await _preparePickedImages(
      context,
      controller,
      [image],
      strings,
    );
  }

  Future<void> _openContactRequiredFlow({
    required String path,
    required String requirementMessage,
  }) async {
    final strings = ref.read(appStringsProvider);
    try {
      final profile = await ref.read(mushukistanApiProvider).getMe();
      final phone = profile.phoneNumber?.trim() ?? '';
      if (!mounted) {
        return;
      }
      if (phone.isNotEmpty && isValidUzbekPhoneNumber(phone)) {
        context.go(path);
        return;
      }
      final editProfile = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.phoneNumberRequired),
          content: Text(requirementMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.editProfile),
            ),
          ],
        ),
      );
      if (editProfile == true && mounted) {
        context.go('/profile/edit');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotLoadProfile)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addObservationControllerProvider);
    final strings = ref.watch(appStringsProvider);

    if (widget.observationOnly) {
      return Scaffold(
        body: Center(
          child: _preparingPhotos
              ? const CircularProgressIndicator()
              : const SizedBox.shrink(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.create)),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              strings.whatAreYouCreating,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.chooseTypeFirst,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _AddCategoryCard(
              icon: Icons.add_a_photo_outlined,
              title: strings.catObservation,
              subtitle: strings.catObservationSubtitle,
              color: Theme.of(context).colorScheme.primary,
              onTap: _preparingPhotos
                  ? null
                  : () => unawaited(_openObservationPhotoSource(context, ref)),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddCategoryCard(
              icon: Icons.search_outlined,
              title: strings.lostPetAlert,
              subtitle: strings.lostPetAlertSubtitle,
              color: Theme.of(context).colorScheme.error,
              onTap: () => unawaited(
                _openContactRequiredFlow(
                  path: '/add/lost-pet',
                  requirementMessage: strings.phoneNumberRequiredForLostPet,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _AddCategoryCard(
              icon: Icons.home_outlined,
              title: strings.findANewHome,
              subtitle: strings.findANewHomeSubtitle,
              color: AppPalette.adoption,
              onTap: () => unawaited(
                _openContactRequiredFlow(
                  path: '/add/adoption',
                  requirementMessage: strings.phoneNumberRequiredForAdoption,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_preparingPhotos) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                strings.preparingPhotoForUpload,
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
              label: Text(strings.continueDraft),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: state.hasDraft
                  ? () async {
                      final shouldDelete =
                          await _confirmDeleteDraft(context, strings);
                      if (!shouldDelete) {
                        return;
                      }
                      ref
                          .read(addObservationControllerProvider.notifier)
                          .reset();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.draftDeleted)),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.delete_outline),
              label: Text(strings.deleteDraft),
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
    final strings = ref.read(appStringsProvider);
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
                  strings.addCatPhotos,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(strings.chooseFromGallery),
                  subtitle: Text(strings.selectUpToFivePhotos),
                  onTap: () => Navigator.of(context)
                      .pop(_ObservationPhotoSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(strings.takeAPhoto),
                  subtitle: Text(strings.useCameraThenChooseLocation),
                  onTap: () =>
                      Navigator.of(context).pop(_ObservationPhotoSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted) {
      return;
    }
    if (source == null) {
      if (widget.observationOnly) {
        context.go('/feed');
      }
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
    if (widget.observationOnly &&
        context.mounted &&
        !ref.read(addObservationControllerProvider).hasPhoto &&
        !_preparingPhotos) {
      context.go('/feed');
    }
  }
}

enum _ObservationPhotoSource { gallery, camera }

Future<bool> _confirmDeleteDraft(
    BuildContext context, AppStrings strings) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.deleteDraftTitle),
      content: Text(strings.deleteDraftMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.delete),
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
    final strings = AppStrings.forLanguage(AppLanguage.fromCode(
      Localizations.localeOf(context).languageCode,
    ));
    return AppCard(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.draftStatus,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _SummaryRow(
              label: strings.photo,
              value: state.hasPhoto ? strings.selected : strings.missing),
          _SummaryRow(
            label: strings.location,
            value: state.hasLocation ? strings.set : strings.missing,
          ),
          _SummaryRow(
            label: strings.visibility,
            value: state.isPublic ? strings.public : strings.private,
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
