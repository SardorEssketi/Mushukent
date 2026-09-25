import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:mushukistan_frontend/core/localization/app_strings.dart';
import 'package:mushukistan_frontend/core/localization/language_controller.dart';
import 'package:mushukistan_frontend/core/media/image_upload_preprocessor.dart';
import 'package:mushukistan_frontend/core/media/selected_image_pipeline.dart';
import 'package:mushukistan_frontend/core/network/api_error.dart';

void main() {
  late Uint8List jpegBytes;

  setUp(() {
    jpegBytes = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 320, height: 320)),
    );
  });

  test('materializes XFile bytes and releases its temporary path once',
      () async {
    final file = XFile.fromData(
      jpegBytes,
      name: 'cat.jpg',
      path: 'cat.jpg',
    );
    final releasedPaths = <String>[];

    final prepared = await preparePickedXFileForUpload(
      file,
      releaseUrl: releasedPaths.add,
    );

    expect(prepared.bytes, isNotEmpty);
    expect(prepared.filename, 'cat.jpg');
    expect(releasedPaths, <String>[file.path]);
  });

  test('empty picker result behaves as cancellation', () async {
    final releasedPaths = <String>[];

    final prepared = await preparePickedXFilesForUpload(
      const <XFile>[],
      releaseUrl: releasedPaths.add,
    );

    expect(prepared, isEmpty);
    expect(releasedPaths, isEmpty);
  });

  test('replacement limit releases selected files that are not retained',
      () async {
    final first = XFile.fromData(
      jpegBytes,
      name: 'first.jpg',
      path: 'first.jpg',
    );
    final second = XFile.fromData(
      jpegBytes,
      name: 'second.jpg',
      path: 'second.jpg',
    );
    final releasedPaths = <String>[];

    final prepared = await preparePickedXFilesForUpload(
      <XFile>[first, second],
      limit: 1,
      releaseUrl: releasedPaths.add,
    );

    expect(prepared, hasLength(1));
    expect(releasedPaths, <String>[first.path, second.path]);
  });

  test('FilePicker bytes are copied and its Blob path is released', () async {
    final file = PlatformFile(
      name: 'cat.jpg',
      size: jpegBytes.length,
      bytes: jpegBytes,
      path: 'blob:test-file',
    );
    final releasedPaths = <String>[];

    final prepared = await preparePlatformFilesForUpload(
      <PlatformFile>[file],
      releaseUrl: releasedPaths.add,
    );

    expect(prepared.single.bytes, isNotEmpty);
    expect(releasedPaths, <String>['blob:test-file']);
  });

  test('a failed read releases the path and a new selection can retry',
      () async {
    final missing = XFile('missing-photo-for-test.jpg', name: 'missing.jpg');
    final releasedPaths = <String>[];

    await expectLater(
      preparePickedXFileForUpload(
        missing,
        releaseUrl: releasedPaths.add,
      ),
      throwsA(
        isA<SelectedImageException>().having(
          (error) => error.failure,
          'failure',
          SelectedImageFailure.readFailed,
        ),
      ),
    );
    final retry = XFile.fromData(
      jpegBytes,
      name: 'retry.jpg',
      path: 'retry.jpg',
    );
    final prepared = await preparePickedXFileForUpload(
      retry,
      releaseUrl: releasedPaths.add,
    );

    expect(prepared.bytes, isNotEmpty);
    expect(releasedPaths, <String>[missing.path, retry.path]);
  });

  test('browser HEIC normalization supplies JPEG to the existing pipeline',
      () async {
    final heic = Uint8List.fromList(<int>[
      0,
      0,
      0,
      20,
      ...'ftypheic'.codeUnits,
      0,
      0,
      0,
      0,
      ...'heic'.codeUnits,
    ]);
    expect(isHeifImage(heic), isTrue);
    final selected =
        XFile.fromData(heic, name: 'holiday.heic', path: 'holiday.heic');
    final releasedPaths = <String>[];

    final prepared = await preparePickedXFileForUpload(
      selected,
      normalizeHeif: (path) async {
        expect(path, 'holiday.heic');
        return jpegBytes;
      },
      releaseUrl: releasedPaths.add,
    );

    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.filename, 'holiday.jpg');
    expect(releasedPaths, <String>['holiday.heic']);
  });

  test('HEIC without a working browser decoder gives export guidance',
      () async {
    final heic = Uint8List.fromList(<int>[
      0,
      0,
      0,
      16,
      ...'ftypheic'.codeUnits,
      0,
      0,
      0,
      0,
    ]);
    final selected =
        XFile.fromData(heic, name: 'holiday.heic', path: 'holiday.heic');
    final releasedPaths = <String>[];

    await expectLater(
      preparePickedXFileForUpload(
        selected,
        normalizeHeif: (_) async => null,
        releaseUrl: releasedPaths.add,
      ),
      throwsA(
        isA<SelectedImageException>().having(
          (error) => error.failure,
          'failure',
          SelectedImageFailure.heifUnsupported,
        ),
      ),
    );
    expect(releasedPaths, <String>['holiday.heic']);
    expect(
      selectedImageErrorMessage(
        AppStrings.forLanguage(AppLanguage.english),
        const SelectedImageException(SelectedImageFailure.heifUnsupported),
      ),
      contains('Save it as JPEG'),
    );
  });

  test('oversized picker input is rejected before decoding', () async {
    final oversized = Uint8List(maxUploadImageBytes + 1);
    oversized.setRange(0, 3, <int>[0xff, 0xd8, 0xff]);
    final selected = XFile.fromData(
      oversized,
      name: 'large.jpg',
      path: 'large.jpg',
    );

    await expectLater(
      preparePickedXFileForUpload(selected),
      throwsA(
        isA<SelectedImageException>().having(
          (error) => error.failure,
          'failure',
          SelectedImageFailure.tooLarge,
        ),
      ),
    );
    await expectLater(
      preparePlatformFilesForUpload(<PlatformFile>[
        PlatformFile(
            name: 'large.jpg', size: oversized.length, bytes: oversized),
      ]),
      throwsA(
        isA<SelectedImageException>().having(
          (error) => error.failure,
          'failure',
          SelectedImageFailure.tooLarge,
        ),
      ),
    );
    await expectLater(
      prepareImageForUpload(bytes: oversized, filename: 'large.jpg'),
      throwsA(
        isA<ImagePreparationException>().having(
          (error) => error.failure,
          'failure',
          ImagePreparationFailure.tooLarge,
        ),
      ),
    );
  });

  test('selection failures map to specific user-facing messages', () {
    final strings = AppStrings.forLanguage(AppLanguage.english);

    expect(
      selectedImageErrorMessage(
        strings,
        const SelectedImageException(SelectedImageFailure.unsupportedFormat),
      ),
      'Choose a JPEG or PNG image.',
    );
    expect(
      selectedImageErrorMessage(
        strings,
        const SelectedImageException(SelectedImageFailure.tooLarge),
      ),
      'The image is too large. Choose a smaller photo.',
    );
  });

  test('upload transport, storage and expired-session errors are actionable',
      () {
    final strings = AppStrings.forLanguage(AppLanguage.english);

    expect(
      photoUploadErrorMessage(
        strings,
        const MushukistanApiException(
          kind: ApiFailureKind.network,
          code: 'PHOTO_UPLOAD_TIMEOUT',
          message: 'Transport timed out',
        ),
      ),
      'Photo upload timed out. Check your connection and try again.',
    );
    expect(
      photoUploadErrorMessage(
        strings,
        const MushukistanApiException(
          kind: ApiFailureKind.server,
          code: 'IMAGE_UPLOAD_FAILED',
          message: 'Cloudflare R2 failed',
        ),
      ),
      'Photo upload failed. Try again later.',
    );
    expect(
      photoUploadErrorMessage(
        strings,
        const MushukistanApiException(
          kind: ApiFailureKind.unauthorized,
          code: 'UNAUTHORIZED',
          message: 'Missing Authorization header',
        ),
      ),
      'Sign in again to upload the photo.',
    );
  });
}
