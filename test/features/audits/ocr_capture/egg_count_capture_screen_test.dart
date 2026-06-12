import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/ocr_capture/egg_count_capture_controller.dart';
import 'package:hatchaudit/features/audits/ocr_capture/egg_count_capture_result.dart';
import 'package:hatchaudit/features/audits/ocr_capture/egg_count_capture_screen.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_camera_port.dart';
import 'package:hatchaudit/services/ocr/egg_count_ocr_service.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart'
    show ThermoScanCropFrame;
import 'package:hatchaudit/services/photo/photo_service.dart';

class _FakeCameraPort implements OcrCameraPort {
  @override
  Future<String?> takePicture() async => 'photo.jpg';
  @override
  Future<String?> takePictureForAutoScan() async => 'photo.jpg';
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
  @override
  Future<String?> saveCapturedPhotoPath(String sourcePath) async =>
      'saved_$sourcePath';
  @override
  Future<void> deletePhoto(String filePath) async {}
}

void main() {
  testWidgets('returns confirmed egg count and photo evidence', (tester) async {
    final controller = EggCountCaptureController(
      title: 'Infertile',
      analyzeEggCount: (_) async => const EggCountOcrResult(
        count: 14,
        confidence: EggCountOcrConfidence.high,
      ),
      photoService: _FakePhotoService(),
      cameraPort: _FakeCameraPort(),
    );
    addTearDown(controller.dispose);

    EggCountCaptureResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await Navigator.of(context)
                      .push<EggCountCaptureResult>(
                        MaterialPageRoute(
                          builder: (_) => EggCountCaptureScreen(
                            controller: controller,
                            cameraBuilder: (_) =>
                                const ColoredBox(color: Colors.black),
                          ),
                        ),
                      );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Capture'));
    await tester.pumpAndSettle();
    expect(find.text('14 eggs'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.count, 14);
    expect(popped!.photos, ['saved_photo.jpg']);
  });
}
