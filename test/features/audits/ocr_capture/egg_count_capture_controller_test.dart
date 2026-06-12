import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/ocr_capture/egg_count_capture_controller.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_camera_port.dart';
import 'package:hatchaudit/services/ocr/egg_count_ocr_service.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart'
    show ThermoScanCropFrame;
import 'package:hatchaudit/services/photo/photo_service.dart';

class _FakeCameraPort implements OcrCameraPort {
  final List<String?> photos;
  int _index = 0;

  _FakeCameraPort(this.photos);

  @override
  Future<String?> takePicture() async => photos[_index++];
  @override
  Future<String?> takePictureForAutoScan() async => takePicture();
  @override
  ThermoScanCropFrame? get ocrCropFrame => null;
  @override
  bool get isCameraReady => true;
  @override
  bool get hasCameraError => false;
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

void main() {
  group('EggCountCaptureController', () {
    test('confirms multiple photos and sums their counts', () async {
      final controller = EggCountCaptureController(
        title: 'Infertile',
        analyzeEggCount: (path) async => EggCountOcrResult(
          count: path.endsWith('a.jpg') ? 12 : 8,
          confidence: EggCountOcrConfidence.high,
        ),
        photoService: _FakePhotoService(),
        cameraPort: _FakeCameraPort(['a.jpg', 'b.jpg']),
      );
      addTearDown(controller.dispose);

      await controller.captureOnce();
      expect(controller.pendingCount, 12);
      await controller.confirmPending();

      await controller.captureOnce();
      expect(controller.pendingCount, 8);
      await controller.confirmPending();

      expect(controller.totalCount, 20);
      expect(controller.photos, ['saved_a.jpg', 'saved_b.jpg']);
      expect(controller.result().count, 20);
      expect(controller.result().photos, ['saved_a.jpg', 'saved_b.jpg']);
    });

    test('manual entry can correct the pending photo count', () async {
      final controller = EggCountCaptureController(
        title: 'Early Dead',
        analyzeEggCount: (_) async => const EggCountOcrResult(
          count: 9,
          confidence: EggCountOcrConfidence.medium,
        ),
        photoService: _FakePhotoService(),
        cameraPort: _FakeCameraPort(['photo.jpg']),
      );
      addTearDown(controller.dispose);

      await controller.captureOnce();
      controller.rejectToManual();
      await controller.commitManualCount(11);

      expect(controller.totalCount, 11);
      expect(controller.photos, ['saved_photo.jpg']);
      expect(controller.pendingCount, isNull);
    });
  });
}
