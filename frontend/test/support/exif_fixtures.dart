import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// A camera-style JPEG whose pixels are stored landscape (60x30: left half
/// red, right half blue) with an EXIF Orientation tag, as phones write it.
///
/// Displayed correctly, the photo looks like:
/// - 1: landscape, red left, blue right
/// - 3: rotated 180 degrees: blue left, red right
/// - 6: rotated 90 degrees clockwise: portrait, red top, blue bottom
/// - 8: rotated 90 degrees counter-clockwise: portrait, blue top, red bottom
Uint8List exifOrientedJpeg(int orientation) {
  final pixels = image.Image(width: 60, height: 30);
  for (var y = 0; y < pixels.height; y++) {
    for (var x = 0; x < pixels.width; x++) {
      final red = x < pixels.width / 2;
      pixels.setPixelRgb(x, y, red ? 255 : 0, 0, red ? 0 : 255);
    }
  }
  pixels.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(image.encodeJpg(pixels, quality: 95));
}

/// Whether [pixel] is clearly red (true) or clearly blue (false).
bool isRed(image.Pixel pixel) => pixel.r > 150 && pixel.b < 100;
bool isBlue(image.Pixel pixel) => pixel.b > 150 && pixel.r < 100;
