import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/features/customers/widgets/customer_card.dart';

void main() {
  final customer = CustomerModel(
    id: 'customer-1',
    name: 'Blue Valley Farms',
    location: 'Cairo',
    phone: '+20 100 000 0000',
    createdAt: DateTime(2026, 5, 16),
    createdBy: 'tester',
  );

  testWidgets('CustomerCard displays a simple customer symbol', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerCard(customer: customer, flockCount: 2, onTap: () {}),
        ),
      ),
    );

    expect(find.byIcon(Icons.business_outlined), findsOneWidget);
    expect(find.text('Blue Valley Farms'), findsOneWidget);
  });

  testWidgets('CustomerCard exposes delete only when callback exists', (
    tester,
  ) async {
    var deleteCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerCard(
            customer: customer,
            flockCount: 2,
            onDelete: () => deleteCalls++,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Delete customer'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete customer'));
    expect(deleteCalls, 1);
  });

  testWidgets('CustomerCard hides delete without a callback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CustomerCard(customer: customer, flockCount: 2)),
      ),
    );

    expect(find.byTooltip('Delete customer'), findsNothing);
  });
}
