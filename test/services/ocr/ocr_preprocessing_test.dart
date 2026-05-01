import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

void main() {
  test(
    'ThermoScan OCR preprocessing crops, normalizes, and grayscales image',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('ocr_preprocess_');
      addTearDown(() => tempDir.delete(recursive: true));

      final sourcePath = path.join(tempDir.path, 'source.jpg');
      final outputPath = path.join(tempDir.path, 'processed.jpg');

      final source = img.Image(width: 420, height: 240);
      for (final pixel in source) {
        final isCenter =
            pixel.x > 120 && pixel.x < 300 && pixel.y > 70 && pixel.y < 170;
        pixel
          ..r = isCenter ? 40 : 220
          ..g = isCenter ? 190 : 40
          ..b = isCenter ? 70 : 160
          ..a = 255;
      }
      await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

      final processed = await OcrService.preprocessThermoScanImageForOcr(
        sourcePath: sourcePath,
        outputPath: outputPath,
      );

      expect(processed, isTrue);
      final decoded = img.decodeImage(await File(outputPath).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThan(source.width));
      expect(decoded.height, lessThan(source.height));
      expect(
        decoded.width / decoded.height,
        closeTo(kThermoScanFrameWidth / kThermoScanFrameHeight, 0.15),
      );

      final centerPixel = decoded.getPixel(
        decoded.width ~/ 2,
        decoded.height ~/ 2,
      );
      expect(centerPixel.r, centerPixel.g);
      expect(centerPixel.g, centerPixel.b);
    },
  );

  test('quality checks can be disabled without blocking OCR prep', () async {
    final tempDir = await Directory.systemTemp.createTemp('ocr_preprocess_');
    addTearDown(() => tempDir.delete(recursive: true));

    final sourcePath = path.join(tempDir.path, 'source.jpg');
    final outputPath = path.join(tempDir.path, 'processed.jpg');

    final source = img.Image(width: 360, height: 240);
    for (final pixel in source) {
      pixel
        ..r = 128
        ..g = 128
        ..b = 128
        ..a = 255;
    }
    await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

    final result = await OcrService.prepareThermoScanImageForOcr(
      sourcePath: sourcePath,
      outputPath: outputPath,
      enableQualityChecks: false,
    );

    expect(result.shouldRunOcr, isTrue);
    expect(result.hint, isNull);
    expect(await File(outputPath).exists(), isTrue);
  });

  test('blurry cropped frame is rejected before OCR with blur hint', () async {
    final tempDir = await Directory.systemTemp.createTemp('ocr_preprocess_');
    addTearDown(() => tempDir.delete(recursive: true));

    final sourcePath = path.join(tempDir.path, 'source.jpg');
    final outputPath = path.join(tempDir.path, 'processed.jpg');

    final source = img.Image(width: 360, height: 240);
    for (final pixel in source) {
      pixel
        ..r = 132
        ..g = 132
        ..b = 132
        ..a = 255;
    }
    await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

    final result = await OcrService.prepareThermoScanImageForOcr(
      sourcePath: sourcePath,
      outputPath: outputPath,
    );

    expect(result.shouldRunOcr, isFalse);
    expect(result.rejectionReason, ThermoScanQualityRejection.blur);
    expect(result.hint, 'Move slightly back');
  });

  test('extreme lighting is rejected before OCR with glare hint', () async {
    final tempDir = await Directory.systemTemp.createTemp('ocr_preprocess_');
    addTearDown(() => tempDir.delete(recursive: true));

    final sourcePath = path.join(tempDir.path, 'source.jpg');
    final outputPath = path.join(tempDir.path, 'processed.jpg');

    final source = img.Image(width: 360, height: 240);
    for (final pixel in source) {
      final stripe = pixel.x.isEven;
      pixel
        ..r = stripe ? 255 : 220
        ..g = stripe ? 255 : 220
        ..b = stripe ? 255 : 220
        ..a = 255;
    }
    await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

    final result = await OcrService.prepareThermoScanImageForOcr(
      sourcePath: sourcePath,
      outputPath: outputPath,
    );

    expect(result.shouldRunOcr, isFalse);
    expect(result.rejectionReason, ThermoScanQualityRejection.lighting);
    expect(result.hint, 'Reduce glare');
  });

  test('small digit-like marks are rejected with distance hint', () async {
    final tempDir = await Directory.systemTemp.createTemp('ocr_preprocess_');
    addTearDown(() => tempDir.delete(recursive: true));

    final sourcePath = path.join(tempDir.path, 'source.jpg');
    final outputPath = path.join(tempDir.path, 'processed.jpg');

    final source = img.Image(width: 360, height: 240);
    for (final pixel in source) {
      final inTinyMark =
          pixel.x >= 178 && pixel.x <= 184 && pixel.y >= 118 && pixel.y <= 124;
      pixel
        ..r = inTinyMark ? 10 : 140
        ..g = inTinyMark ? 10 : 140
        ..b = inTinyMark ? 10 : 140
        ..a = 255;
    }
    await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

    final result = await OcrService.prepareThermoScanImageForOcr(
      sourcePath: sourcePath,
      outputPath: outputPath,
    );

    expect(result.shouldRunOcr, isFalse);
    expect(result.rejectionReason, ThermoScanQualityRejection.distance);
    expect(result.hint, 'Move closer');
  });

  test('borderline quality continues to OCR', () async {
    final tempDir = await Directory.systemTemp.createTemp('ocr_preprocess_');
    addTearDown(() => tempDir.delete(recursive: true));

    final sourcePath = path.join(tempDir.path, 'source.jpg');
    final outputPath = path.join(tempDir.path, 'processed.jpg');

    final source = img.Image(width: 360, height: 240);
    for (final pixel in source) {
      final inDisplay =
          pixel.x >= 130 && pixel.x <= 230 && pixel.y >= 90 && pixel.y <= 150;
      final inSegment =
          inDisplay &&
          ((pixel.x % 20 < 10 && pixel.y % 28 < 5) ||
              (pixel.x % 20 < 4 && pixel.y % 28 < 18));
      pixel
        ..r = inSegment ? 45 : 145
        ..g = inSegment ? 45 : 145
        ..b = inSegment ? 45 : 145
        ..a = 255;
    }
    await File(sourcePath).writeAsBytes(img.encodeJpg(source, quality: 95));

    final result = await OcrService.prepareThermoScanImageForOcr(
      sourcePath: sourcePath,
      outputPath: outputPath,
    );

    expect(result.shouldRunOcr, isTrue);
    expect(result.hint, isNull);
  });
}
