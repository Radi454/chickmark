import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/farm_visit_models.dart';
import 'package:hatchaudit/features/performance/providers/farm_visit_provider.dart';
import 'package:hatchaudit/features/performance/screens/farm_visit_screen.dart';

void main() {
  testWidgets('shows frozen daily evidence and explicit cause control', (
    tester,
  ) async {
    final provider = FarmVisitProvider.debug(visit: _visit());

    await tester.pumpWidget(
      MaterialApp(home: FarmVisitScreen(provider: provider)),
    );

    expect(find.text('Visit briefing'), findsOneWidget);
    expect(find.text('Daily performance evidence'), findsOneWidget);
    expect(
      find.textContaining('Water:feed declined from 1.74 to 1.51'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('visit-daily-data-readonly')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('visit-daily-data-input')), findsNothing);
    expect(
      find.text('Measure front, middle, and rear nipple flow.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pressure falls after flushing'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('cause-status-cause-1')),
      280,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cause-status-cause-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Probable').last);
    await tester.pumpAndSettle();

    expect(
      provider.visit!.causeAssessments.single.status,
      CauseAssessmentStatus.probable,
    );
  });
}

FarmVisitSession _visit() {
  return FarmVisitSession(
    id: 'visit-1',
    customerId: 'customer-1',
    farmId: 'farm-1',
    flockId: 'flock-1',
    visitDate: DateTime.utc(2026, 7, 25),
    briefing: const VisitBriefingSnapshot(
      generatedAtIso: '2026-07-24T08:00:00.000Z',
      concernIds: ['concern-1'],
      evidence: {
        'concern-1': {
          'metricKey': 'water_to_feed_ratio',
          'evidenceSummary': 'Water:feed declined from 1.74 to 1.51',
          'actualValue': 1.51,
        },
      },
      investigations: ['check_nipple_flow'],
      targetVersion: 'ross-308-2022',
      ruleVersion: 'defaults-v1',
    ),
    status: FarmVisitStatus.inProgress,
    houseIds: const ['house-1'],
    investigations: const [
      VisitInvestigation(
        id: 'investigation-1',
        visitId: 'visit-1',
        sourceConcernId: 'concern-1',
        houseId: 'house-1',
        origin: InvestigationOrigin.suggested,
        investigationType: 'check_nipple_flow',
        instruction: 'Measure front, middle, and rear nipple flow.',
        status: InvestigationStatus.completed,
        resultSummary: 'Rear flow was 38 ml/min.',
      ),
    ],
    findings: const [
      VisitFinding(
        id: 'finding-1',
        visitId: 'visit-1',
        investigationId: 'investigation-1',
        findingType: 'nipple_flow',
        measuredValue: 38,
        unit: 'ml/min',
        location: 'rear',
        staffExplanation: 'Pressure falls after flushing.',
      ),
    ],
    causeAssessments: const [
      CauseAssessment(
        id: 'cause-1',
        visitId: 'visit-1',
        concernId: 'concern-1',
        probableCause: 'Restricted rear-line water availability',
        supportingEvidenceIds: ['finding-1'],
        status: CauseAssessmentStatus.suspected,
      ),
    ],
  );
}
