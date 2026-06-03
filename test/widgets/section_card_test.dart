import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/widgets/section_card.dart';

void main() {
  testWidgets('SectionCard can render a leading section icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionCard(
            title: 'Account',
            icon: Icons.person_outline,
            child: Text('Profile'),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });
}
