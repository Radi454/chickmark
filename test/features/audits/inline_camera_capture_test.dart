import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/inline_camera_capture.dart';

void main() {
  testWidgets(
    'lifecycle pause shows explicit resume state instead of loading',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: InlineCameraCapture(),
            ),
          ),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(find.text('Camera paused'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Resume camera'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('idle pause reuses the existing camera paused UI', (
    tester,
  ) async {
    final cameraKey = GlobalKey<InlineCameraCaptureState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: InlineCameraCapture(key: cameraKey),
          ),
        ),
      ),
    );

    await cameraKey.currentState!.pauseCameraForIdle();
    await tester.pump();

    expect(find.text('Camera paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume camera'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
