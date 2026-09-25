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

  test('keeps transparent avatar PNG transparent', () async {
    final source = image.Image(width: 32, height: 32, numChannels: 4)
      ..setPixelRgba(8, 8, 20, 80, 160, 64);

    final prepared = await prepareImageForUpload(
      bytes: Uint8List.fromList(image.encodePng(source)),
      filename: 'avatar.png',
      preserveTransparency: true,
    );
    final decoded = image.decodePng(prepared.bytes);

    expect(prepared.contentType, 'image/png');
    expect(prepared.filename, 'avatar.png');
    expect(decoded, isNotNull);
    expect(decoded!.getPixel(8, 8).a, 64);
  });

  test('bakes EXIF portrait orientation into JPEG pixels', () async {
    final source = image.Image(width: 40, height: 20);
    source.exif.imageIfd.orientation = 6;

    final prepared = await prepareImageForUpload(
      bytes: Uint8List.fromList(image.encodeJpg(source)),
      filename: 'portrait.jpg',
    );
    final decoded = image.decodeJpg(prepared.bytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, 20);
    expect(decoded.height, 40);
    expect(decoded.exif.imageIfd.orientation, isNot(6));
  });

  test('accepts native picker JPEG bytes even with a HEIC filename', () async {
    final prepared = await prepareImageForUpload(
      bytes: Uint8List.fromList(
          image.encodeJpg(image.Image(width: 24, height: 24))),
      filename: 'iPhone photo.heic',
    );

    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.filename, 'iPhone photo.jpg');
  });

  test('resizes a normal high-resolution phone JPEG to the upload bound',
      () async {
    final source = image.Image(width: 4032, height: 3024);
    final bytes = Uint8List.fromList(image.encodeJpg(source, quality: 95));

    final prepared = await prepareImageForUpload(
      bytes: bytes,
      filename: 'phone camera.jpg',
    );
    final decoded = image.decodeJpg(prepared.bytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, 1920);
    expect(decoded.height, 1440);
    expect(prepared.bytes.length, lessThanOrEqualTo(maxUploadImageBytes));
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

  test('rejects raw WebP and HEIC inputs with unsupported-format error',
      () async {
    final unsupported = <Uint8List>[
      Uint8List.fromList('RIFF0000WEBP'.codeUnits),
      Uint8List.fromList(<int>[
        0x00,
        0x00,
        0x00,
        0x18,
        ...'ftypheic'.codeUnits,
      ]),
    ];

    for (final bytes in unsupported) {
      await expectLater(
        prepareImageForUpload(bytes: bytes, filename: 'unsupported.image'),
        throwsA(
          isA<ImagePreparationException>().having(
            (error) => error.failure,
            'failure',
            ImagePreparationFailure.unsupportedFormat,
          ),
        ),
      );
    }
  });

  test('rejects oversized pixel dimensions before decoding pixels', () async {
    final source = image.Image(width: 8, height: 8);
    final bytes = Uint8List.fromList(image.encodeJpg(source));
    final marker = _findStartOfFrame(bytes);
    expect(marker, isNonNegative);
    bytes[marker + 5] = 0x13;
    bytes[marker + 6] = 0x88;
    bytes[marker + 7] = 0x17;
    bytes[marker + 8] = 0x70;

    await expectLater(
      prepareImageForUpload(bytes: bytes, filename: 'huge.jpg'),
      throwsA(
        isA<ImagePreparationException>().having(
          (error) => error.failure,
          'failure',
          ImagePreparationFailure.tooLarge,
        ),
      ),
    );
  });

  test('preserves readable Unicode filename while normalizing extension',
      () async {
    final source = image.Image(width: 16, height: 16);

    final prepared = await prepareImageForUpload(
      bytes: Uint8List.fromList(image.encodePng(source)),
      filename: 'мой кот.png',
    );

    expect(prepared.filename, 'мой кот.jpg');
  });
}

int _findStartOfFrame(Uint8List bytes) {
  for (var index = 0; index < bytes.length - 9; index++) {
    if (bytes[index] == 0xff &&
        (bytes[index + 1] == 0xc0 || bytes[index + 1] == 0xc2)) {
      return index;
    }
  }
  return -1;
}
