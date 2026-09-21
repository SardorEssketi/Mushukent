import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:mushukistan_frontend/core/media/selected_image_pipeline.dart';

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
}
