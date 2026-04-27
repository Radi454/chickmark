import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/models/est_guided_capture_state.dart';
import 'package:hatchaudit/features/audits/widgets/est_grid_widget.dart';
import 'package:hatchaudit/features/audits/widgets/est_guided_capture_panel.dart';

void main() {
  testWidgets(
    'inline capture panel can appear while EST matrix stays visible',
    (tester) async {
      final valueController = TextEditingController();
      final controllers = {
        for (final key in EstGridData.scanKeys) key: TextEditingController(),
      };
      final focusNodes = {
        for (final key in EstGridData.scanKeys) key: FocusNode(),
      };

      addTearDown(() {
        valueController.dispose();
        for (final controller in controllers.values) {
          controller.dispose();
        }
        for (final focusNode in focusNodes.values) {
          focusNode.dispose();
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  EstGuidedCapturePanel(
                    state: EstGuidedCaptureState.initial(),
                    valueController: valueController,
                    preview: const Text('inline camera placeholder'),
                    onCapture: () {},
                    onUseNativeCamera: () {},
                    onAutoScan: () {},
                    onStopAutoScan: () {},
                    onRetake: () {},
                    onSkip: () {},
                    onFinish: () {},
                    onValueChanged: (_) {},
                    onConfirm: () {},
                    onRejectAutoScanReading: () {},
                  ),
                  EstGridWidget(
                    controllers: controllers,
                    focusNodes: focusNodes,
                    photos: const {},
                    enabled: true,
                    onValueChanged: (_, _) {},
                    onPhotoCaptured: (_, _) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('inline camera placeholder'), findsOneWidget);
      expect(find.text('Front'), findsOneWidget);
      expect(find.text('Bottom'), findsOneWidget);
    },
  );

  testWidgets('confirm is disabled until a captured valid value exists', (
    tester,
  ) async {
    final valueController = TextEditingController();
    var confirmed = false;

    addTearDown(valueController.dispose);

    Future<void> pump(EstGuidedCaptureState state) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EstGuidedCapturePanel(
              state: state,
              valueController: valueController,
              preview: const SizedBox(),
              onCapture: () {},
              onUseNativeCamera: () {},
              onAutoScan: () {},
              onStopAutoScan: () {},
              onRetake: () {},
              onSkip: () {},
              onFinish: () {},
              onValueChanged: (_) {},
              onConfirm: () => confirmed = true,
              onRejectAutoScanReading: () {},
            ),
          ),
        ),
      );
    }

    await pump(EstGuidedCaptureState.initial());
    expect(find.widgetWithText(FilledButton, 'Right'), findsNothing);

    valueController.text = '23.4';
    await pump(
      EstGuidedCaptureState.initial().captureResolved(
        photoPath: '/tmp/front_top.jpg',
        ocrValue: 23.4,
      ),
    );
    await tester.pump(const Duration(milliseconds: 220));
    final right = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Right'),
    );
    expect(right.onPressed, isNotNull);
    expect(find.text('23.4'), findsWidgets);
    expect(find.text('Confirm reading'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Right'));
    await tester.tap(find.widgetWithText(FilledButton, 'Right'));
    expect(confirmed, isTrue);
  });

  testWidgets('native camera fallback remains when inline camera failed', (
    tester,
  ) async {
    final valueController = TextEditingController();
    var openedCameraApp = false;

    addTearDown(valueController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGuidedCapturePanel(
            state: EstGuidedCaptureState.initial().captureFailed(
              'Inline camera is unavailable. Capture will open the camera app.',
            ),
            valueController: valueController,
            preview: const SizedBox(),
            useCameraAppForCapture: true,
            onCapture: () {},
            onUseNativeCamera: () => openedCameraApp = true,
            onAutoScan: () {},
            onStopAutoScan: () {},
            onRetake: () {},
            onSkip: () {},
            onFinish: () {},
            onValueChanged: (_) {},
            onConfirm: () {},
            onRejectAutoScanReading: () {},
          ),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Camera app'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Camera app'));
    expect(openedCameraApp, isTrue);
  });

  testWidgets('scanning state shows capture options without review actions', (
    tester,
  ) async {
    final valueController = TextEditingController();
    var autoScanStarted = false;
    var captured = false;

    addTearDown(valueController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGuidedCapturePanel(
            state: EstGuidedCaptureState.initial(),
            valueController: valueController,
            preview: const SizedBox(),
            onCapture: () => captured = true,
            onUseNativeCamera: () {},
            onAutoScan: () => autoScanStarted = true,
            onStopAutoScan: () {},
            onRetake: () {},
            onSkip: () {},
            onFinish: () {},
            onValueChanged: (_) {},
            onConfirm: () {},
            onRejectAutoScanReading: () {},
          ),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Camera app'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Right'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Wrong'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Retake'), findsNothing);
    expect(find.text('Scanning for temperature...'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Auto scan'));
    expect(autoScanStarted, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Capture'));
    expect(captured, isTrue);
  });

  testWidgets('scanning status is visible while auto scan is running', (
    tester,
  ) async {
    final valueController = TextEditingController();
    var stopped = false;

    addTearDown(valueController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGuidedCapturePanel(
            state: EstGuidedCaptureState.initial().startAutoScan(),
            valueController: valueController,
            preview: const SizedBox(),
            onCapture: () {},
            onUseNativeCamera: () {},
            onAutoScan: () {},
            onStopAutoScan: () => stopped = true,
            onRetake: () {},
            onSkip: () {},
            onFinish: () {},
            onValueChanged: (_) {},
            onConfirm: () {},
            onRejectAutoScanReading: () {},
          ),
        ),
      ),
    );

    expect(find.text('Scanning for temperature...'), findsOneWidget);
    final autoScan = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Auto scan'),
    );
    expect(autoScan.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Auto scan'));
    expect(stopped, isFalse);
  });

  testWidgets('auto scan detected reading shows right and wrong actions', (
    tester,
  ) async {
    final valueController = TextEditingController(text: '23.4');
    var accepted = false;
    var rejected = false;

    addTearDown(valueController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGuidedCapturePanel(
            state: EstGuidedCaptureState.initial()
                .startAutoScan()
                .autoScanAttemptStarted()
                .autoScanAttemptResolved(
                  photoPath: '/tmp/front_top_tmp.jpg',
                  ocrValue: 23.4,
                ),
            valueController: valueController,
            preview: const SizedBox(),
            onCapture: () {},
            onUseNativeCamera: () {},
            onAutoScan: () {},
            onStopAutoScan: () {},
            onRetake: () {},
            onSkip: () {},
            onFinish: () {},
            onValueChanged: (_) {},
            onConfirm: () => accepted = true,
            onRejectAutoScanReading: () => rejected = true,
          ),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Right'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Wrong'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retake'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Camera app'), findsNothing);
    expect(find.text('Confirm reading'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Wrong'));
    expect(rejected, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Right'));
    expect(accepted, isTrue);
  });
}
