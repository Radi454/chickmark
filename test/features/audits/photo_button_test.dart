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

  testWidgets(
    'multi photo button shows existing photos with edit and add more',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiPhotoButton(
              photoPaths: const ['/tmp/chickmark-missing-breakout-photo.jpg'],
              onPhotoCaptured: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('multi-photo-thumbnail-0')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add_a_photo), findsOneWidget);

      await tester.tap(find.byTooltip('Edit photo'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Camera'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Gallery'), findsOneWidget);
    },
  );

  testWidgets('multi photo button can keep every tile on one row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 64,
            child: MultiPhotoButton(
              singleRow: true,
              photoPaths: const [
                '/tmp/chickmark-breakout-photo-1.jpg',
                '/tmp/chickmark-breakout-photo-2.jpg',
              ],
              onPhotoCaptured: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(MultiPhotoButton),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scrollView.scrollDirection, Axis.horizontal);
    expect(
      find.byKey(const ValueKey('multi-photo-thumbnail-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('multi-photo-thumbnail-1')),
      findsOneWidget,
    );
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
