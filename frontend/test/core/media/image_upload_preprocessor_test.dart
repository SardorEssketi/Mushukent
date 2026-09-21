import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mushukistan_frontend/core/media/image_upload_preprocessor.dart';

void main() {
  test('prepares JPEG bytes for upload', () async {
    final source = image.Image(width: 640, height: 480)
      ..setPixelRgb(20, 20, 240, 120, 60);
    final bytes = Uint8List.fromList(image.encodeJpg(source));

    final prepared = await prepareImageForUpload(
      bytes: bytes,
      filename: 'cat.jpeg',
    );

    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.filename, 'cat.jpg');
    expect(image.decodeImage(prepared.bytes), isNotNull);
  });

  test('accepts PNG bytes and produces durable upload bytes', () async {
    final source = image.Image(width: 320, height: 320)
      ..setPixelRgba(10, 10, 20, 80, 160, 255);
    final bytes = Uint8List.fromList(image.encodePng(source));

    final prepared = await prepareImageForUpload(
      bytes: bytes,
      filename: 'cat.png',
    );

    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.filename, 'cat.jpg');
    expect(prepared.bytes, isNotEmpty);
  });

  test('rejects unsupported formats before upload', () async {
    await expectLater(
      prepareImageForUpload(
        bytes: Uint8List.fromList(<int>[0x47, 0x49, 0x46, 0x38, 0x39]),
        filename: 'cat.gif',
      ),
      throwsA(
        isA<ImagePreparationException>().having(
          (error) => error.failure,
          'failure',
          ImagePreparationFailure.unsupportedFormat,
        ),
      ),
    );
  });
}
