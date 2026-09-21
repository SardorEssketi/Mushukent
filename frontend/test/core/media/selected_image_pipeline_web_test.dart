@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:mushukistan_frontend/core/media/selected_image_pipeline.dart';
import 'package:web/web.dart' as web;

void main() {
  test('materializes a browser Blob before releasing its URL', () async {
    final bytes = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 320, height: 320)),
    );
    final blob = web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    final url = web.URL.createObjectURL(blob);
    final file = XFile(
      url,
      name: 'browser-cat.jpg',
      mimeType: 'image/jpeg',
      length: bytes.length,
    );

    final prepared = await preparePickedXFileForUpload(file);

    expect(prepared.bytes, isNotEmpty);
    expect(prepared.filename, 'browser-cat.jpg');
    await expectLater(
      XFile(url, name: 'revoked.jpg').readAsBytes(),
      throwsA(isA<Exception>()),
    );
  });
}
