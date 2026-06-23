import 'dart:async';

import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_camera_port.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_config.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_controller.dart';
import 'package:hatchaudit/services/photo/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCameraPort implements TemperatureCameraPort {
  bool ready = true;
  bool error = false;
  String? photo = 'cam.jpg';

  @override
  Future<String?> takePicture() async => photo;
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

TemperatureCaptureController _build({
  TemperatureCaptureConfig? config,
  _FakeCameraPort? cam,
  _FakePhotoService? photo,
}) {
  return TemperatureCaptureController(
    config: config ?? const TemperatureCaptureConfig(title: 'T'),
    photoService: photo ?? _FakePhotoService(),
    cameraPort: cam ?? _FakeCameraPort(),
  );
}

void main() {
  group('TemperatureCaptureController', () {
    test('tap-select moves the active cell', () {
      final c = _build();
      expect(c.activeIndex, 0);
      c.selectKey('back_bottom');
      expect(c.currentKey, 'back_bottom');
      expect(c.activeIndex, EstGridData.scanKeys.indexOf('back_bottom'));
    });

    test('initial key opens that exact cell for editing', () {
      final c = _build(
        config: const TemperatureCaptureConfig(
          title: 'T',
          initialKey: 'front_middle',
          initialReadings: {'front_middle': 20.0},
          initialPhotos: {'front_middle': 'front-middle.jpg'},
        ),
      );

      expect(c.currentKey, 'front_middle');
      expect(c.manualEntryActive, isTrue);
      expect(c.pendingPhotoPath, 'front-middle.jpg');
    });

    test('capture stages a saved photo and opens manual entry', () async {
      final c = _build();

      await c.captureOnce();

      expect(c.pendingValue, isNull);
      expect(c.manualEntryActive, isTrue);
      expect(c.capture.capturedImagePath, 'saved_cam.jpg');
      expect(c.readings, isEmpty);
    });

    test('manual save with staged photo saves and advances', () async {
      final c = _build();
      await c.captureOnce();
      await c.commitManualEntry(37.5);

      expect(c.readings['front_top'], 37.5);
      expect(c.photos['front_top'], 'saved_cam.jpg');
      expect(c.activeIndex, 1, reason: 'saving advances to next open cell');
    });

    test('confirm stays put when no open cell remains', () async {
      final initial = {for (final k in EstGridData.scanKeys.skip(1)) k: 50.0};
      final c = _build(
        config: TemperatureCaptureConfig(title: 'T', initialReadings: initial),
      );
      expect(c.activeIndex, 0);
      await c.captureOnce();
      await c.commitManualEntry(37.5);
      expect(c.readings['front_top'], 37.5);
      expect(c.allCellsFilled, isTrue);
      expect(
        c.activeIndex,
        0,
        reason: 'no open cell -> stay on confirmed cell',
      );
    });

    test('manual entry without photo saves a value and advances', () async {
      final c = _build();
      c.selectCell(2);
      c.beginManualEntry();
      expect(c.manualEntryActive, isTrue);
      await c.commitManualEntry(40.0);
      expect(c.readings['front_bottom'], 40.0);
      expect(c.photos.containsKey('front_bottom'), isFalse);
      expect(c.activeIndex, 3);
    });

    test('result() returns only cells changed this session', () async {
      final c = _build(
        config: const TemperatureCaptureConfig(
          title: 'T',
          initialReadings: {'front_top': 20.0},
          initialPhotos: {'front_top': 'old.jpg'},
        ),
      );
      expect(c.activeIndex, 1, reason: 'front_top already filled -> next open');
      await c.captureOnce();
      await c.commitManualEntry(37.5);

      final r = c.result();
      expect(r.readings.containsKey('front_top'), isFalse);
      expect(r.readings['front_middle'], 37.5);
      expect(r.readings.length, 1);
    });

    test('a late camera result after dispose is a no-op', () async {
      final gate = Completer<String?>();
      final cam = _DelayedCameraPort(gate.future);
      final c = _build(cam: cam);
      final pending = c.captureOnce();
      c.dispose();
      gate.complete('cam.jpg');
      await pending;
      expect(c.readings.isEmpty, isTrue);
    });
  });
}

class _DelayedCameraPort extends _FakeCameraPort {
  _DelayedCameraPort(this.future);

  final Future<String?> future;

  @override
  Future<String?> takePicture() => future;
}
