import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../../feed/presentation/screens/feed_screen.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/presentation/screens/user_activity_screen.dart';
import 'post_detail_screen.dart';

const _editablePostStatuses = <String>{
  'unknown',
  'healthy',
  'injured',
  'needs_help',
  'adopted',
};

class PostEditScreen extends ConsumerStatefulWidget {
  const PostEditScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostEditScreen> createState() => _PostEditScreenState();
}

class _PostEditScreenState extends ConsumerState<PostEditScreen> {
  final _descriptionController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _pickingPhotos = false;
  bool _isPublic = true;
  GeoPoint? _location;
  String? _status;
  List<ObservationPhotoUpload>? _replacementPhotos;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _initialize(PostDetail post) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _descriptionController.text = post.description ?? '';
    _isPublic = post.isPublic;
    _location = post.location;
    _status = _editablePostStatuses.contains(post.status) ? post.status : null;
  }

  Future<void> _replacePhotos(AppStrings strings) async {
    if (_pickingPhotos) {
      return;
    }
    final images =
        await ImagePicker().pickMultiImage(imageQuality: 90, limit: 5);
    if (images.isEmpty || !mounted) {
      return;
    }
    setState(() => _pickingPhotos = true);
    try {
      final uploads = <ObservationPhotoUpload>[];
      for (final image in images.take(5)) {
        final prepared = await prepareImageForUpload(
          bytes: await image.readAsBytes(),
          filename: image.name,
        );
        uploads.add(
          ObservationPhotoUpload(
            bytes: prepared.bytes,
            filename: prepared.filename,
            contentType: prepared.contentType,
          ),
        );
      }
      if (mounted) {
        setState(() => _replacementPhotos = uploads);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotPreparePhoto(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pickingPhotos = false);
      }
    }
  }

  Future<void> _useCurrentLocation(AppStrings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.useCurrentLocationTitle),
        content: Text(strings.useCurrentLocationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.continueAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final location = await LocationService().resolveCurrentLocation();
    if (!mounted) {
      return;
    }
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.couldNotResolveYourLocation)),
      );
      return;
    }
    setState(() => _location = location);
  }

  Future<void> _save(AppStrings strings) async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(mushukistanApiProvider).updateObservation(
            postId: widget.postId,
            description: _descriptionController.text,
            location: _location,
            isPublic: _isPublic,
            status: _status,
            replacementPhotos: _replacementPhotos,
          );
      ref.read(postMutationRevisionProvider.notifier).state++;
      ref.invalidate(postDetailProvider(widget.postId));
      ref.invalidate(feedPostsProvider);
      ref.invalidate(profileMeProvider);
      final userId = ref.read(currentUserProvider)?.id;
      if (userId != null) {
        ref.invalidate(userPostsProvider(userId));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.changesSaved)),
        );
        context.pop(true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.couldNotSaveChanges)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final postAsync = ref.watch(postDetailProvider(widget.postId));
    return Scaffold(
      appBar: AppBar(title: Text(strings.editObservation)),
      body: postAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppStatePanel(
          icon: Icons.error_outline,
          title: strings.editObservation,
          message: strings.couldNotLoadSection,
          action: FilledButton(
            onPressed: () => ref.invalidate(postDetailProvider(widget.postId)),
            child: Text(strings.retry),
          ),
        ),
        data: (post) {
          _initialize(post);
          final photoCount =
              _replacementPhotos?.length ?? post.photoUrls.length;
          return AppContentWidth(
            maxWidth: AppWidths.readable,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                TextField(
                  controller: _descriptionController,
                  maxLength: 2000,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: strings.descriptionLabel,
                    hintText: strings.descriptionHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isPublic,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _isPublic = value),
                  title: Text(strings.privacy),
                  subtitle: Text(_isPublic
                      ? strings.allowPublicActivityView
                      : strings.private),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: strings.catStatus),
                  hint: Text(strings.unknown),
                  items: [
                    DropdownMenuItem(
                      value: 'unknown',
                      child: Text(strings.unknown),
                    ),
                    DropdownMenuItem(
                      value: 'healthy',
                      child: Text(strings.healthy),
                    ),
                    DropdownMenuItem(
                      value: 'injured',
                      child: Text(strings.injured),
                    ),
                    DropdownMenuItem(
                      value: 'needs_help',
                      child: Text(strings.needsHelp),
                    ),
                    DropdownMenuItem(
                      value: 'adopted',
                      child: Text(strings.adoption),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(strings.replacePhotos),
                  subtitle: Text('$photoCount ${strings.photo.toLowerCase()}'),
                  trailing: _pickingPhotos
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _saving || _pickingPhotos
                      ? null
                      : () => _replacePhotos(strings),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.my_location_outlined),
                  title: Text(strings.updateLocationFromDevice),
                  subtitle: Text(_location == null
                      ? strings.continueWithoutLocation
                      : '${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : () => _useCurrentLocation(strings),
                ),
                if (_location != null)
                  TextButton.icon(
                    onPressed:
                        _saving ? null : () => setState(() => _location = null),
                    icon: const Icon(Icons.location_off_outlined),
                    label: Text(strings.removeLocation),
                  ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: _saving ? null : () => _save(strings),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.saveChanges),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
