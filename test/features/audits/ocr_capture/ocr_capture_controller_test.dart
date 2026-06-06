import 'dart:async';

import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_camera_port.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_config.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_controller.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart' show ThermoScanCropFrame;
import 'package:hatchaudit/services/photo/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCameraPort implements OcrCameraPort {
  bool ready = true;
  bool error = false;
  String? photo = 'cam.jpg';

  @override
  Future<String?> takePicture() async => photo;
  @override
  Future<String?> takePictureForAutoScan() async => photo;
  @override
  ThermoScanCropFrame? get ocrCropFrame => null;
  @override
  bool get isCameraReady => ready;
  @override
  bool get hasCameraError => error;
  @override
  Future<void> closeCameraForStationExit() async {}
  @override
  Future<void> pauseCameraForIdle() async {}
}

class _FakePhotoService extends PhotoService {
  final List<String> deleted = [];

  @override
  Future<String?> saveCapturedPhotoPath(String sourcePath) async =>
      'saved_$sourcePath';
  @override
  Future<void> deletePhoto(String filePath) async => deleted.add(filePath);
  @override
  Future<String?> pickPhoto({bool fromCamera = true}) async => 'native.jpg';
}

OcrCaptureController _build({
  OcrCaptureConfig? config,
  CelsiusRecognizer? recognizer,
  _FakeCameraPort? cam,
  _FakePhotoService? photo,
}) {
  return OcrCaptureController(
    config: config ?? const OcrCaptureConfig(title: 'T'),
    recognizeCelsius: recognizer ?? (_, _) async => 37.5,
    photoService: photo ?? _FakePhotoService(),
    cameraPort: cam ?? _FakeCameraPort(),
  );
}

void main() {
  group('OcrCaptureController', () {
    test('tap-select moves the active cell', () {
      final c = _build();
      expect(c.activeIndex, 0);
      c.selectKey('back_bottom');
      expect(c.currentKey, 'back_bottom');
      expect(c.activeIndex, EstGridData.scanKeys.indexOf('back_bottom'));
    });

    test('previous/next clamp at the ends', () {
      final c = _build();
      c.previous();
      expect(c.activeIndex, 0);
      c.next();
      expect(c.activeIndex, 1);
      c.selectCell(EstGridData.scanKeys.length - 1);
      c.next();
      expect(c.activeIndex, EstGridData.scanKeys.length - 1);
    });

    test('capture then confirm saves the cell and auto-advances', () async {
      final c = _build(recognizer: (_, _) async => 37.5);
      await c.captureOnce();
      expect(c.pendingValue, 37.5);
      expect(c.capture.capturedImagePath, 'saved_cam.jpg');

      await c.confirm();
      expect(c.readings['front_top'], 37.5);
      expect(c.photos['front_top'], 'saved_cam.jpg');
      expect(c.activeIndex, 1, reason: 'confirm advances to next open cell');
    });

    test('confirm stays put when no open cell remains', () async {
      final initial = {
        for (final k in EstGridData.scanKeys.skip(1)) k: 50.0,
      };
      final c = _build(
        config: OcrCaptureConfig(title: 'T', initialReadings: initial),
        recognizer: (_, _) async => 37.5,
      );
      expect(c.activeIndex, 0);
      await c.captureOnce();
      await c.confirm();
      expect(c.readings['front_top'], 37.5);
      expect(c.allCellsFilled, isTrue);
      expect(c.activeIndex, 0, reason: 'no open cell -> stay on confirmed cell');
    });

    test('reject to manual keeps the photo and commits the typed value',
        () async {
      final c = _build(recognizer: (_, _) async => 37.5);
      await c.captureOnce();

      c.rejectToManual();
      expect(c.manualEntryActive, isTrue);
      expect(c.pendingValue, isNull, reason: 'scanned value cleared');
      expect(c.capture.capturedImagePath, 'saved_cam.jpg',
          reason: 'frame retained as pending evidence');

      await c.commitManualEntry(36.0);
      expect(c.readings['front_top'], 36.0);
      expect(c.photos['front_top'], 'saved_cam.jpg',
          reason: 'single-capture frame already saved -> reused, not re-saved');
      expect(c.manualEntryActive, isFalse);
      expect(c.activeIndex, 0, reason: 'manual entry does not auto-advance');
    });

    test('pure manual entry saves a value with no photo and stays', () async {
      final c = _build();
      c.selectCell(2);
      c.beginManualEntry();
      expect(c.manualEntryActive, isTrue);
      await c.commitManualEntry(40.0);
      expect(c.readings['front_bottom'], 40.0);
      expect(c.photos.containsKey('front_bottom'), isFalse);
      expect(c.activeIndex, 2);
    });

    test('converts Celsius OCR to Fahrenheit when configured', () async {
      final c = _build(
        config: const OcrCaptureConfig(
          title: 'T',
          unitSuffix: '°F',
          convertCelsiusToFahrenheit: true,
        ),
        recognizer: (_, _) async => 37.0,
      );
      await c.captureOnce();
      expect(c.pendingValue, closeTo(98.6, 0.01));
      await c.confirm();
      expect(c.readings['front_top'], closeTo(98.6, 0.01));
      expect(c.result().readings['front_top'], closeTo(98.6, 0.01));
    });

    test('result() returns only cells changed this session', () async {
      final c = _build(
        config: const OcrCaptureConfig(
          title: 'T',
          initialReadings: {'front_top': 20.0},
          initialPhotos: {'front_top': 'old.jpg'},
        ),
        recognizer: (_, _) async => 37.5,
      );
      expect(c.activeIndex, 1, reason: 'front_top already filled -> next open');
      await c.captureOnce();
      await c.confirm();

      final r = c.result();
      expect(r.readings.containsKey('front_top'), isFalse);
      expect(r.readings['front_middle'], 37.5);
      expect(r.readings.length, 1);
    });

    test('a late OCR result after dispose is a no-op', () async {
      final gate = Completer<double?>();
      final c = _build(recognizer: (_, _) => gate.future);
      final pending = c.captureOnce();
      c.dispose();
      gate.complete(37.5);
      await pending;
      expect(c.readings.isEmpty, isTrue);
    });
  });
}
