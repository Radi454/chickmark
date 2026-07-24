import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/corrective_action_models.dart';
import 'package:hatchaudit/data/models/performance_concern_models.dart';
import 'package:hatchaudit/data/repositories/corrective_action_repository.dart';
import 'package:hatchaudit/data/repositories/performance_concern_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  late CorrectiveActionRepository repository;

  setUpAll(() async => databaseDirectory = await useIsolatedAppDatabase());
  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await _seedScope();
    repository = CorrectiveActionRepository();
  });
  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('action owns immutable KPI baseline and explicit evaluation', () async {
    final concern = await PerformanceConcernRepository().upsertDetection(
      PerformanceAlertDetection(
        ruleId: 'water-change-global',
        metricKey: 'water_change_without_event',
        severity: ConcernSeverity.critical,
        observedAt: DateTime.utc(2026, 7, 24),
        windowStart: DateTime.utc(2026, 7, 23),
        windowEnd: DateTime.utc(2026, 7, 24),
        actualValue: 45,
        customerId: 'customer-1',
        farmId: 'farm-1',
        flockId: 'flock-1',
      ),
    );
    final db = await DatabaseHelper().db;
    await db.insert('cause_assessments', {
      'id': 'cause-1',
      'visitId': 'visit-1',
      'concernId': concern.id,
      'probableCause': 'Restricted water availability',
    });
    final created = await repository.createAction(
      CorrectiveActionDraft(
        concernId: concern.id,
        visitId: 'visit-1',
        causeAssessmentId: 'cause-1',
        instruction: 'Adjust pressure and flush the rear water line.',
        ownerName: 'Farm manager',
        dueAt: DateTime.utc(2026, 7, 25, 12),
        createdBy: 'auditor-1',
      ),
      evaluations: [
        ActionKpiEvaluationDefinition(
          kpiKey: 'water_to_feed_ratio',
          scope: const {'houseId': 'house-1'},
          baselineWindowStart: DateTime.utc(2026, 7, 22),
          baselineWindowEnd: DateTime.utc(2026, 7, 24),
          baselineValue: 1.51,
          targetRule: ActionTargetRule.atLeast,
          targetValue: 1.70,
          evaluationStart: DateTime.utc(2026, 7, 26),
          evaluationEnd: DateTime.utc(2026, 7, 28),
        ),
      ],
    );

    expect(created.concernId, concern.id);
    expect(created.visitId, 'visit-1');
    expect(created.causeAssessmentId, 'cause-1');
    expect(created.evaluations.single.baselineValue, 1.51);

    final implemented = await repository.confirmImplementation(
      created.id,
      confirmedBy: 'auditor-1',
      implementedAt: DateTime.utc(2026, 7, 25, 10),
    );
    expect(implemented.status, CorrectiveActionStatus.implemented);
    expect(implemented.implementationConfirmedBy, 'auditor-1');

    final evaluation = await repository.recordEvaluation(
      created.evaluations.single.id,
      result: const ActionEvaluationResult(
        effectiveness: ActionEffectiveness.effective,
        baselineValue: 1.51,
        observedValue: 1.74,
        reason: 'Latest valid observation met the target.',
      ),
      evaluatedBy: 'auditor-1',
      evaluatedAt: DateTime.utc(2026, 7, 28, 12),
    );
    expect(evaluation.effectiveness, ActionEffectiveness.effective);

    final loaded = await repository.getAction(created.id);
    expect(loaded!.evaluations.single.baselineValue, 1.51);
    expect(loaded.evaluations.single.observedValue, 1.74);
  });
}

Future<void> _seedScope() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {'id': 'customer-1', 'name': 'Customer'});
  await db.insert('farms', {
    'id': 'farm-1',
    'customerId': 'customer-1',
    'sectorKey': 'broiler',
    'name': 'Farm',
  });
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'F-1',
    'farmId': 'farm-1',
    'sectorKey': 'broiler',
  });
  await db.insert('farm_visit_sessions', {
    'id': 'visit-1',
    'customerId': 'customer-1',
    'farmId': 'farm-1',
    'flockId': 'flock-1',
    'visitDate': '2026-07-25T00:00:00.000Z',
    'briefingSnapshotJson': '{}',
  });
}
