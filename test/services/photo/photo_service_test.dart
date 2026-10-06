import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/photo/photo_data_uri.dart';
import 'package:hatchaudit/services/photo/photo_service.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'browser byte capture is compressed into durable JPEG data URI',
    () async {
      final source = img.Image(width: 32, height: 24);
      source.setPixelRgb(3, 4, 120, 40, 210);
      final jpeg = Uint8List.fromList(img.encodeJpg(source, quality: 100));

      final saved = await PhotoService(
        useBrowserStorage: true,
      ).saveCapturedPhotoBytes(jpeg);

      final storedBytes = parseDurablePhotoDataUri(saved);
      expect(storedBytes, isNotNull);
      expect(img.decodeJpg(storedBytes!), isNotNull);
    },
  );

  test('already durable capture paths remain unchanged', () async {
    final saved = encodePhotoDataUri(
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
    );
    expect(
      await PhotoService(useBrowserStorage: true).saveCapturedPhotoPath(saved),
      saved,
    );
  });
}
