import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/performance_concern_models.dart';
import 'package:hatchaudit/data/repositories/performance_concern_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late PerformanceConcernRepository repository;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await _seedScope();
    repository = PerformanceConcernRepository();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('customer rules override global defaults by metric identity', () async {
    await repository.ensureDefaultRulesSeeded();
    await repository.saveRule(
      const PerformanceAlertRule(
        id: 'customer-water',
        metricKey: 'water_change_without_event',
        scopeLevel: AlertRuleScope.customer,
        customerId: 'customer-1',
        direction: AlertRuleDirection.rateOfChange,
        watchThreshold: 20,
        criticalThreshold: 35,
        minimumValidObservations: 2,
        source: 'Customer policy',
      ),
    );

    final rules = await repository.listEffectiveRules('customer-1');
    final water = rules.singleWhere(
      (rule) => rule.metricKey == 'water_change_without_event',
    );
    expect(water.id, 'customer-water');
    expect(water.criticalThreshold, 35);
  });

  test(
    'detections deduplicate while open and recur after resolution',
    () async {
      final first = await repository.upsertDetection(_detection(1));
      final updated = await repository.upsertDetection(_detection(2));

      expect(updated.id, first.id);
      expect(updated.lastObservedAt, DateTime.utc(2026, 7, 2));

      await repository.setMonitoring(first.id);
      expect(
        (await repository.getConcern(first.id))!.status,
        ConcernStatus.monitoring,
      );
      await repository.resolve(
        first.id,
        resolvedBy: 'auditor-1',
        notes: 'Water intake recovered',
      );
      final recurrence = await repository.upsertDetection(_detection(3));

      expect(recurrence.id, isNot(first.id));
      expect(recurrence.recurrenceOfId, first.id);
    },
  );

  test('dismissal stores explicit user and reason', () async {
    final concern = await repository.upsertDetection(_detection(1));
    await repository.dismiss(
      concern.id,
      dismissedBy: 'auditor-1',
      reason: 'Meter calibration error',
    );

    final dismissed = await repository.getConcern(concern.id);
    expect(dismissed!.status, ConcernStatus.dismissed);
    expect(dismissed.dismissalReason, 'Meter calibration error');
  });
}

PerformanceAlertDetection _detection(int day) {
  return PerformanceAlertDetection(
    ruleId: 'water-change-global',
    metricKey: 'water_change_without_event',
    severity: ConcernSeverity.critical,
    observedAt: DateTime.utc(2026, 7, day),
    windowStart: DateTime.utc(2026, 7, day - 1),
    windowEnd: DateTime.utc(2026, 7, day),
    actualValue: 45,
    baselineValue: 100,
    customerId: 'customer-1',
    farmId: 'farm-1',
    flockId: 'flock-1',
    placementId: 'placement-1',
    houseId: 'house-1',
    evidence: const {'changePct': 45},
    investigationKeys: const ['check_water_meter', 'check_nipple_flow'],
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
  await db.insert('flock_placements', {
    'id': 'placement-1',
    'flockId': 'flock-1',
    'houseId': 'house-1',
    'placedBirds': 10000,
    'placedAt': '2026-07-01',
    'status': 'active',
  });
}
