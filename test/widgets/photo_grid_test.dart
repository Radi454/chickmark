import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('durable browser photo renders from persisted bytes', (
    tester,
  ) async {
    final bytes = img.encodeJpg(img.Image(width: 8, height: 8));
    final photoPath = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PhotoImage(filePath: photoPath)),
      ),
    );
    await tester.pump();
    expect(isPhotoPathDisplayable(photoPath), isTrue);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, bytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing image paths render placeholders without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhotoGrid(filePaths: ['/tmp/chickmark-missing-photo.jpg']),
        ),
      ),
    );

    expect(find.byIcon(Icons.image), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('private cloud photo paths resolve to network images', (
    tester,
  ) async {
    const remotePath =
        'supabase://photos/session/residue_breakout/row/photo.jpg';
    const signedUrl = 'https://example.invalid/signed-photo.jpg';
    final resolvedUrl = Completer<String?>();
    String? requestedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoGrid(
            filePaths: const [remotePath],
            remoteUrlResolver: (path) {
              requestedPath = path;
              return resolvedUrl.future;
            },
          ),
        ),
      ),
    );

    expect(requestedPath, remotePath);
    expect(find.byIcon(Icons.image), findsOneWidget);

    resolvedUrl.complete(signedUrl);
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, signedUrl);
  });
}
