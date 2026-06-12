import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_camera_port.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_config.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_controller.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_result.dart';
import 'package:hatchaudit/features/audits/ocr_capture/ocr_capture_screen.dart';
import 'package:hatchaudit/services/ocr/ocr_service.dart'
    show ThermoScanCropFrame;
import 'package:hatchaudit/services/photo/photo_service.dart';

class _FakeCameraPort implements OcrCameraPort {
  @override
  Future<String?> takePicture() async => 'cam.jpg';
  @override
  Future<String?> takePictureForAutoScan() async => 'cam.jpg';
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
  @override
  Future<String?> pickPhoto({bool fromCamera = true}) async => 'native.jpg';
}

OcrCaptureController _controller({OcrCaptureConfig? config}) {
  return OcrCaptureController(
    config: config ?? const OcrCaptureConfig(title: 'EST'),
    recognizeCelsius: (_, _) async => 37.5,
    photoService: _FakePhotoService(),
    cameraPort: _FakeCameraPort(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  OcrCaptureController controller, {
  void Function(OcrCaptureResult?)? onResult,
  Size surfaceSize = const Size(1080, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await Navigator.of(context).push<OcrCaptureResult>(
                  MaterialPageRoute(
                    builder: (_) => OcrCaptureScreen(
                      config: controller.config,
                      controller: controller,
                      cameraBuilder: (_) =>
                          const ColoredBox(color: Colors.black),
                    ),
                  ),
                );
                onResult?.call(r);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the 9-point grid and initial header', (tester) async {
    await _pump(tester, _controller());
    for (final key in const ['front_top', 'middle_middle', 'back_bottom']) {
      expect(find.byKey(ValueKey('est-grid-cell-$key')), findsOneWidget);
    }
    expect(find.text('Front - Top'), findsOneWidget);
    expect(find.text('Step 1 of 9'), findsOneWidget);
  });

  testWidgets('tapping a cell selects it', (tester) async {
    await _pump(tester, _controller());
    await tester.tap(
      find.byKey(const ValueKey('est-grid-cell-back_middle')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('Back - Middle'), findsOneWidget);
    expect(find.text('Step 8 of 9'), findsOneWidget);
  });

  testWidgets('Enter manually switches to the manual entry card', (
    tester,
  ) async {
    await _pump(tester, _controller());
    expect(find.text('Scanning for temperature…'), findsOneWidget);
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(find.text('Enter reading manually'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('Previous/Next move between cells', (tester) async {
    await _pump(tester, _controller());
    await tester.tap(find.widgetWithText(OutlinedButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 9'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 9'), findsOneWidget);
  });

  testWidgets('Done pops the dirty-only result', (tester) async {
    final controller = _controller();
    controller.beginManualEntry();
    await controller.commitManualEntry(37.5);

    OcrCaptureResult? popped;
    await _pump(tester, controller, onResult: (r) => popped = r);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.readings['front_top'], 37.5);
  });

  testWidgets('manual entry layout avoids phone overflow at large text scale', (
    tester,
  ) async {
    await _pump(
      tester,
      _controller(),
      surfaceSize: const Size(360, 844),
      textScale: 1.5,
    );

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter reading manually'), findsOneWidget);
  });
}
