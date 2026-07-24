import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/corrective_action_models.dart';
import 'package:hatchaudit/features/performance/providers/farm_visit_provider.dart';
import 'package:hatchaudit/features/performance/screens/corrective_action_screen.dart';

void main() {
  testWidgets('shows action ownership and before-after KPI evidence', (
    tester,
  ) async {
    final provider = FarmVisitProvider.debug(action: _action());

    await tester.pumpWidget(
      MaterialApp(home: CorrectiveActionScreen(provider: provider)),
    );

    expect(
      find.text('Adjust pressure and flush the rear water line.'),
      findsOneWidget,
    );
    expect(find.textContaining('Farm manager'), findsOneWidget);
    expect(find.text('KPI effectiveness'), findsOneWidget);
    expect(find.textContaining('Before 1.51'), findsOneWidget);
    expect(find.textContaining('After 1.74'), findsOneWidget);
    expect(find.text('Effective'), findsOneWidget);
    expect(
      find.textContaining('Latest valid observation met the target'),
      findsOneWidget,
    );
  });
}

CorrectiveAction _action() {
  return CorrectiveAction(
    id: 'action-1',
    concernId: 'concern-1',
    visitId: 'visit-1',
    causeAssessmentId: 'cause-1',
    instruction: 'Adjust pressure and flush the rear water line.',
    ownerName: 'Farm manager',
    dueAt: DateTime.utc(2026, 7, 25, 12),
    implementedAt: DateTime.utc(2026, 7, 25, 10),
    implementationConfirmedBy: 'auditor-1',
    status: CorrectiveActionStatus.implemented,
    evaluations: [
      ActionKpiEvaluation(
        id: 'evaluation-1',
        actionId: 'action-1',
        kpiKey: 'water_to_feed_ratio',
        scope: const {'houseId': 'house-1'},
        baselineWindowStart: DateTime.utc(2026, 7, 22),
        baselineWindowEnd: DateTime.utc(2026, 7, 24),
        baselineValue: 1.51,
        targetRule: ActionTargetRule.atLeast,
        targetValue: 1.70,
        evaluationStart: DateTime.utc(2026, 7, 26),
        evaluationEnd: DateTime.utc(2026, 7, 28),
        observedValue: 1.74,
        effectiveness: ActionEffectiveness.effective,
        evaluationReason: 'Latest valid observation met the target.',
        evaluatedBy: 'auditor-1',
        evaluatedAt: DateTime.utc(2026, 7, 28, 12),
      ),
    ],
  );
}
