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
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);

    valueController.text = '23.4';
    await pump(
      EstGuidedCaptureState.initial().captureResolved(
        photoPath: '/tmp/front_top.jpg',
        ocrValue: 23.4,
      ),
    );
    await tester.pump(const Duration(milliseconds: 220));
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNotNull);
    expect(find.text('23.4'), findsWidgets);
    expect(find.text('Is this reading correct?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
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
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);
    expect(find.text('Capture once'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Camera app'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Camera app'));
    expect(openedCameraApp, isTrue);
  });

  testWidgets('scanning state shows capture options without review actions', (
    tester,
  ) async {
    final valueController = TextEditingController();
    var resumed = false;

    addTearDown(valueController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGuidedCapturePanel(
            state: EstGuidedCaptureState.initial(),
            valueController: valueController,
            preview: const SizedBox(),
            onCapture: () {},
            onUseNativeCamera: () {},
            onAutoScan: () => resumed = true,
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

    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);
    expect(find.text('Capture once'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Camera app'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Try again'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Retake'), findsNothing);
    expect(find.text('Scanning for temperature...'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    expect(resumed, isTrue);
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
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);
    final pause = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Pause'),
    );
    expect(pause.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    expect(stopped, isTrue);
  });

  testWidgets('auto scan detected reading shows confirm and retry actions', (
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

    expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retake'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Auto scan'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Capture'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Camera app'), findsNothing);
    expect(find.text('Is this reading correct?'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    expect(rejected, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    expect(accepted, isTrue);
  });

  testWidgets('review state allows editing detected value before confirm', (
    tester,
  ) async {
    final valueController = TextEditingController(text: '23.4');
    final state = EstGuidedCaptureState.initial().captureResolved(
      photoPath: '/tmp/front_top_tmp.jpg',
      ocrValue: 23.4,
    );
    double? editedValue;

    addTearDown(valueController.dispose);

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
            onValueChanged: (value) => editedValue = value,
            onConfirm: () {},
            onRejectAutoScanReading: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Edit reading'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit reading'));
    await tester.pumpAndSettle();

    valueController.clear();
    await tester.pump();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.tap(find.text('7'));
    await tester.tap(find.text('.'));
    await tester.tap(find.text('7'));
    await tester.pump();

    expect(valueController.text, '27.7');
    expect(editedValue, 27.7);
  });

  testWidgets('invalid edited value disables confirm', (tester) async {
    final valueController = TextEditingController(text: '23.4');
    final state = EstGuidedCaptureState.initial().captureResolved(
      photoPath: '/tmp/front_top_tmp.jpg',
      ocrValue: 23.4,
    );

    addTearDown(valueController.dispose);

    Future<void> pumpPanel() async {
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
              onConfirm: () {},
              onRejectAutoScanReading: () {},
            ),
          ),
        ),
      );
    }

    await pumpPanel();
    await tester.tap(find.byTooltip('Edit reading'));
    await tester.pumpAndSettle();

    valueController.clear();
    await pumpPanel();
    await tester.pump();

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text('Enter a valid temperature'), findsOneWidget);
  });
}
