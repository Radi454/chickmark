import 'dart:io';

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

  test('audit photo buttons declare sync field identities', () {
    final root = Directory.current.path;
    final yfbm = File(
      '$root/lib/features/audits/widgets/tabs/yfbm_tab.dart',
    ).readAsStringSync();
    final pm = File(
      '$root/lib/features/audits/widgets/tabs/pm_necropsy_tab.dart',
    ).readAsStringSync();
    final pasgar = File(
      '$root/lib/features/audits/widgets/tabs/pasgar_tab.dart',
    ).readAsStringSync();
    final setter = File(
      '$root/lib/features/audits/screens/setter_optimizing_screen.dart',
    ).readAsStringSync();
    final hatcher = File(
      '$root/lib/features/audits/screens/hatcher_optimizing_screen.dart',
    ).readAsStringSync();
    final estGrid = File(
      '$root/lib/features/audits/widgets/est_grid_widget.dart',
    ).readAsStringSync();

    expect(yfbm, contains("fieldKey: 'yfbm_photo'"));
    expect(pm, contains("fieldKey: 'pm_photo'"));
    expect(pasgar, contains('fieldKey: photoFields[index]'));
    expect(setter, contains("fieldKey: 'co2_photo'"));
    expect(hatcher, contains("fieldKey: 'chick_panting_photo'"));
    expect(hatcher, contains("fieldKey: 'co2_photo'"));
    expect(estGrid, contains('fieldKey: key'));
  });
}
