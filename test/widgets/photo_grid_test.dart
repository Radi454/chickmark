import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/widgets/photo_grid.dart';

void main() {
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
