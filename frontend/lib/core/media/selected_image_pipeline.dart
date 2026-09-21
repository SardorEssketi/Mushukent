import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'blob_url_lifecycle.dart';
import 'image_upload_preprocessor.dart';

typedef BlobUrlReleaser = void Function(String path);

enum SelectedImageFailure {
  readFailed,
  unsupportedFormat,
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
        await _prepareXFile(file, releaseUrl: releaseUrl),
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
}) {
  return _prepareXFile(file, releaseUrl: releaseUrl);
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
}) async {
  try {
    final bytes = await file.readAsBytes();
    return _prepareBytes(bytes: bytes, filename: file.name);
  } catch (error) {
    logPhotoPipelineFailure('xfile_read_or_process', error);
    if (error is SelectedImageException) {
      rethrow;
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
}) async {
  try {
    return await prepareImageForUpload(bytes: bytes, filename: filename);
  } on ImagePreparationException catch (error) {
    throw SelectedImageException(
      switch (error.failure) {
        ImagePreparationFailure.unsupportedFormat =>
          SelectedImageFailure.unsupportedFormat,
        ImagePreparationFailure.invalidImage =>
          SelectedImageFailure.invalidImage,
        ImagePreparationFailure.tooLarge => SelectedImageFailure.tooLarge,
      },
    );
  }
}

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
