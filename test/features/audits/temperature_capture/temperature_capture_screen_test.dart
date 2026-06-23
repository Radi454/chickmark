import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_camera_port.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_config.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_controller.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_result.dart';
import 'package:hatchaudit/features/audits/temperature_capture/temperature_capture_screen.dart';
import 'package:hatchaudit/services/photo/photo_service.dart';

class _FakeCameraPort implements TemperatureCameraPort {
  @override
  Future<String?> takePicture() async => 'cam.jpg';
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

TemperatureCaptureController _controller({TemperatureCaptureConfig? config}) {
  return TemperatureCaptureController(
    config: config ?? const TemperatureCaptureConfig(title: 'EST'),
    photoService: _FakePhotoService(),
    cameraPort: _FakeCameraPort(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  TemperatureCaptureController controller, {
  void Function(TemperatureCaptureResult?)? onResult,
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
                final r = await Navigator.of(context)
                    .push<TemperatureCaptureResult>(
                      MaterialPageRoute(
                        builder: (_) => TemperatureCaptureScreen(
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

  testWidgets('ready card only offers the inline photo action', (tester) async {
    await _pump(tester, _controller());
    expect(find.text('Take a photo, then enter the reading.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Take photo'), findsOneWidget);
    expect(find.text('Camera app'), findsNothing);
    expect(find.text('Manual without photo'), findsNothing);
  });

  testWidgets('footer keeps serial capture controls to Done only', (
    tester,
  ) async {
    await _pump(tester, _controller());

    expect(find.widgetWithText(OutlinedButton, 'Previous'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Next'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
  });

  testWidgets('Capture opens manual entry with the staged photo', (
    tester,
  ) async {
    await _pump(tester, _controller());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Take photo'));
    await tester.pumpAndSettle();

    expect(find.text('Enter reading manually'), findsOneWidget);
    expect(find.text('Photo captured for this point.'), findsOneWidget);
  });

  testWidgets(
    'opening a saved initial cell shows its attached photo for edit',
    (tester) async {
      final controller = _controller(
        config: const TemperatureCaptureConfig(
          title: 'EST',
          initialKey: 'front_middle',
          initialReadings: {'front_middle': 20.0},
          initialPhotos: {'front_middle': 'front-middle.jpg'},
        ),
      );

      await _pump(tester, controller);

      expect(find.text('Front - Middle'), findsOneWidget);
      expect(find.text('Enter reading manually'), findsOneWidget);
      expect(find.text('Photo captured for this point.'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets('Done pops the dirty-only result', (tester) async {
    final controller = _controller();
    controller.beginManualEntry();
    await controller.commitManualEntry(37.5);

    TemperatureCaptureResult? popped;
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Take photo'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter reading manually'), findsOneWidget);
  });
}
