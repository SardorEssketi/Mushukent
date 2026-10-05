import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/add_observation_controller.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../leaderboards/presentation/screens/leaderboard_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

class AddObservationDetailsScreen extends ConsumerStatefulWidget {
  const AddObservationDetailsScreen({super.key});

  @override
  ConsumerState<AddObservationDetailsScreen> createState() =>
      _AddObservationDetailsScreenState();
}

class _AddObservationDetailsScreenState
    extends ConsumerState<AddObservationDetailsScreen> {
  bool _picking = false;
  bool _locating = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    if (_picking || ref.read(addObservationControllerProvider).submitting) {
      return;
    }
    final current = ref.read(addObservationControllerProvider).photos;
    if (current.length >= 5) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final files = source == ImageSource.gallery
          ? await picker.pickMultiImage(
              imageQuality: pickerImageQuality,
              maxWidth: pickerMaxWidth,
              maxHeight: pickerMaxHeight,
              limit: 5 - current.length,
            )
          : <XFile>[
              if (await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: pickerImageQuality,
                maxWidth: pickerMaxWidth,
                maxHeight: pickerMaxHeight,
              )
                  case final XFile file)
                file,
            ];
      if (files.isEmpty) return;
      final prepared = await preparePickedXFilesForUpload(
        files,
        limit: 5 - current.length,
      );
      if (!mounted) return;
      ref.read(addObservationControllerProvider.notifier).setPhotos([
        ...current,
        for (final photo in prepared)
          ObservationPhotoUpload(
            bytes: photo.bytes,
            filename: photo.filename,
            contentType: photo.contentType,
          ),
      ]);
    } catch (error) {
      logPhotoPipelineFailure('cat_post_picker', error);
      if (mounted) {
        setState(() => _error =
            selectedImageErrorMessage(ref.read(appStringsProvider), error));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    final strings = ref.read(appStringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.useCurrentLocationTitle),
        content: Text(strings.useCurrentLocationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.continueAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final location =
          await ref.read(locationServiceProvider).resolveCurrentLocation();
      if (!mounted) return;
      if (location == null) {
        setState(() => _error = strings.couldNotResolveYourLocation);
      } else {
        ref
            .read(addObservationControllerProvider.notifier)
            .setLocation(location);
      }
    } catch (_) {
      if (mounted) setState(() => _error = strings.couldNotResolveYourLocation);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addObservationControllerProvider);
    final controller = ref.read(addObservationControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);
    final needsHelp = state.kind == 'needs_help';

    return Scaffold(
      appBar: AppBar(
          title: Text(needsHelp ? strings.needsHelp : strings.catObservation)),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: AppBadge(
                  label: needsHelp ? strings.needsHelp : strings.catObservation,
                  icon: needsHelp
                      ? Icons.volunteer_activism_outlined
                      : Icons.photo_outlined,
                  color: needsHelp
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.primary,
                )),
            const SizedBox(height: AppSpacing.md),
            Text(
              needsHelp ? strings.helpThisCat : strings.shareCatPost,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(needsHelp
                ? strings.helpThisCatSubtitle
                : strings.shareCatPostSubtitle),
            const SizedBox(height: AppSpacing.xl),
            Text(strings.photos,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var index = 0; index < state.photos.length; index++)
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(state.photos[index].bytes,
                        width: 92, height: 92, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton.filledTonal(
                      tooltip: strings.removePhoto,
                      onPressed: _picking || state.submitting
                          ? null
                          : () {
                              final photos = [...state.photos]..removeAt(index);
                              controller.setPhotos(photos);
                            },
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ]),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed:
                    _picking || state.submitting || state.photos.length >= 5
                        ? null
                        : () => unawaited(_pick(ImageSource.gallery)),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(strings.chooseFromGallery),
              ),
              OutlinedButton.icon(
                onPressed:
                    _picking || state.submitting || state.photos.length >= 5
                        ? null
                        : () => unawaited(_pick(ImageSource.camera)),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(strings.takeAPhoto),
              ),
            ]),
            if (_picking) ...[
              const SizedBox(height: AppSpacing.sm),
              const LinearProgressIndicator(),
              Text(strings.preparingPhotoForUpload),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              initialValue: state.catName,
              decoration: InputDecoration(
                labelText: strings.catNameOptionalLabel,
              ),
              maxLength: 100,
              textCapitalization: TextCapitalization.words,
              onChanged: controller.setCatName,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(strings.location,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (state.location == null)
              Text(needsHelp
                  ? strings.needsHelpLocationHelp
                  : strings.catPostLocationHelp)
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(strings.locationSelected),
                subtitle:
                    Text('${state.location!.latitude.toStringAsFixed(5)}, '
                        '${state.location!.longitude.toStringAsFixed(5)}'),
                trailing: needsHelp
                    ? null
                    : IconButton(
                        tooltip: strings.removeLocation,
                        onPressed:
                            state.submitting ? null : controller.clearLocation,
                        icon: const Icon(Icons.close),
                      ),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed:
                    _locating || state.submitting ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_outlined),
                label: Text(strings.updateLocationFromDevice),
              ),
              OutlinedButton.icon(
                onPressed: state.submitting
                    ? null
                    : () => context.push('/add/location'),
                icon: const Icon(Icons.map_outlined),
                label: Text(strings.chooseOnMap),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              initialValue: state.description,
              decoration: InputDecoration(
                labelText: needsHelp
                    ? strings.helpDetailsLabel
                    : strings.addNoteOptional,
              ),
              maxLength: 2000,
              maxLines: 4,
              onChanged: controller.setDescription,
            ),
            if (_error != null || state.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _error ?? state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: state.submitting || _picking
                  ? null
                  : () async {
                      if (!state.hasPhoto) {
                        setState(() => _error = strings.addAtLeastOnePhoto);
                        return;
                      }
                      if (needsHelp && !state.hasLocation) {
                        setState(
                            () => _error = strings.needsHelpLocationRequired);
                        return;
                      }
                      if (needsHelp && state.description.trim().isEmpty) {
                        setState(() => _error = strings.helpDetailsRequired);
                        return;
                      }
                      setState(() => _error = null);
                      try {
                        await controller.submit(
                          strings: strings,
                        );
                        ref.invalidate(feedPostsProvider);
                        ref.read(postMutationRevisionProvider.notifier).state++;
                        ref.invalidate(profileMeProvider);
                        ref.invalidate(leaderboardProvider);
                        controller.reset();
                        if (context.mounted) {
                          final messenger = ScaffoldMessenger.of(context);
                          context.go('/feed');
                          messenger
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                              content: Text(needsHelp
                                  ? strings.helpRequestPublished
                                  : strings.postPublished),
                            ));
                        }
                      } catch (_) {
                        // Error is surfaced by controller state.
                      }
                    },
              child: state.submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      needsHelp
                          ? strings.publishNeedsHelp
                          : strings.publishObservation,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
