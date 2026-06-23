import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/widgets/est_grid_widget.dart';
import 'package:hatchaudit/features/audits/widgets/photo_button.dart';

void main() {
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

  testWidgets('renders EST as level rows with position columns', (
    tester,
  ) async {
    final controllers = {
      for (final key in EstGridData.scanKeys) key: TextEditingController(),
    };
    final focusNodes = {
      for (final key in EstGridData.scanKeys) key: FocusNode(),
    };

    addTearDown(() {
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
          body: EstGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            photos: const {},
            enabled: true,
            onValueChanged: (_, _) {},
            onPhotoCaptured: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Bottom'), findsOneWidget);
  });

  testWidgets('can render manual entry cells without camera buttons', (
    tester,
  ) async {
    final controllers = {
      for (final key in EstGridData.scanKeys) key: TextEditingController(),
    };
    final focusNodes = {
      for (final key in EstGridData.scanKeys) key: FocusNode(),
    };

    addTearDown(() {
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
          body: EstGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            photos: const {},
            enabled: true,
            showPhotoCapture: false,
            onValueChanged: (_, _) {},
            onPhotoCaptured: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.byType(PhotoButton), findsNothing);
    expect(find.byType(TextField), findsNWidgets(9));
  });

  testWidgets('manual entry cells show saved evidence photo under the value', (
    tester,
  ) async {
    final controllers = {
      for (final key in EstGridData.scanKeys) key: TextEditingController(),
    };
    final focusNodes = {
      for (final key in EstGridData.scanKeys) key: FocusNode(),
    };
    final photoFile = File(
      '${Directory.systemTemp.path}/est-grid-evidence-${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(base64Decode(onePixelPng));

    controllers['front_top']!.text = '23.5';

    addTearDown(() {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      for (final focusNode in focusNodes.values) {
        focusNode.dispose();
      }
      if (photoFile.existsSync()) photoFile.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            photos: {'front_top': photoFile.path},
            enabled: true,
            showPhotoCapture: false,
            onValueChanged: (_, _) {},
            onPhotoCaptured: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.byType(PhotoButton), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
  });

  testWidgets('display grid renders values and thumbnails without text fields', (
    tester,
  ) async {
    final controllers = {
      for (final key in EstGridData.scanKeys) key: TextEditingController(),
    };
    final focusNodes = {
      for (final key in EstGridData.scanKeys) key: FocusNode(),
    };
    final photoFile = File(
      '${Directory.systemTemp.path}/est-grid-display-${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(base64Decode(onePixelPng));
    String? selectedKey;

    controllers['front_top']!.text = '23.5';

    addTearDown(() {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      for (final focusNode in focusNodes.values) {
        focusNode.dispose();
      }
      if (photoFile.existsSync()) photoFile.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            photos: {'front_top': photoFile.path},
            enabled: false,
            showPhotoCapture: false,
            displayOnly: true,
            onCellSelected: (key) => selectedKey = key,
            onValueChanged: (_, _) {},
            onPhotoCaptured: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.text('23.5°F'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('est-grid-cell-front_top')));
    expect(selectedKey, 'front_top');
  });

  testWidgets(
    'manual entry cell with value and no photo shows add photo icon',
    (tester) async {
      final controllers = {
        for (final key in EstGridData.scanKeys) key: TextEditingController(),
      };
      final focusNodes = {
        for (final key in EstGridData.scanKeys) key: FocusNode(),
      };
      String? requestedKey;

      controllers['front_top']!.text = '23.5';

      addTearDown(() {
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
            body: EstGridWidget(
              controllers: controllers,
              focusNodes: focusNodes,
              photos: const {},
              enabled: true,
              showPhotoCapture: false,
              onValueChanged: (_, _) {},
              onPhotoCaptured: (_, _) {},
              onMissingPhotoRequested: (key) => requestedKey = key,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      expect(requestedKey, 'front_top');
    },
  );

  testWidgets('manual entry cell with value shows clear icon for that point', (
    tester,
  ) async {
    final controllers = {
      for (final key in EstGridData.scanKeys) key: TextEditingController(),
    };
    final focusNodes = {
      for (final key in EstGridData.scanKeys) key: FocusNode(),
    };
    String? clearedKey;

    controllers['front_top']!.text = '23.5';

    addTearDown(() {
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
          body: EstGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            photos: const {},
            enabled: true,
            showPhotoCapture: false,
            onValueChanged: (_, _) {},
            onPhotoCaptured: (_, _) {},
            onClearRequested: (key) => clearedKey = key,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Clear reading and photo'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear reading and photo'));
    expect(clearedKey, 'front_top');
  });

  testWidgets('manual entry cell with only photo shows clear icon', (
    tester,
  ) async {
    final controllers = {
      for (final key in EstGridData.scanKeys) key: TextEditingController(),
    };
    final focusNodes = {
      for (final key in EstGridData.scanKeys) key: FocusNode(),
    };
    final photoFile = File(
      '${Directory.systemTemp.path}/est-grid-clear-photo-${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(base64Decode(onePixelPng));

    addTearDown(() {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      for (final focusNode in focusNodes.values) {
        focusNode.dispose();
      }
      if (photoFile.existsSync()) photoFile.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstGridWidget(
            controllers: controllers,
            focusNodes: focusNodes,
            photos: {'front_top': photoFile.path},
            enabled: true,
            showPhotoCapture: false,
            onValueChanged: (_, _) {},
            onPhotoCaptured: (_, _) {},
            onClearRequested: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Clear reading and photo'), findsOneWidget);
  });
}
