import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/farm_visit_models.dart';
import 'package:hatchaudit/data/models/performance_concern_models.dart';
import 'package:hatchaudit/data/repositories/farm_visit_repository.dart';
import 'package:hatchaudit/data/repositories/performance_concern_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  late FarmVisitRepository repository;

  setUpAll(() async => databaseDirectory = await useIsolatedAppDatabase());
  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await _seedScope();
    repository = FarmVisitRepository();
  });
  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'briefing, houses, investigations, findings and causes persist',
    () async {
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
      const snapshot = VisitBriefingSnapshot(
        generatedAtIso: '2026-07-24T08:00:00.000Z',
        concernIds: ['placeholder'],
        evidence: {'water': 'declined'},
        investigations: ['check_nipple_flow'],
        targetVersion: 'ross-2022',
        ruleVersion: 'defaults-v1',
      );
      final visit = await repository.createVisit(
        customerId: 'customer-1',
        farmId: 'farm-1',
        flockId: 'flock-1',
        visitDate: DateTime.utc(2026, 7, 25),
        briefing: snapshot,
        houseIds: const ['house-1'],
        createdBy: 'auditor-1',
        suggestedInvestigations: [
          VisitInvestigationDraft(
            sourceConcernId: concern.id,
            houseId: 'house-1',
            investigationType: 'check_nipple_flow',
            instruction: 'Measure front, middle, and rear nipple flow.',
          ),
        ],
      );
      await repository.startVisit(visit.id);
      final manual = await repository.addInvestigation(
        VisitInvestigationDraft(
          visitId: visit.id,
          houseId: 'house-1',
          origin: InvestigationOrigin.manual,
          investigationType: 'staff_interview',
          instruction: 'Ask about water interruptions.',
        ),
      );
      await repository.completeInvestigation(
        manual.id,
        resultSummary: 'Valve blockage reported at 09:00.',
      );
      final finding = await repository.addFinding(
        VisitFindingDraft(
          visitId: visit.id,
          investigationId: manual.id,
          findingType: 'nipple_flow',
          measuredValue: 38,
          unit: 'ml/min',
          houseId: 'house-1',
          location: 'rear',
          staffExplanation: 'Pressure falls after flushing.',
          attachmentRefs: const ['photo://rear-line'],
          authoredBy: 'auditor-1',
        ),
      );
      final cause = await repository.saveCauseAssessment(
        CauseAssessmentDraft(
          visitId: visit.id,
          concernId: concern.id,
          probableCause: 'Restricted rear-line water availability',
          supportingEvidenceIds: [finding.id],
          authoredBy: 'auditor-1',
        ),
      );

      expect(cause.status, CauseAssessmentStatus.suspected);
      final probable = await repository.setCauseStatus(
        cause.id,
        CauseAssessmentStatus.probable,
      );
      expect(probable.status, CauseAssessmentStatus.probable);
      await repository.completeVisit(visit.id);

      final loaded = await repository.getVisit(visit.id);
      expect(loaded!.briefing.toJson(), snapshot.toJson());
      expect(loaded.status, FarmVisitStatus.completed);
    },
  );
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
  await db.insert('houses', {
    'id': 'house-1',
    'farmId': 'farm-1',
    'name': 'House 1',
  });
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'F-1',
    'farmId': 'farm-1',
    'sectorKey': 'broiler',
  });
}
