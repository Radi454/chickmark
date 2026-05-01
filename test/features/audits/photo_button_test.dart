import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/inline_camera_capture.dart';
import 'package:hatchaudit/features/audits/widgets/photo_button.dart';

void main() {
  testWidgets('camera-first photo button opens camera with gallery option', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoButton(cameraFirst: true, onPhotoCaptured: (_) {}),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pump();

    expect(find.byType(InlineCameraCapture), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Camera'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Gallery'), findsNothing);
  });
}
