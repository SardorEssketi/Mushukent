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
import '../../../feed/presentation/screens/feed_screen.dart';
import 'adoption_post_detail_screen.dart';

class AdoptionPostEditScreen extends ConsumerStatefulWidget {
  const AdoptionPostEditScreen({super.key, required this.adoptionPostId});

  final String adoptionPostId;

  @override
  ConsumerState<AdoptionPostEditScreen> createState() =>
      _AdoptionPostEditScreenState();
}

class _AdoptionPostEditScreenState
    extends ConsumerState<AdoptionPostEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _info = TextEditingController();
  final _phone = TextEditingController();
  final _telegram = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _picking = false;
  List<LostPetPhotoUpload>? _replacementPhotos;

  @override
  void dispose() {
    _name.dispose();
    _info.dispose();
    _phone.dispose();
    _telegram.dispose();
    super.dispose();
  }

  void _initialize(AdoptionPostData post) {
    if (_initialized) return;
    _initialized = true;
    _name.text = post.petName;
    _info.text = post.additionalInfo ?? '';
    _phone.text = post.ownerPhoneNumber;
    _telegram.text = post.ownerTelegramUsername ?? '';
  }

  Future<void> _pick(AppStrings strings) async {
    if (_picking) return;
    try {
      final files = await ImagePicker().pickMultiImage(
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
        limit: 5,
      );
      if (files.isEmpty) return;
      setState(() => _picking = true);
      final prepared = await preparePickedXFilesForUpload(files, limit: 5);
      if (mounted) {
        setState(() => _replacementPhotos = prepared
            .map((photo) => LostPetPhotoUpload(
                  bytes: photo.bytes,
                  filename: photo.filename,
                  contentType: photo.contentType,
                ))
            .toList(growable: false));
      }
    } catch (error) {
      logPhotoPipelineFailure('adoption_edit_gallery_picker', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(selectedImageErrorMessage(strings, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save(AppStrings strings) async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(mushukistanApiProvider).updateAdoptionPost(
            adoptionPostId: widget.adoptionPostId,
            petName: _name.text,
            phoneNumber: _phone.text,
            telegramUsername: _telegram.text,
            additionalInfo: _info.text,
            replacementPhotos: _replacementPhotos,
          );
      ref.read(adoptionMutationOverridesProvider.notifier).state = {
        ...ref.read(adoptionMutationOverridesProvider),
        updated.id: updated,
      };
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(adoptionPostDetailProvider(widget.adoptionPostId));
      ref.invalidate(feedPostsProvider);
      if (mounted) context.pop(true);
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
    final postAsync =
        ref.watch(adoptionPostDetailProvider(widget.adoptionPostId));
    return Scaffold(
      appBar: AppBar(title: Text(strings.editAdoptionPost)),
      body: postAsync.when(
        data: (post) {
          _initialize(post);
          final photoUrls = post.photoUrls;
          return Form(
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
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        child: replacement == null
                            ? Image.network(photoUrls[index],
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined))
                            : Image.memory(replacement[index].bytes,
                                width: 96, height: 96, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving || _picking ? null : () => _pick(strings),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(strings.replacePhotos),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _name,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: strings.petsName),
                  validator: (value) => (value?.trim().isNotEmpty ?? false)
                      ? null
                      : strings.enterPetsName,
                ),
                TextFormField(
                  controller: _info,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration:
                      InputDecoration(labelText: strings.additionalInformation),
                ),
                TextFormField(
                  controller: _phone,
                  decoration: InputDecoration(labelText: strings.phoneNumber),
                  validator: (value) => (value?.trim().isNotEmpty ?? false)
                      ? null
                      : strings.phoneNumberRequired,
                ),
                TextFormField(
                  controller: _telegram,
                  decoration:
                      InputDecoration(labelText: strings.telegramUsername),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _saving ? null : () => unawaited(_save(strings)),
                  child: Text(strings.saveChanges),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.editAdoptionPost,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () => ref
                .invalidate(adoptionPostDetailProvider(widget.adoptionPostId)),
            child: Text(strings.retry),
          ),
        ),
      ),
    );
  }
}
