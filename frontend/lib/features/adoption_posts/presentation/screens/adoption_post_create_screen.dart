import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../feed/presentation/screens/feed_screen.dart';

class AdoptionPostCreateScreen extends ConsumerStatefulWidget {
  const AdoptionPostCreateScreen({super.key});

  @override
  ConsumerState<AdoptionPostCreateScreen> createState() =>
      _AdoptionPostCreateScreenState();
}

class _AdoptionPostCreateScreenState
    extends ConsumerState<AdoptionPostCreateScreen> {
  final _petNameController = TextEditingController();
  final _infoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<LostPetPhotoUpload> _photos = [];
  bool _isSubmitting = false;
  bool _phonePublicationConsent = false;
  String? _error;

  @override
  void dispose() {
    _petNameController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null) {
      return;
    }
    final uploads = <LostPetPhotoUpload>[];
    final availableSlots = 5 - _photos.length;
    for (final file in result.files
        .where((file) => file.bytes != null)
        .take(availableSlots)) {
      final prepared = await prepareImageForUpload(
        bytes: file.bytes as Uint8List,
        filename: file.name,
      );
      uploads.add(
        LostPetPhotoUpload(
          bytes: prepared.bytes,
          filename: prepared.filename,
          contentType: prepared.contentType,
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _photos.addAll(uploads);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (_photos.isEmpty) {
      setState(() {
        _error = 'Add at least one photo.';
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (!_phonePublicationConsent) {
      setState(() {
        _error = 'Confirm that your phone number may be shown publicly.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(mushukistanApiProvider).createAdoptionPost(
            photos: _photos,
            petName: _petNameController.text,
            ownerPhonePublicationConsent: _phonePublicationConsent,
            additionalInfo: _infoController.text,
          );
      ref.invalidate(feedPostsProvider);
      if (mounted) {
        context.go('/feed');
      }
    } on MushukistanApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.userMessage;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a new home')),
      body: AppContentWidth(
        maxWidth: AppWidths.readable,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              const AppBadge(
                label: 'Rehoming',
                icon: Icons.home_outlined,
                color: AppPalette.adoption,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Create a rehoming post',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Describe the cat and the kind of home they need. This is separate from lost-pet alerts and does not require a map location.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Photos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _photos.length; index++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _photos[index].bytes,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton.filledTonal(
                            onPressed: () {
                              setState(() {
                                _photos.removeAt(index);
                              });
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ],
                    ),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting || _photos.length >= 5
                        ? null
                        : _pickPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Add photos (${_photos.length}/5)'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _petNameController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: "Pet's name",
                  hintText: 'Mittens',
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) {
                    return "Enter the pet's name.";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _infoController,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Additional information',
                  hintText:
                      'Age, personality, health notes, and preferred home.',
                  alignLabelWithHint: true,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _phonePublicationConsent,
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        setState(() {
                          _phonePublicationConsent = value ?? false;
                          _error = null;
                        });
                      },
                title: const Text('Show my phone number publicly'),
                subtitle: const Text(
                  'People need your profile phone number to contact you about adoption.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : () => unawaited(_submit()),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: const Text('Publish adoption post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
