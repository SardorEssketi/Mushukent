import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'blob_url_lifecycle.dart';
import 'image_upload_preprocessor.dart';

// Browser decoding is available on some platforms (including Safari), but is
// not guaranteed. Return null when the browser cannot decode this HEIF image.
Future<Uint8List?> normalizeHeifFromPicker(String path) async {
  if (!path.startsWith('blob:')) {
    return null;
  }

  final image = web.HTMLImageElement();
  final loaded = Completer<bool>();
  final loadSubscription = image.onLoad.listen((_) {
    if (!loaded.isCompleted) loaded.complete(true);
  });
  final errorSubscription = image.onError.listen((_) {
    if (!loaded.isCompleted) loaded.complete(false);
  });

  try {
    image.src = path;
    if (!await loaded.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    )) {
      return null;
    }
    final width = image.naturalWidth;
    final height = image.naturalHeight;
    if (width <= 0 || height <= 0) {
      return null;
    }
    if (width * height > maxSourceImagePixels) {
      throw const ImagePreparationException(ImagePreparationFailure.tooLarge);
    }
    final scale = (width > height ? width : height) > uploadImageLongestSide
        ? uploadImageLongestSide / (width > height ? width : height)
        : 1.0;
    final canvas = web.HTMLCanvasElement()
      ..width = (width * scale).round()
      ..height = (height * scale).round();
    canvas.context2D.drawImage(
      image,
      0,
      0,
      canvas.width.toDouble(),
      canvas.height.toDouble(),
    );

    final encoded = Completer<Uint8List?>();
    Future<void> readBlob(web.Blob blob) async {
      final url = web.URL.createObjectURL(blob);
      try {
        final bytes = await XFile(url).readAsBytes();
        if (!encoded.isCompleted) encoded.complete(bytes);
      } catch (_) {
        if (!encoded.isCompleted) encoded.complete(null);
      } finally {
        releaseBlobUrl(url);
      }
    }

    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null) {
          if (!encoded.isCompleted) encoded.complete(null);
          return;
        }
        unawaited(readBlob(blob));
      }).toJS,
      'image/jpeg',
      0.88.toJS,
    );
    return await encoded.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => null,
    );
  } on ImagePreparationException {
    rethrow;
  } catch (_) {
    return null;
  } finally {
    await loadSubscription.cancel();
    await errorSubscription.cancel();
    image.src = '';
  }
}
