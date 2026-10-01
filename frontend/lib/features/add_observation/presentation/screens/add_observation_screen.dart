import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
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
          unawaited(
            _openObservationPhotoSource(context, ref, kind: 'observation'),
          );
        }
      });
    }
  }

  Future<void> _chooseGalleryPhoto(
    BuildContext context,
    WidgetRef ref,
    String kind,
  ) async {
    if (_preparingPhotos) {
      return;
    }
    final strings = ref.read(appStringsProvider);
    final controller = ref.read(addObservationControllerProvider.notifier);
    late final List<XFile> images;
    try {
      images = await ImagePicker().pickMultiImage(
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
        limit: 5,
      );
    } catch (error) {
      logPhotoPipelineFailure('observation_gallery_picker', error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(selectedImageErrorMessage(strings, error))),
        );
      }
      return;
    }
    if (images.isEmpty) {
      return;
    }
    if (!context.mounted) {
      releasePickedXFiles(images);
      return;
    }
    await _preparePickedImages(
      context,
      controller,
      images.take(5).toList(growable: false),
      strings,
      kind,
    );
  }

  Future<void> _preparePickedImages(
    BuildContext context,
    AddObservationController controller,
    List<XFile> images,
    AppStrings strings,
    String kind,
  ) async {
    setState(() {
      _preparingPhotos = true;
    });
    try {
      final preparedPhotos = await preparePickedXFilesForUpload(images);
      final photos = preparedPhotos
          .map(
            (prepared) => ObservationPhotoUpload(
              bytes: prepared.bytes,
              filename: prepared.filename,
              contentType: prepared.contentType,
            ),
          )
          .toList(growable: false);
      controller.reset(kind: kind);
      controller.setPhotos(photos);
      if (context.mounted) {
        context.go('/add/location');
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(selectedImageErrorMessage(strings, error))),
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
    String kind,
  ) async {
    if (_preparingPhotos) {
      return;
    }
    final strings = ref.read(appStringsProvider);
    late final XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
      );
    } catch (error) {
      logPhotoPipelineFailure('observation_camera_picker', error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(selectedImageErrorMessage(strings, error))),
        );
      }
      return;
    }
    if (image == null) {
      return;
    }
    if (!context.mounted) {
      releasePickedXFiles([image]);
      return;
    }
    final controller = ref.read(addObservationControllerProvider.notifier);
    await _preparePickedImages(
      context,
      controller,
      [image],
      strings,
      kind,
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: AppContentWidth(
        maxWidth: AppWidths.wide,
        child: ListView(
          padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < AppWidths.compact
                  ? AppSpacing.lg
                  : AppSpacing.xl),
          children: [
            Text(strings.createInMushukistan,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.chooseShareType,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(builder: (context, constraints) {
              final colors = Theme.of(context).colorScheme;
              final cards = [
                _CreateActionCard(
                  icon: Icons.add_a_photo_outlined,
                  title: strings.catObservation,
                  description: strings.catObservationAddSubtitle,
                  accent: colors.primary,
                  enabled: !_preparingPhotos,
                  onTap: () => unawaited(_openObservationPhotoSource(
                    context,
                    ref,
                    kind: 'observation',
                  )),
                ),
                _CreateActionCard(
                  icon: Icons.volunteer_activism_outlined,
                  title: strings.needsHelp,
                  description: strings.needsHelpCreateSubtitle,
                  accent: colors.secondary,
                  enabled: !_preparingPhotos,
                  onTap: () => unawaited(_openObservationPhotoSource(
                    context,
                    ref,
                    kind: 'needs_help',
                  )),
                ),
                _CreateActionCard(
                  icon: Icons.search_outlined,
                  title: strings.lostPet,
                  description: strings.lostPetAlertSubtitle,
                  accent: colors.error,
                  onTap: () => unawaited(_openContactRequiredFlow(
                    path: '/add/lost-pet',
                    requirementMessage: strings.phoneNumberRequiredForLostPet,
                  )),
                ),
                _CreateActionCard(
                  icon: Icons.home_outlined,
                  title: strings.findANewHome,
                  description: strings.findANewHomeSubtitle,
                  accent: AppPalette.adoption,
                  onTap: () => unawaited(_openContactRequiredFlow(
                    path: '/add/adoption',
                    requirementMessage: strings.phoneNumberRequiredForAdoption,
                  )),
                ),
              ];
              if (constraints.maxWidth < AppWidths.readable - AppSpacing.xl) {
                return Column(children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: AppSpacing.md),
                  ],
                ]);
              }
              return Column(children: [
                for (var row = 0; row < 2; row++) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[row * 2]),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: cards[row * 2 + 1]),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ]);
            }),
            if (_preparingPhotos) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.sm),
              Text(
                strings.preparingPhotoForUpload,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (state.hasDraft) ...[
              const SizedBox(height: AppSpacing.xl),
              Text(strings.continueDraft,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: LayoutBuilder(builder: (context, constraints) {
                  final content = Row(children: [
                    const Icon(Icons.edit_note_outlined),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(strings.draftStatus)),
                  ]);
                  final action = FilledButton.tonal(
                    onPressed: state.hasPhoto
                        ? () => context.go('/add/location')
                        : null,
                    child: Text(strings.continueAction),
                  );
                  if (constraints.maxWidth < AppWidths.compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        content,
                        const SizedBox(height: AppSpacing.md),
                        action,
                      ],
                    );
                  }
                  return Row(children: [Expanded(child: content), action]);
                }),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final shouldDelete =
                        await _confirmDeleteDraft(context, strings);
                    if (!shouldDelete) return;
                    ref.read(addObservationControllerProvider.notifier).reset();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.draftDeleted)),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(strings.deleteDraft),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openObservationPhotoSource(
    BuildContext context,
    WidgetRef ref, {
    required String kind,
  }) async {
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
        await _chooseGalleryPhoto(context, ref, kind);
        break;
      case _ObservationPhotoSource.camera:
        await _takePhoto(context, ref, kind);
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

class _CreateActionCard extends StatelessWidget {
  const _CreateActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 138),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(icon, color: accent, size: 24),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.xs),
              Text(description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

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
