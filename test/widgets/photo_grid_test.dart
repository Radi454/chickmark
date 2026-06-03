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
}
