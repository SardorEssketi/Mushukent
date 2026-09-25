import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../localization/app_strings.dart';
import '../network/api_error.dart';
import 'blob_url_lifecycle.dart';
import 'heif_normalizer.dart';
import 'image_upload_preprocessor.dart';

typedef BlobUrlReleaser = void Function(String path);
typedef HeifNormalizer = Future<Uint8List?> Function(String path);

enum SelectedImageFailure {
  readFailed,
  unsupportedFormat,
  heifUnsupported,
  invalidImage,
  tooLarge
}

class SelectedImageException implements Exception {
  const SelectedImageException(this.failure);

  final SelectedImageFailure failure;
}

Future<List<PreparedImageUpload>> preparePickedXFilesForUpload(
  List<XFile> files, {
  int limit = 5,
  BlobUrlReleaser releaseUrl = releaseBlobUrl,
  HeifNormalizer normalizeHeif = normalizeHeifFromPicker,
}) async {
  final uploads = <PreparedImageUpload>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    if (index >= limit) {
      releaseUrl(file.path);
      continue;
    }
    try {
      uploads.add(
        await _prepareXFile(
          file,
          releaseUrl: releaseUrl,
          normalizeHeif: normalizeHeif,
        ),
      );
    } catch (_) {
      for (final remaining in files.skip(index + 1)) {
        releaseUrl(remaining.path);
      }
      rethrow;
    }
  }
  return uploads;
}

void releasePickedXFiles(
  Iterable<XFile> files, {
  BlobUrlReleaser releaseUrl = releaseBlobUrl,
}) {
  for (final file in files) {
    releaseUrl(file.path);
  }
}

Future<PreparedImageUpload> preparePickedXFileForUpload(
  XFile file, {
  BlobUrlReleaser releaseUrl = releaseBlobUrl,
  HeifNormalizer normalizeHeif = normalizeHeifFromPicker,
  bool preserveTransparency = false,
}) {
  return _prepareXFile(
    file,
    releaseUrl: releaseUrl,
    normalizeHeif: normalizeHeif,
    preserveTransparency: preserveTransparency,
  );
}

Future<List<PreparedImageUpload>> preparePlatformFilesForUpload(
  List<PlatformFile> files, {
  int limit = 5,
  BlobUrlReleaser releaseUrl = releaseBlobUrl,
}) async {
  final uploads = <PreparedImageUpload>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    if (index >= limit) {
      _releasePlatformFile(file, releaseUrl);
      continue;
    }
    try {
      uploads.add(
        await _preparePlatformFile(file, releaseUrl: releaseUrl),
      );
    } catch (_) {
      for (final remaining in files.skip(index + 1)) {
        _releasePlatformFile(remaining, releaseUrl);
      }
      rethrow;
    }
  }
  return uploads;
}

Future<PreparedImageUpload> _prepareXFile(
  XFile file, {
  required BlobUrlReleaser releaseUrl,
  required HeifNormalizer normalizeHeif,
  bool preserveTransparency = false,
}) async {
  try {
    if (await file.length() > maxUploadImageBytes) {
      throw const SelectedImageException(SelectedImageFailure.tooLarge);
    }
    var bytes = await file.readAsBytes();
    if (isHeifImage(bytes)) {
      final converted = await normalizeHeif(file.path);
      if (converted == null) {
        throw const SelectedImageException(
          SelectedImageFailure.heifUnsupported,
        );
      }
      bytes = converted;
    }
    return _prepareBytes(
      bytes: bytes,
      filename: file.name,
      preserveTransparency: preserveTransparency,
    );
  } catch (error) {
    logPhotoPipelineFailure('xfile_read_or_process', error);
    if (error is SelectedImageException) {
      rethrow;
    }
    if (error is ImagePreparationException) {
      throw SelectedImageException(
        _selectedFailureFromPreparation(error.failure),
      );
    }
    throw const SelectedImageException(SelectedImageFailure.readFailed);
  } finally {
    releaseUrl(file.path);
  }
}

Future<PreparedImageUpload> _preparePlatformFile(
  PlatformFile file, {
  required BlobUrlReleaser releaseUrl,
}) async {
  try {
    if (file.size > maxUploadImageBytes) {
      throw const SelectedImageException(SelectedImageFailure.tooLarge);
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const SelectedImageException(SelectedImageFailure.readFailed);
    }
    return _prepareBytes(bytes: bytes, filename: file.name);
  } catch (error) {
    logPhotoPipelineFailure('platform_file_read_or_process', error);
    if (error is SelectedImageException) {
      rethrow;
    }
    throw const SelectedImageException(SelectedImageFailure.readFailed);
  } finally {
    _releasePlatformFile(file, releaseUrl);
  }
}

Future<PreparedImageUpload> _prepareBytes({
  required Uint8List bytes,
  required String filename,
  bool preserveTransparency = false,
}) async {
  try {
    return await prepareImageForUpload(
      bytes: bytes,
      filename: filename,
      preserveTransparency: preserveTransparency,
    );
  } on ImagePreparationException catch (error) {
    throw SelectedImageException(
        _selectedFailureFromPreparation(error.failure));
  }
}

SelectedImageFailure _selectedFailureFromPreparation(
  ImagePreparationFailure failure,
) =>
    switch (failure) {
      ImagePreparationFailure.unsupportedFormat =>
        SelectedImageFailure.unsupportedFormat,
      ImagePreparationFailure.invalidImage => SelectedImageFailure.invalidImage,
      ImagePreparationFailure.tooLarge => SelectedImageFailure.tooLarge,
    };

void _releasePlatformFile(
  PlatformFile file,
  BlobUrlReleaser releaseUrl,
) {
  final path = file.path;
  if (path != null) {
    releaseUrl(path);
  }
}

void logPhotoPipelineFailure(String stage, Object error) {
  debugPrint(
    'Photo pipeline failure: stage=$stage type=${error.runtimeType}',
  );
}

String selectedImageErrorMessage(AppStrings strings, Object error) {
  if (error is! SelectedImageException) {
    return strings.couldNotPreparePhoto;
  }
  return switch (error.failure) {
    SelectedImageFailure.unsupportedFormat => strings.unsupportedPhotoFormat,
    SelectedImageFailure.heifUnsupported => strings.heifPhotoUnsupported,
    SelectedImageFailure.invalidImage => strings.invalidPhoto,
    SelectedImageFailure.tooLarge => strings.photoTooLarge,
    SelectedImageFailure.readFailed => strings.couldNotReadPhoto,
  };
}

String photoUploadErrorMessage(AppStrings strings, Object error) {
  if (error is! MushukistanApiException) {
    return strings.couldNotSaveChanges;
  }
  if (error.kind == ApiFailureKind.unauthorized) {
    return strings.photoUploadRequiresSignIn;
  }
  return switch (error.code) {
    'INVALID_IMAGE' => strings.invalidPhoto,
    'PAYLOAD_TOO_LARGE' => strings.photoTooLarge,
    'PHOTO_UPLOAD_TIMEOUT' => strings.photoUploadTimedOut,
    'PHOTO_UPLOAD_NETWORK_ERROR' => strings.photoUploadNetworkError,
    'IMAGE_UPLOAD_FAILED' => strings.photoUploadStorageError,
    _ => error.kind == ApiFailureKind.server
        ? strings.photoUploadStorageError
        : error.userMessage,
  };
}
