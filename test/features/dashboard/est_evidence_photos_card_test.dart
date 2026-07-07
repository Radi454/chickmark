import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/models/egg_storage_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/est_evidence_photos_card.dart';

void main() {
  const onePixelPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

  testWidgets('renders the 9-point EST evidence grid in canonical order', (
    tester,
  ) async {
    final photoFile = File(
      '${Directory.systemTemp.path}/dashboard-est-evidence-${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(base64Decode(onePixelPng));
    addTearDown(() {
      if (photoFile.existsSync()) photoFile.deleteSync();
    });

    final evidence = EggStorageEstEvidence.fromJsonStrings(
      readingsJson: '{"front_top":20.1,"middle_middle":20.5}',
      photosJson: '{"front_top":"${photoFile.path}"}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EstEvidencePhotosCard(evidence: evidence)),
      ),
    );

    expect(find.text('Captured Photos'), findsOneWidget);
    expect(find.text('9-point EST evidence'), findsOneWidget);
    expect(find.text('Partial'), findsOneWidget);
    expect(find.text('Front Top'), findsOneWidget);
    expect(find.text('Front Middle'), findsOneWidget);
    expect(find.text('Front Bottom'), findsOneWidget);
    expect(find.text('Middle Top'), findsOneWidget);
    expect(find.text('Middle Middle'), findsOneWidget);
    expect(find.text('Middle Bottom'), findsOneWidget);
    expect(find.text('Back Top'), findsOneWidget);
    expect(find.text('Back Middle'), findsOneWidget);
    expect(find.text('Back Bottom'), findsOneWidget);
    expect(find.text('20.1°C'), findsOneWidget);
    expect(find.text('20.5°C'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsWidgets);
  });

  testWidgets('opens fullscreen callback only for valid photo paths', (
    tester,
  ) async {
    final photoFile = File(
      '${Directory.systemTemp.path}/dashboard-est-evidence-tap-${DateTime.now().microsecondsSinceEpoch}.png',
    )..writeAsBytesSync(base64Decode(onePixelPng));
    String? tappedPath;
    addTearDown(() {
      if (photoFile.existsSync()) photoFile.deleteSync();
    });

    final evidence = EggStorageEstEvidence.fromJsonStrings(
      readingsJson: '{"front_top":20.1,"front_middle":20.2}',
      photosJson:
          '{"front_top":"${photoFile.path}","front_middle":"/missing/photo.jpg"}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstEvidencePhotosCard(
            evidence: evidence,
            onPhotoTap: (path) => tappedPath = path,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Image));
    expect(tappedPath, photoFile.path);

    await tester.tap(find.text('Front Middle'));
    expect(tappedPath, photoFile.path);
  });

  testWidgets('renders the saved unit from temperature reading payloads', (
    tester,
  ) async {
    final evidence = EggStorageEstEvidence.fromJsonStrings(
      readingsJson:
          '{"unit":"°F","readings":{"front_top":68.2,"middle_middle":69.1}}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EstEvidencePhotosCard(evidence: evidence)),
      ),
    );

    expect(find.text('68.2°F'), findsOneWidget);
    expect(find.text('69.1°F'), findsOneWidget);
    expect(find.text('68.2°C'), findsNothing);
  });
}
