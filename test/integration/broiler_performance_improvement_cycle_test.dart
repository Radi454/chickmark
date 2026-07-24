import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/data/models/corrective_action_models.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/farm_visit_models.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/performance_concern_models.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/broiler_daily_record_repository.dart';
import 'package:hatchaudit/data/repositories/broiler_target_repository.dart';
import 'package:hatchaudit/data/repositories/corrective_action_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/farm_visit_repository.dart';
import 'package:hatchaudit/data/repositories/performance_concern_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/features/performance/providers/performance_provider.dart';
import 'package:hatchaudit/features/performance/services/action_effectiveness_evaluator.dart';
import 'package:hatchaudit/features/performance/services/performance_alert_engine.dart';
import 'package:hatchaudit/features/performance/services/visit_briefing_builder.dart';

import '../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late PoultryHierarchyRepository hierarchy;
  late BroilerDailyRecordRepository dailyRecords;
  late BroilerTargetRepository targets;
  late PerformanceConcernRepository concerns;
  late FarmVisitRepository visits;
  late CorrectiveActionRepository actions;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    hierarchy = PoultryHierarchyRepository();
    dailyRecords = BroilerDailyRecordRepository();
    targets = BroilerTargetRepository();
    concerns = PerformanceConcernRepository();
    visits = FarmVisitRepository();
    actions = CorrectiveActionRepository();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'daily deviation drives visit diagnosis and measured action recovery',
    () async {
      const customerId = 'customer-cycle';
      const farmId = 'farm-broiler';
      const flockId = 'flock-cycle';
      const frontHouseId = 'house-front';
      const rearHouseId = 'house-rear';
      const frontPlacementId = 'placement-front';
      const rearPlacementId = 'placement-rear';
      final entryDate = DateTime.utc(2026, 7, 1);

      await CustomerRepository().insertCustomer(
        CustomerModel(
          id: customerId,
          name: 'Integrated Poultry Customer',
          createdAt: DateTime.utc(2026, 7, 1),
          createdBy: 'admin-1',
        ),
      );
      await hierarchy.replaceCustomerSectors(customerId, {
        PoultrySector.breeder,
        PoultrySector.broiler,
        PoultrySector.layer,
      });
      for (final farm in [
        FarmModel(
          id: 'farm-breeder',
          customerId: customerId,
          sector: PoultrySector.breeder,
          name: 'Breeder Farm',
        ),
        FarmModel(
          id: farmId,
          customerId: customerId,
          sector: PoultrySector.broiler,
          name: 'Broiler Farm',
        ),
        FarmModel(
          id: 'farm-layer',
          customerId: customerId,
          sector: PoultrySector.layer,
          name: 'Layer Farm',
        ),
      ]) {
        await hierarchy.saveFarm(farm);
      }
      await hierarchy.saveHouse(
        HouseModel(
          id: frontHouseId,
          farmId: farmId,
          name: 'Front House',
          capacity: 5000,
        ),
      );
      await hierarchy.saveHouse(
        HouseModel(
          id: rearHouseId,
          farmId: farmId,
          name: 'Rear House',
          capacity: 5000,
        ),
      );

      await targets.ensureOfficialCatalogueSeeded();
      final flock = FlockModel(
        id: flockId,
        customerId: customerId,
        flockId: 'BR-2026-07',
        breed: 'Ross 308',
        entryDate: entryDate,
        farmId: farmId,
        sector: PoultrySector.broiler,
        targetProfileId: 'ross-308-2022-as-hatched',
        productionPhase: 'grower',
      );
      await hierarchy.createBroilerFlockWithPlacements(flock, [
        FlockPlacementModel(
          id: frontPlacementId,
          flockId: flockId,
          houseId: frontHouseId,
          placedBirds: 5000,
          placedAt: entryDate,
        ),
        FlockPlacementModel(
          id: rearPlacementId,
          flockId: flockId,
          houseId: rearHouseId,
          placedBirds: 5000,
          placedAt: entryDate,
        ),
      ]);

      final liveBirds = <String, int>{
        frontPlacementId: 5000,
        rearPlacementId: 5000,
      };
      String? correctedRecordId;
      for (var age = 20; age <= 24; age++) {
        final target = await targets.getRow('ross-308-2022-as-hatched', age);
        expect(target?.bodyWeightG, isNotNull);
        for (final placementId in [frontPlacementId, rearPlacementId]) {
          final opening = liveBirds[placementId]!;
          final isRear = placementId == rearPlacementId;
          final draft = BroilerDailyRecordDraft(
            placementId: placementId,
            recordDate: entryDate.add(Duration(days: age)),
            verificationStatus: VerificationStatus.entered,
            dataSourceType: DailyDataSourceType.spreadsheet,
            sourceDescription: 'Farm daily report',
            reportedBy: 'Farm clerk',
            enteredBy: 'auditor-1',
            enteredAt: entryDate.add(Duration(days: age, hours: 18)),
            openingBirdCount: opening,
            dailyMortality: 2,
            dailyCulls: 1,
            transfersIn: 0,
            transfersOut: 0,
            partialDepletion: 0,
            otherPopulationAdjustment: 0,
            closingLiveBirdCount: opening - 3,
            dailyFeedConsumedKg: 110,
            waterConsumedLiters: 165,
            averageBodyWeightG: target!.bodyWeightG! * (isRear ? 0.86 : 0.92),
            birdsWeighed: 100,
            uniformityPct: isRear ? 70 : 82,
            cvPct: isRear ? 14 : 9,
          );
          final saved = await dailyRecords.saveRevision(draft);
          liveBirds[placementId] = opening - 3;

          if (age == 22 && isRear) {
            correctedRecordId = saved.record.id;
            final corrected = await dailyRecords.saveRevision(
              draft.copyWith(
                recordId: saved.record.id,
                verificationStatus: VerificationStatus.corrected,
                correctionReason: 'Mortality source sheet verified.',
                dailyMortality: 3,
                closingLiveBirdCount: opening - 4,
              ),
            );
            liveBirds[placementId] = opening - 4;
            expect(corrected.revision.revisionNumber, 2);
          }
        }
      }
      expect(correctedRecordId, isNotNull);
      expect(
        await dailyRecords.listRevisions(correctedRecordId!),
        hasLength(2),
      );

      final dataSource = SqlitePerformanceWorkspaceDataSource();
      final preVisit = await dataSource.loadSnapshot(
        flock: flock,
        rangeStart: entryDate.add(const Duration(days: 20)),
        rangeEnd: entryDate.add(const Duration(days: 24)),
      );
      expect(preVisit.trendPoints, hasLength(5));
      expect(preVisit.metrics['age_day']?.value, 24);
      expect(preVisit.metrics['weight_deviation_pct']?.value, lessThan(-5));
      expect(
        preVisit.metrics['water_to_feed_ratio']?.value,
        closeTo(1.5, 0.001),
      );
      expect(preVisit.reportedData, isTrue);

      await concerns.ensureDefaultRulesSeeded();
      final weightRule = (await concerns.listEffectiveRules(
        customerId,
      )).singleWhere((rule) => rule.metricKey == 'weight_deviation_pct');
      final weightObservations = <PerformanceAlertObservation>[];
      for (var age = 20; age <= 24; age++) {
        final target = await targets.getRow('ross-308-2022-as-hatched', age);
        final point = preVisit.trendPoints[age - 20];
        final observed = point.values['weight_g']!;
        weightObservations.add(
          PerformanceAlertObservation(
            metricKey: 'weight_deviation_pct',
            observedAt: point.date,
            value:
                (observed - target!.bodyWeightG!) / target.bodyWeightG! * 100,
            targetValue: target.bodyWeightG,
          ),
        );
      }
      final detection = const PerformanceAlertEngine().evaluate(
        weightRule,
        weightObservations,
        customerId: customerId,
        farmId: farmId,
        flockId: flockId,
        placementId: rearPlacementId,
        houseId: rearHouseId,
      );
      expect(detection?.severity, ConcernSeverity.critical);
      final concern = await concerns.upsertDetection(detection!);

      final briefing = const VisitBriefingBuilder().build(
        generatedAt: DateTime.utc(2026, 7, 26, 7),
        targetVersion: 'Ross 308 · 2022',
        ruleVersion: 'defaults-v1',
        concerns: [
          VisitBriefingConcern(
            concernId: 'temporary',
            metricKey: 'weight_deviation_pct',
            actualValue: -9,
            targetValue: 0,
            evidenceSummary:
                'Weight and water intake remain below objective in the rear.',
            investigationKeys: [
              'sample_weights_by_location',
              'check_nipple_flow',
            ],
          ),
        ],
      );
      final visit = await visits.createVisit(
        customerId: customerId,
        farmId: farmId,
        flockId: flockId,
        visitDate: DateTime.utc(2026, 7, 26),
        briefing: briefing,
        houseIds: const [frontHouseId, rearHouseId],
        createdBy: 'auditor-1',
        suggestedInvestigations: [
          VisitInvestigationDraft(
            sourceConcernId: concern.id,
            houseId: rearHouseId,
            location: 'rear',
            investigationType: 'check_nipple_flow',
            instruction: 'Measure front, middle, and rear nipple flow.',
          ),
        ],
      );
      await visits.startVisit(visit.id);
      final investigation = (await visits.getVisit(
        visit.id,
      ))!.investigations.single;
      await visits.completeInvestigation(
        investigation.id,
        resultSummary: 'Rear flow was restricted.',
      );
      final rearFlow = await visits.addFinding(
        VisitFindingDraft(
          visitId: visit.id,
          investigationId: investigation.id,
          findingType: 'nipple_flow',
          measuredValue: 38,
          unit: 'ml/min',
          houseId: rearHouseId,
          location: 'rear',
          authoredBy: 'auditor-1',
        ),
      );
      final rearWeight = await visits.addFinding(
        VisitFindingDraft(
          visitId: visit.id,
          investigationId: investigation.id,
          findingType: 'sample_weight_difference',
          measuredValue: 105,
          unit: 'g',
          houseId: rearHouseId,
          location: 'rear',
          authoredBy: 'auditor-1',
        ),
      );
      final cause = await visits.saveCauseAssessment(
        CauseAssessmentDraft(
          visitId: visit.id,
          concernId: concern.id,
          probableCause: 'Restricted rear-house water availability',
          supportingEvidenceIds: [rearFlow.id, rearWeight.id],
          status: CauseAssessmentStatus.probable,
          authoredBy: 'auditor-1',
        ),
      );

      final action = await actions.createAction(
        CorrectiveActionDraft(
          concernId: concern.id,
          visitId: visit.id,
          causeAssessmentId: cause.id,
          instruction: 'Adjust pressure and flush the rear water line.',
          ownerName: 'Farm manager',
          dueAt: DateTime.utc(2026, 7, 26, 12),
          createdBy: 'auditor-1',
        ),
        evaluations: [
          ActionKpiEvaluationDefinition(
            kpiKey: 'water_to_feed_ratio',
            scope: const {'houseId': rearHouseId},
            baselineWindowStart: DateTime.utc(2026, 7, 21),
            baselineWindowEnd: DateTime.utc(2026, 7, 25),
            baselineValue: 1.5,
            targetRule: ActionTargetRule.atLeast,
            targetValue: 1.7,
            evaluationStart: DateTime.utc(2026, 7, 27),
            evaluationEnd: DateTime.utc(2026, 7, 29),
          ),
        ],
      );
      await actions.confirmImplementation(
        action.id,
        confirmedBy: 'auditor-1',
        implementedAt: DateTime.utc(2026, 7, 26, 10),
      );

      for (var age = 25; age <= 27; age++) {
        final target = await targets.getRow('ross-308-2022-as-hatched', age);
        for (final placementId in [frontPlacementId, rearPlacementId]) {
          final opening = liveBirds[placementId]!;
          await dailyRecords.saveRevision(
            BroilerDailyRecordDraft(
              placementId: placementId,
              recordDate: entryDate.add(Duration(days: age)),
              verificationStatus: VerificationStatus.entered,
              dataSourceType: DailyDataSourceType.spreadsheet,
              reportedBy: 'Farm clerk',
              enteredBy: 'auditor-1',
              enteredAt: entryDate.add(Duration(days: age, hours: 18)),
              openingBirdCount: opening,
              dailyMortality: 1,
              dailyCulls: 1,
              transfersIn: 0,
              transfersOut: 0,
              partialDepletion: 0,
              otherPopulationAdjustment: 0,
              closingLiveBirdCount: opening - 2,
              dailyFeedConsumedKg: 110,
              waterConsumedLiters: 192.5,
              averageBodyWeightG: target!.bodyWeightG! * 0.96,
              birdsWeighed: 100,
              uniformityPct: 84,
              cvPct: 8,
            ),
          );
          liveBirds[placementId] = opening - 2;
        }
      }

      final postAction = await dataSource.loadSnapshot(
        flock: flock,
        rangeStart: entryDate.add(const Duration(days: 20)),
        rangeEnd: entryDate.add(const Duration(days: 27)),
      );
      expect(
        postAction.metrics['water_to_feed_ratio']?.value,
        closeTo(1.75, 0.001),
      );
      expect(
        postAction.metrics['weight_deviation_pct']?.value,
        greaterThan(-5),
      );

      final evaluationDefinition = action.evaluations.single.toDefinition();
      final result = const ActionEffectivenessEvaluator().evaluate(
        definition: evaluationDefinition,
        implementationConfirmed: true,
        evaluatedAt: DateTime.utc(2026, 7, 30),
        observations: [
          for (var age = 25; age <= 27; age++)
            ActionKpiObservation(
              kpiKey: 'water_to_feed_ratio',
              scope: const {'houseId': rearHouseId},
              observedAt: entryDate.add(Duration(days: age)),
              value: 1.75,
            ),
        ],
      );
      expect(result.effectiveness, ActionEffectiveness.effective);
      await actions.recordEvaluation(
        action.evaluations.single.id,
        result: result,
        evaluatedBy: 'auditor-1',
        evaluatedAt: DateTime.utc(2026, 7, 30),
      );
      await actions.completeAction(
        action.id,
        completionNotes: 'Water intake recovered and weight gap narrowed.',
        evidenceRefs: [rearFlow.id, rearWeight.id],
      );
      await visits.completeVisit(visit.id);
      await concerns.resolve(
        concern.id,
        resolvedBy: 'auditor-1',
        notes: 'Post-action daily KPIs met the recovery target.',
      );

      final completed = await actions.getAction(action.id);
      final resolved = await concerns.getConcern(concern.id);
      expect(completed?.status, CorrectiveActionStatus.completed);
      expect(
        completed?.evaluations.single.effectiveness,
        ActionEffectiveness.effective,
      );
      expect(resolved?.status, ConcernStatus.resolved);
      expect(
        (await hierarchy.listCustomerSectors(
          customerId,
        )).where((membership) => membership.isActive),
        hasLength(3),
      );
    },
  );
}
