import 'dart:typed_data';

import 'package:image/image.dart' as image;

class PreparedImageUpload {
  const PreparedImageUpload({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}

enum ImagePreparationFailure { unsupportedFormat, invalidImage, tooLarge }

class ImagePreparationException implements Exception {
  const ImagePreparationException(this.failure);

  final ImagePreparationFailure failure;
}

const int maxUploadImageBytes = 10 * 1024 * 1024;
const int targetUploadImageBytes = 8 * 1024 * 1024;
const int uploadImageLongestSide = 1920;
const int maxSourceImagePixels = 25 * 1000 * 1000;

Future<PreparedImageUpload> prepareImageForUpload({
  required Uint8List bytes,
  required String filename,
  bool preserveTransparency = false,
}) async {
  return Future(() {
    if (bytes.length > maxUploadImageBytes) {
      throw const ImagePreparationException(ImagePreparationFailure.tooLarge);
    }
    if (!_isSupportedImage(bytes)) {
      throw const ImagePreparationException(
        ImagePreparationFailure.unsupportedFormat,
      );
    }
    image.Image? decoded;
    try {
      final decoder = image.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (decoder == null || info == null) {
        throw const ImagePreparationException(
          ImagePreparationFailure.invalidImage,
        );
      }
      if (info.width <= 0 ||
          info.height <= 0 ||
          info.width * info.height > maxSourceImagePixels) {
        throw const ImagePreparationException(
          ImagePreparationFailure.tooLarge,
        );
      }
      decoded = decoder.decodeFrame(0);
    } on ImagePreparationException {
      rethrow;
    } catch (_) {
      throw const ImagePreparationException(
        ImagePreparationFailure.invalidImage,
      );
    }
    if (decoded == null) {
      throw const ImagePreparationException(
        ImagePreparationFailure.invalidImage,
      );
    }

    final oriented = image.bakeOrientation(decoded);
    final resized = _resizeToLongestSide(oriented, uploadImageLongestSide);
    if (preserveTransparency && resized.hasAlpha) {
      final encoded = Uint8List.fromList(image.encodePng(resized));
      if (encoded.length > maxUploadImageBytes) {
        throw const ImagePreparationException(ImagePreparationFailure.tooLarge);
      }
      return PreparedImageUpload(
        bytes: encoded,
        filename: _pngFilename(filename),
        contentType: 'image/png',
      );
    }
    var quality = 88;
    var encoded =
        Uint8List.fromList(image.encodeJpg(resized, quality: quality));

    while (encoded.length > targetUploadImageBytes && quality > 68) {
      quality -= 6;
      encoded = Uint8List.fromList(image.encodeJpg(resized, quality: quality));
    }

    if (encoded.length > targetUploadImageBytes) {
      final smaller = _resizeToLongestSide(resized, 1440);
      quality = 82;
      encoded = Uint8List.fromList(image.encodeJpg(smaller, quality: quality));
      while (encoded.length > targetUploadImageBytes && quality > 64) {
        quality -= 6;
        encoded =
            Uint8List.fromList(image.encodeJpg(smaller, quality: quality));
      }
    }

    if (encoded.length > maxUploadImageBytes) {
      throw const ImagePreparationException(ImagePreparationFailure.tooLarge);
    }

    return PreparedImageUpload(
      bytes: encoded,
      filename: _jpegFilename(filename),
      contentType: 'image/jpeg',
    );
  });
}

bool isHeifImage(Uint8List bytes) {
  if (bytes.length < 12 ||
      bytes[4] != 0x66 ||
      bytes[5] != 0x74 ||
      bytes[6] != 0x79 ||
      bytes[7] != 0x70) {
    return false;
  }
  const heifBrands = <String>{
    'heic',
    'heix',
    'hevc',
    'hevx',
    'heim',
    'heis',
    'heif',
  };
  final brandLength = bytes.length < 64 ? bytes.length : 64;
  for (var index = 8; index + 4 <= brandLength; index += 4) {
    if (heifBrands
        .contains(String.fromCharCodes(bytes.sublist(index, index + 4)))) {
      return true;
    }
  }
  return false;
}

bool _isSupportedImage(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return true;
  }
  return bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;
}

image.Image _resizeToLongestSide(image.Image source, int longestSide) {
  final width = source.width;
  final height = source.height;
  final longest = width > height ? width : height;
  if (longest <= longestSide) {
    return source;
  }

  if (width >= height) {
    return image.copyResize(source, width: longestSide);
  }
  return image.copyResize(source, height: longestSide);
}

String _jpegFilename(String filename) {
  return _filenameWithExtension(filename, 'jpg');
}

String _pngFilename(String filename) {
  return _filenameWithExtension(filename, 'png');
}

String _filenameWithExtension(String filename, String extension) {
  final trimmed = filename.trim();
  if (trimmed.isEmpty) {
    return 'upload.$extension';
  }
  final dotIndex = trimmed.lastIndexOf('.');
  if (dotIndex <= 0) {
    return '$trimmed.$extension';
  }
  return '${trimmed.substring(0, dotIndex)}.$extension';
}
