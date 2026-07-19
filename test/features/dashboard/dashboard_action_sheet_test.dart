import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/dashboard_action_model.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_models.dart';
import 'package:hatchaudit/features/dashboard/widgets/dashboard_action_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('existing action exposes owner status due date and notes', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 12);
    const finding = DashboardFinding(
      key: 'finding-1',
      station: 'Chicks',
      sectorId: 'chick_quality',
      metricKey: 'cvtAvgTemp',
      metricLabel: 'CVT Average',
      valueText: '41.2 °C',
      severity: ScopeSeverity.err,
      rank: 300,
    );
    final action = DashboardActionModel(
      id: 'action-1',
      findingKey: finding.key,
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      title: finding.metricLabel,
      ownerName: 'Shift lead',
      dueAt: now,
      resolutionNotes: 'Check ventilation',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DashboardProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDashboardActionSheet(
                  context,
                  finding: finding,
                  action: action,
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Update action'), findsOneWidget);
    expect(find.text('Shift lead'), findsOneWidget);
    expect(find.text('Action open'), findsOneWidget);
    expect(find.text('Due 2026-07-12'), findsOneWidget);
    expect(find.text('Check ventilation'), findsOneWidget);
    expect(find.text('Save action'), findsOneWidget);
  });
}
