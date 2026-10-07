import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/selected_image_pipeline.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import 'lost_pet_create_screen.dart';
import 'lost_pet_detail_screen.dart';

class LostPetEditScreen extends ConsumerStatefulWidget {
  const LostPetEditScreen({super.key, required this.lostPetId});

  final String lostPetId;

  @override
  ConsumerState<LostPetEditScreen> createState() => _LostPetEditScreenState();
}

class _LostPetEditScreenState extends ConsumerState<LostPetEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _petNameController = TextEditingController();
  final _infoController = TextEditingController();
  final _phoneController = TextEditingController();
  final _telegramController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _pickingPhotos = false;
  GeoPoint? _location;
  List<LostPetPhotoUpload>? _replacementPhotos;

  @override
  void dispose() {
    _petNameController.dispose();
    _infoController.dispose();
    _phoneController.dispose();
    _telegramController.dispose();
    super.dispose();
  }

  void _initialize(LostPetData pet) {
    if (_initialized) return;
    _initialized = true;
    _petNameController.text = pet.petName;
    _infoController.text = pet.additionalInfo ?? '';
    _phoneController.text = pet.ownerPhoneNumber ?? '';
    _telegramController.text = pet.ownerTelegramUsername ?? '';
    _location = pet.lastSeenLocation;
  }

  Future<void> _replacePhotos(AppStrings strings) async {
    if (_pickingPhotos) return;
    late final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
        limit: 5,
      );
    } catch (error) {
      logPhotoPipelineFailure('lost_pet_edit_gallery_picker', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(selectedImageErrorMessage(strings, error))),
        );
      }
      return;
    }
    if (files.isEmpty) return;
    if (!mounted) {
      releasePickedXFiles(files);
      return;
    }
    setState(() => _pickingPhotos = true);
    try {
      final prepared = await preparePickedXFilesForUpload(files, limit: 5);
      if (mounted) {
        setState(() {
          _replacementPhotos = prepared
              .map(
                (photo) => LostPetPhotoUpload(
                  bytes: photo.bytes,
                  filename: photo.filename,
                  contentType: photo.contentType,
                ),
              )
              .toList(growable: false);
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(selectedImageErrorMessage(strings, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  Future<void> _save(AppStrings strings) async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final location = _location;
    if (location == null) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(mushukistanApiProvider).updateLostPet(
            lostPetId: widget.lostPetId,
            petName: _petNameController.text,
            phoneNumber: _phoneController.text,
            telegramUsername: _telegramController.text,
            lastSeenLocation: location,
            additionalInfo: _infoController.text,
            replacementPhotos: _replacementPhotos,
          );
      ref.read(lostPetMutationOverridesProvider.notifier).state = {
        ...ref.read(lostPetMutationOverridesProvider),
        updated.id: updated,
      };
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(lostPetDetailProvider(widget.lostPetId));
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      ref.read(resolvedLostPetIdsProvider.notifier).state = {
        ...ref.read(resolvedLostPetIdsProvider),
        if (updated.isResolved) updated.id,
      };
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.pop(true);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(strings.changesSaved)));
      }
    } on MushukistanApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(photoUploadErrorMessage(strings, error))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSaveChanges)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final petAsync = ref.watch(lostPetDetailProvider(widget.lostPetId));
    return Scaffold(
      appBar: AppBar(title: Text(strings.editLostPet)),
      body: petAsync.when(
        data: (pet) {
          _initialize(pet);
          final photoUrls = pet.photoUrls;
          return AppContentWidth(
            maxWidth: AppWidths.readable,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Text(strings.photos,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _replacementPhotos?.length ?? photoUrls.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final replacement = _replacementPhotos;
                        if (replacement != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            child: Image.memory(
                              replacement[index].bytes,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          child: AppRemoteImage(
                            photoUrls[index],
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 96,
                              height: 96,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving || _pickingPhotos
                        ? null
                        : () => _replacePhotos(strings),
                    icon: _pickingPhotos
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(strings.replacePhotos),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _petNameController,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: strings.petsName),
                    validator: (value) => (value?.trim().isNotEmpty ?? false)
                        ? null
                        : strings.enterPetsName,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(strings.lastSeen,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  LostPetLocationPicker(
                    strings: strings,
                    selectedLocation: _location,
                    onSelected: (location) =>
                        setState(() => _location = location),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _infoController,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: strings.additionalInformation,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: strings.phoneNumber),
                    validator: (value) => (value?.trim().isNotEmpty ?? false)
                        ? null
                        : strings.phoneNumberRequiredForLostPet,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _telegramController,
                    decoration: InputDecoration(
                      labelText: strings.telegramUsername,
                      prefixText: '@',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _saving || _pickingPhotos
                        ? null
                        : () => unawaited(_save(strings)),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(strings.saveChanges),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.editLostPet,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () =>
                ref.invalidate(lostPetDetailProvider(widget.lostPetId)),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }
}
