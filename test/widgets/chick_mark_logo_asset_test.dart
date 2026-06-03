import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/widgets/chick_mark_logo.dart';
import 'package:image/image.dart' as img;

void main() {
  test('shared ChickMark logo asset is the transparent cap mark', () {
    final bytes = File(ChickMarkLogo.assetPath).readAsBytesSync();
    final logo = img.decodePng(bytes);

    // PNG IHDR color type: 6 means truecolor with alpha.
    expect(bytes[25], 6);
    expect(logo, isNotNull);
    expect(logo!.width, greaterThanOrEqualTo(1000));
    expect(logo.height, greaterThanOrEqualTo(1250));
  });

  testWidgets('animated ChickMark logo renders with semantics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChickMarkLogo(logoSize: 96, animated: true)),
      ),
    );

    expect(find.bySemanticsLabel('ChickMark logo'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(ChickMarkLogo), findsOneWidget);
  });
}
