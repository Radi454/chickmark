import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/features/customers/widgets/customer_card.dart';

void main() {
  testWidgets('CustomerCard displays a simple customer symbol', (tester) async {
    final customer = CustomerModel(
      id: 'customer-1',
      name: 'Blue Valley Farms',
      location: 'Cairo',
      phone: '+20 100 000 0000',
      createdAt: DateTime(2026, 5, 16),
      createdBy: 'tester',
    );

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
}
