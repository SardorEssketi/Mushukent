import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:mushukistan_frontend/core/media/blob_url_lifecycle.dart';
import 'package:mushukistan_frontend/core/media/heif_normalizer.dart';

void main() {
  test('browser decoder exports a bounded JPEG when the source is decodable',
      () async {
    final source = image.Image(width: 2400, height: 1200);
    final selected = XFile.fromData(
      Uint8List.fromList(image.encodeJpg(source)),
      name: 'source.jpg',
      mimeType: 'image/jpeg',
    );
    try {
      final converted = await normalizeHeifFromPicker(selected.path);
      expect(converted, isNotNull);
      final decoded = image.decodeJpg(converted!);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1920);
      expect(decoded.height, 960);
    } finally {
      releaseBlobUrl(selected.path);
    }
  }, skip: !kIsWeb);
}
