import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/ocr/egg_count_ocr_service.dart';
import 'package:image/image.dart' as image;

void main() {
  group('EggCountOcrService', () {
    test('counts separated eggs in a tray-like image', () async {
      final tempDir = await Directory.systemTemp.createTemp('egg_count_ocr_');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/tray.jpg');

      final canvas = image.Image(width: 420, height: 260);
      image.fill(canvas, color: image.ColorRgb8(178, 178, 168));
      for (final center in const [
        (x: 105, y: 130),
        (x: 210, y: 130),
        (x: 315, y: 130),
      ]) {
        image.fillCircle(
          canvas,
          x: center.x,
          y: center.y,
          radius: 38,
          color: image.ColorRgb8(232, 211, 145),
        );
        image.fillCircle(
          canvas,
          x: center.x + 4,
          y: center.y - 3,
          radius: 23,
          color: image.ColorRgb8(219, 143, 35),
        );
      }
      await file.writeAsBytes(image.encodeJpg(canvas, quality: 95));

      final result = await EggCountOcrService().analyzeEggCount(file.path);

      expect(result.count, 3);
      expect(result.confidence, EggCountOcrConfidence.high);
    });
  });
}
