import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/widgets/app_card.dart';

void main() {
  testWidgets('AppCard uses a subtle default border', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: SizedBox(width: 40, height: 40))),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.border, isNotNull);
  });
}
