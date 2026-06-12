import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:hatchaudit/services/photo/photo_compression.dart';

Uint8List _jpegOf(int width, int height, {int quality = 100}) {
  final src = img.Image(width: width, height: height);
  // Some texture so the encoder produces a non-trivial payload.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      src.setPixelRgb(x, y, (x * 7) % 256, (y * 11) % 256, (x + y) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(src, quality: quality));
}

void main() {
  group('resizeJpeg', () {
    test('caps the long edge of a landscape image, preserving aspect', () {
      final bytes = _jpegOf(4000, 3000);

      final out = resizeJpeg(JpegResizeJob(bytes, maxEdge: 2000, quality: 90));

      expect(out, isNotNull);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 2000);
      expect(decoded.height, 1500);
      expect(out.length, lessThan(bytes.length));
    });

    test('caps the long edge of a portrait image on height', () {
      final bytes = _jpegOf(3000, 4000);

      final out = resizeJpeg(JpegResizeJob(bytes, maxEdge: 2000));
      final decoded = img.decodeImage(out!)!;

      expect(decoded.height, 2000);
      expect(decoded.width, 1500);
    });

    test('never upscales an image smaller than maxEdge', () {
      final bytes = _jpegOf(800, 600);

      final out = resizeJpeg(JpegResizeJob(bytes, maxEdge: 2000));
      final decoded = img.decodeImage(out!)!;

      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('returns null for undecodable bytes', () {
      final out = resizeJpeg(
        JpegResizeJob(Uint8List.fromList([0, 1, 2, 3, 4])),
      );
      expect(out, isNull);
    });
  });
}
