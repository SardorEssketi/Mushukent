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

const int maxUploadImageBytes = 10 * 1024 * 1024;
const int targetUploadImageBytes = 8 * 1024 * 1024;
const int uploadImageLongestSide = 1920;

Future<PreparedImageUpload> prepareImageForUpload({
  required Uint8List bytes,
  required String filename,
}) async {
  return Future(() {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) {
      return PreparedImageUpload(
        bytes: bytes,
        filename: filename,
        contentType: _contentTypeForFilename(filename),
      );
    }

    final oriented = image.bakeOrientation(decoded);
    final resized = _resizeToLongestSide(oriented, uploadImageLongestSide);
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

    return PreparedImageUpload(
      bytes: encoded,
      filename: _jpegFilename(filename),
      contentType: 'image/jpeg',
    );
  });
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
  final trimmed = filename.trim();
  if (trimmed.isEmpty) {
    return 'upload.jpg';
  }
  final dotIndex = trimmed.lastIndexOf('.');
  if (dotIndex <= 0) {
    return '$trimmed.jpg';
  }
  return '${trimmed.substring(0, dotIndex)}.jpg';
}

String _contentTypeForFilename(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  return 'image/jpeg';
}
