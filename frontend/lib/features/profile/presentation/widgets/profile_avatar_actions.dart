import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/media/image_picker_options.dart';
import '../../../../core/media/image_upload_preprocessor.dart';
import '../../../../core/media/selected_image_pipeline.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/network/mushukistan_api.dart';
import '../../../../core/theme/app_design_tokens.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../screens/profile_screen.dart';
import 'avatar_crop_editor.dart';

enum ProfileAvatarAction { open, gallery, camera, delete }

/// Whether "Take photo" is offered. On the web only phone and tablet browsers
/// open a camera; a desktop browser would just show a file dialog again.
final avatarCameraAvailableProvider = Provider<bool>((ref) {
  if (kIsWeb) {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
  return ImagePicker().supportsImageSource(ImageSource.camera);
});

/// Picks a photo; overridable in tests.
final avatarImagePickerProvider =
    Provider<Future<XFile?> Function(ImageSource source)>(
  (ref) => (source) => ImagePicker().pickImage(
        source: source,
        imageQuality: pickerImageQuality,
        maxWidth: pickerMaxWidth,
        maxHeight: pickerMaxHeight,
      ),
);

/// Opens the crop editor; overridable in tests.
final avatarCropperProvider =
    Provider<Future<Uint8List?> Function(BuildContext, Uint8List)>(
  (ref) => showAvatarCropEditor,
);

/// True while a photo is being prepared, uploaded or removed.
final profileAvatarBusyProvider =
    StateProvider.autoDispose<bool>((ref) => false);

Future<ProfileAvatarAction?> showProfileAvatarActions(
  BuildContext context,
  AppStrings strings, {
  required bool hasPhoto,
  required bool cameraAvailable,
}) {
  return showModalBottomSheet<ProfileAvatarAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      Widget option(IconData icon, String label, ProfileAvatarAction action,
              {bool destructive = false}) =>
          ListTile(
            leading: Icon(icon,
                color: destructive
                    ? Theme.of(sheetContext).colorScheme.error
                    : null),
            title: Text(label,
                style: destructive
                    ? TextStyle(color: Theme.of(sheetContext).colorScheme.error)
                    : null),
            onTap: () => Navigator.of(sheetContext).pop(action),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.profilePhoto,
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              if (hasPhoto)
                option(Icons.fullscreen, strings.openPhoto,
                    ProfileAvatarAction.open),
              option(Icons.photo_library_outlined, strings.chooseFromGallery,
                  ProfileAvatarAction.gallery),
              if (cameraAvailable)
                option(Icons.photo_camera_outlined, strings.takePhoto,
                    ProfileAvatarAction.camera),
              if (hasPhoto)
                option(Icons.delete_outline, strings.deletePhoto,
                    ProfileAvatarAction.delete,
                    destructive: true),
            ],
          ),
        ),
      );
    },
  );
}

/// The avatar tap on the profile screen: sheet, then view, replace or remove.
Future<void> handleProfileAvatarTap(
  BuildContext context,
  WidgetRef ref, {
  required String? avatarUrl,
}) async {
  if (ref.read(profileAvatarBusyProvider)) return;
  final strings = ref.read(appStringsProvider);
  final url = avatarUrl?.trim();
  final hasPhoto = url != null && url.isNotEmpty;
  final action = await showProfileAvatarActions(
    context,
    strings,
    hasPhoto: hasPhoto,
    cameraAvailable: ref.read(avatarCameraAvailableProvider),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case ProfileAvatarAction.open:
      await showAvatarViewer(context, url!);
    case ProfileAvatarAction.gallery:
      await _replaceAvatar(context, ref, ImageSource.gallery);
    case ProfileAvatarAction.camera:
      await _replaceAvatar(context, ref, ImageSource.camera);
    case ProfileAvatarAction.delete:
      await _removeAvatar(context, ref);
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _replaceAvatar(
  BuildContext context,
  WidgetRef ref,
  ImageSource source,
) async {
  final strings = ref.read(appStringsProvider);
  final busy = ref.read(profileAvatarBusyProvider.notifier);
  final PreparedImageUpload picked;
  try {
    final file = await ref.read(avatarImagePickerProvider)(source);
    if (file == null) return;
    // Same rules as every upload (size, format, HEIC), before cropping.
    picked =
        await preparePickedXFileForUpload(file, preserveTransparency: true);
  } catch (error) {
    logPhotoPipelineFailure(
        source == ImageSource.camera
            ? 'avatar_camera_picker'
            : 'avatar_gallery_picker',
        error);
    if (context.mounted) {
      _snack(context, selectedImageErrorMessage(strings, error));
    }
    return;
  }
  if (!context.mounted) return;
  final cropped = await ref.read(avatarCropperProvider)(context, picked.bytes);
  if (cropped == null || !context.mounted) return;

  busy.state = true;
  try {
    final PreparedImageUpload avatar;
    try {
      avatar = await preparePickedXFileForUpload(
        XFile.fromData(cropped, name: 'avatar.png', mimeType: 'image/png'),
        preserveTransparency: true,
      );
    } catch (error) {
      logPhotoPipelineFailure('avatar_crop_prepare', error);
      if (context.mounted) {
        _snack(context, selectedImageErrorMessage(strings, error));
      }
      return;
    }
    await ref.read(mushukistanApiProvider).updateAvatar(
          avatarBytes: avatar.bytes,
          avatarFilename: avatar.filename,
          avatarContentType: avatar.contentType,
        );
    ref.invalidate(profileMeProvider);
    if (context.mounted) _snack(context, strings.photoUpdated);
  } catch (error) {
    if (context.mounted) {
      _snack(context, photoUploadErrorMessage(strings, error));
    }
  } finally {
    if (context.mounted) busy.state = false;
  }
}

Future<void> _removeAvatar(BuildContext context, WidgetRef ref) async {
  final strings = ref.read(appStringsProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.deletePhotoTitle),
      content: Text(strings.deletePhotoMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final busy = ref.read(profileAvatarBusyProvider.notifier);
  busy.state = true;
  try {
    await ref.read(mushukistanApiProvider).deleteAvatar();
    ref.invalidate(profileMeProvider);
    if (context.mounted) _snack(context, strings.photoRemoved);
  } catch (error) {
    if (context.mounted) {
      _snack(
          context,
          error is MushukistanApiException &&
                  error.kind == ApiFailureKind.validation
              ? error.userMessage
              : strings.couldNotRemovePhoto);
    }
  } finally {
    if (context.mounted) busy.state = false;
  }
}

/// Full-screen photo with pinch zoom.
Future<void> showAvatarViewer(BuildContext context, String url) {
  return Navigator.of(context).push<void>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (viewerContext) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: AppRemoteImage(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: Colors.white54),
          ),
        ),
      ),
    ),
  ));
}
