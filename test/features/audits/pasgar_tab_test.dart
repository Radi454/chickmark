import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/features/audits/widgets/tabs/pasgar_tab.dart';

void main() {
  AuditModel auditFixture() {
    return AuditModel(
      id: 'pasgar-tab-test',
      auditType: 'Chicks',
      customerId: 'customer-1',
      flockId: 'flock-1',
      date: DateTime(2026, 5, 16),
      hatchNumber: 1,
      status: 'active',
      createdBy: 'auditor-1',
      createdAt: DateTime(2026, 5, 16),
      updatedAt: DateTime(2026, 5, 16),
    );
  }

  Future<void> pumpPasgarTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasgarTab(
            audit: auditFixture(),
            isReadOnly: false,
            embedded: true,
            onFieldChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders Pasgar fields without unrelated decorative icons', (
    tester,
  ) async {
    await pumpPasgarTab(tester);

    expect(find.text('Sample Size'), findsNothing);
    expect(find.text('Defect Counts'), findsNothing);
    expect(find.text('Reflexes'), findsOneWidget);
    expect(find.text('Beak'), findsOneWidget);
    expect(find.text('Navel'), findsOneWidget);
    expect(find.text('Belly'), findsOneWidget);
    expect(find.text('Leg'), findsOneWidget);
    expect(find.text('Feather Dev'), findsOneWidget);

    expect(find.byIcon(Icons.numbers), findsNothing);
    expect(find.byIcon(Icons.warning), findsNothing);
    expect(find.byIcon(Icons.accessibility_new), findsNothing);
    expect(find.byIcon(Icons.pets), findsNothing);
    expect(find.byIcon(Icons.healing), findsNothing);
    expect(find.byIcon(Icons.circle_outlined), findsNothing);
    expect(find.byIcon(Icons.directions_walk), findsNothing);
    expect(find.byIcon(Icons.air), findsNothing);
  });

  testWidgets('keeps embedded defect rows compact at station width', (
    tester,
  ) async {
    await pumpPasgarTab(tester);

    final reflexes = tester.widget<Text>(find.text('Reflexes'));

    expect(reflexes.style?.fontSize, lessThanOrEqualTo(17));
  });
}
