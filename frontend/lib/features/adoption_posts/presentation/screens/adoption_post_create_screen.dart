import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/storage/token_store.dart';
import '../../../../core/storage/token_store_provider.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/form_icon_buttons.dart';
import '../../../add_observation/application/pet_post_draft_controller.dart';
import '../../../add_observation/presentation/widgets/contact_share_notice.dart';
import '../../../feed/presentation/screens/feed_screen.dart';

class AdoptionPostCreateScreen extends ConsumerStatefulWidget {
  const AdoptionPostCreateScreen({super.key});

  @override
  ConsumerState<AdoptionPostCreateScreen> createState() =>
      _AdoptionPostCreateScreenState();
}

class _AdoptionPostCreateScreenState
    extends ConsumerState<AdoptionPostCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isPickingPhotos = false;
  String? _error;
  StreamSubscription<void>? _sessionChanges;

  PetPostDraftController get _draft =>
      ref.read(adoptionPostDraftProvider.notifier);

  @override
  void initState() {
    super.initState();
    final store = ref.read(tokenStoreProvider);
    if (store is GuardedAuthTokenStore) {
      // The draft provider clears the draft itself on a session change.
      _sessionChanges = store.sessionChanges.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPickingPhotos = false;
          _error = null;
        });
      });
    }
  }

  @override
  void dispose() {
    _sessionChanges?.cancel();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final draft = ref.read(adoptionPostDraftProvider);
    final attemptId = draft.publicationId;
    if (_isPickingPhotos || draft.locked) {
      return;
    }
    final strings = ref.read(appStringsProvider);
    setState(() {
      _isPickingPhotos = true;
      _error = null;
    });
    try {
      final files = await ImagePicker().pickMultiImage(
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
        limit: 5 - draft.photos.length,
      );
      if (files.isEmpty) {
        return;
      }
      final preparedPhotos = await preparePickedXFilesForUpload(
        files,
        limit: 5 - draft.photos.length,
      );
      final uploads = preparedPhotos
          .map(
            (prepared) => LostPetPhotoUpload(
              bytes: prepared.bytes,
              filename: prepared.filename,
              contentType: prepared.contentType,
            ),
          )
          .toList(growable: false);
      if (mounted &&
          ref.read(adoptionPostDraftProvider).publicationId == attemptId) {
        _draft.addPhotos(uploads);
      }
    } catch (error) {
      logPhotoPipelineFailure('adoption_gallery_picker', error);
      if (mounted) {
        setState(() => _error = selectedImageErrorMessage(strings, error));
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingPhotos = false);
      }
    }
  }

  Future<void> _submit() async {
    final strings = ref.read(appStringsProvider);
    final draft = ref.read(adoptionPostDraftProvider);
    if (draft.submitting || _isPickingPhotos || draft.completedUnavailable) {
      return;
    }
    if (draft.photos.isEmpty) {
      setState(() {
        _error = strings.addAtLeastOnePhoto;
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _error = null);
    final published = await _draft.submit(strings: strings);
    if (!published) return;
    ref.invalidate(feedPostsProvider);
    _draft.reset();
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      context.go('/feed');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.listingPublished)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final draft = ref.watch(adoptionPostDraftProvider);
    final photos = draft.photos;
    final draftLocked = draft.locked;
    final error = _error ?? draft.errorMessage;
    return Scaffold(
      appBar: AppBar(title: Text(strings.findANewHome)),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              AppBadge(
                label: strings.rehoming,
                icon: Icons.home_outlined,
                color: AppPalette.adoption,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                strings.createRehomingPost,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                strings.createRehomingPostHelp,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(strings.photos,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < photos.length; index++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photos[index].bytes,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: PhotoRemoveButton(
                            position: index + 1,
                            total: photos.length,
                            strings: strings,
                            onPressed: draftLocked
                                ? null
                                : () => _draft.removePhotoAt(index),
                          ),
                        ),
                      ],
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        draftLocked || _isPickingPhotos || photos.length >= 5
                            ? null
                            : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(strings.addPhotosCount(photos.length)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: ValueKey('${draft.publicationId}:petName'),
                enabled: !draftLocked,
                initialValue: draft.petName,
                onChanged: _draft.setPetName,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: strings.petName,
                  hintText: 'Mittens',
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) {
                    return strings.petNameRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('${draft.publicationId}:info'),
                enabled: !draftLocked,
                initialValue: draft.additionalInfo,
                onChanged: _draft.setAdditionalInfo,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: strings.additionalInformation,
                  hintText: strings.adoptionInfoHint,
                  alignLabelWithHint: true,
                ),
              ),
              // The profile phone is the consent: name what will be shared.
              const ContactShareNotice(),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: draft.submitting ||
                        _isPickingPhotos ||
                        draft.completedUnavailable
                    ? null
                    : () => unawaited(_submit()),
                icon: draft.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: Text(draft.completedUnavailable
                    ? strings.publicationAlreadyPublished
                    : draft.outcomeUnknown
                        ? strings.checkPublicationStatus
                        : strings.publishAdoptionPost),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
