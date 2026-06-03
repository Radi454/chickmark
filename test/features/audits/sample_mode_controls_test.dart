import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';
import 'package:hatchaudit/features/audits/widgets/sample_mode_controls.dart';

void main() {
  AuditProvider initializedProvider(String auditType) {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: auditType,
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-04-27',
      ),
      notify: false,
    );
    return provider;
  }

  Future<void> pumpControls(
    WidgetTester tester, {
    required String auditType,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationSampleModeControls(
            provider: initializedProvider(auditType),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('opens sample mode help with chick quality explanation', (
    tester,
  ) async {
    await pumpControls(tester, auditType: 'Chicks');

    expect(
      find.text('One sample representing the overall condition.'),
      findsNothing,
    );
    expect(
      find.text(
        'Add separate samples and compare their results side by side.\n'
        'Each sample is entered and saved separately.',
      ),
      findsNothing,
    );

    await tester.tap(find.bySemanticsLabel('Help: Sample Mode explanation'));
    await tester.pumpAndSettle();

    expect(find.text('Understanding Sample Mode'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Single Sample'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('One sample representing the overall condition.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Compare Samples'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Add separate samples and compare their results side by side.\n'
        'Each sample is entered and saved separately.',
      ),
      findsOneWidget,
    );
    expect(find.text('Batch Level:'), findsOneWidget);
    expect(find.text('Compare different egg batches.'), findsOneWidget);
    expect(find.text('House Level:'), findsOneWidget);
    expect(find.text('Compare houses within the same batch.'), findsOneWidget);
    expect(find.text('Machine Level:'), findsOneWidget);
    expect(
      find.text('Compare machines (Setter + Hatcher) within the same batch.'),
      findsOneWidget,
    );
    expect(find.text('Tray Level:'), findsOneWidget);
    expect(find.text('Compare trays within the same machine.'), findsOneWidget);
    expect(
      find.text('Each level represents a deeper level of detail.'),
      findsOneWidget,
    );
  });

  testWidgets('sample mode help shows shared sampling hierarchy', (
    tester,
  ) async {
    await pumpControls(tester, auditType: 'Hatch Analysis & Egg Breakouts');

    await tester.tap(find.bySemanticsLabel('Help: Sample Mode explanation'));
    await tester.pumpAndSettle();

    expect(find.text('Batch Level:'), findsOneWidget);
    expect(find.text('House Level:'), findsOneWidget);
    expect(find.text('Machine Level:'), findsOneWidget);
    expect(find.text('Tray Level:'), findsOneWidget);
  });
}
