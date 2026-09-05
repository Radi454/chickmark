import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';

import '../../support/test_database.dart';

/// `breeder_alert_rules`/`breeder_performance_alerts`
/// (breeder-flock-performance ticket 17, design doc section 10 and 12).
/// Schema-level enforcement that must hold with or without the service
/// layer above it: the seeded default rules exist, the metric vocabulary
/// CHECK constraint, the house-scope guard trigger, and — most
/// importantly — the partial unique index that is design section 12's
/// "one open performance alert per customer, flock, house, metric, and
/// period" invariant.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('breeder_performance_alerts');
    await db.delete('houses');
    await db.delete('flocks');
    await db.delete('customers');
    await db.insert('customers', {'id': 'customer-1', 'name': 'Test Co.'});
    await db.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
      'flockId': 'BR-2026-01',
      'breed': 'Ross308',
      'entryDate': '2026-01-01T00:00:00.000Z',
      'sectorKey': 'breeder',
    });
    await db.insert('flocks', {
      'id': 'flock-2',
      'customerId': 'customer-1',
      'flockId': 'BR-2026-02',
      'breed': 'Ross308',
      'entryDate': '2026-01-01T00:00:00.000Z',
      'sectorKey': 'breeder',
    });
    await db.insert('houses', {
      'id': 'house-1',
      'flockId': 'flock-1',
      'name': 'House 1',
    });
    await db.insert('houses', {
      'id': 'house-2',
      'flockId': 'flock-2',
      'name': 'House 2',
    });
  });

  Map<String, dynamic> alertRow({
    String id = 'alert-1',
    String flockId = 'flock-1',
    String? houseId,
    String metricCode = 'body_weight_g',
    String periodStart = '2026-08-03T00:00:00.000Z',
    String periodEnd = '2026-08-09T00:00:00.000Z',
    String state = 'new',
  }) {
    const now = '2026-08-10T00:00:00.000Z';
    return {
      'id': id,
      'customerId': 'customer-1',
      'flockId': flockId,
      'houseId': houseId,
      'ruleId': 'rule-body_weight_g-flock-weekly-either',
      'metricCode': metricCode,
      'scope': houseId == null ? 'flock' : 'house',
      'periodType': 'weekly',
      'periodStart': periodStart,
      'periodEnd': periodEnd,
      'actualValue': 320.0,
      'officialTargetValue': 400.0,
      'thresholdIsOfficial': 0,
      'deviationValue': -80.0,
      'severity': 'critical',
      'evidenceReportDatesJson': periodEnd,
      'state': state,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  test('the default alert rules are seeded on a fresh install', () async {
    final db = await DatabaseHelper().db;
    final rows = await db.query('breeder_alert_rules');
    expect(rows, isNotEmpty);
    final codes = rows.map((r) => r['metricCode']).toSet();
    expect(
      codes,
      containsAll([
        'body_weight_g',
        'hen_week_production_pct',
        'liveability_rearing_pct',
        'uniformity_pct',
        'cv_pct',
      ]),
    );
  });

  test('metricCode is restricted to the known vocabulary', () async {
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert('breeder_performance_alerts', alertRow(metricCode: 'not_a_real_metric')),
      throwsA(anything),
    );
  });

  test(
    'at most one OPEN alert per customer/flock/house/metric/period: a '
    'second insert with the same key is rejected while the first stays open',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('breeder_performance_alerts', alertRow());

      await expectLater(
        db.insert(
          'breeder_performance_alerts',
          alertRow(id: 'alert-2'),
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'a closed alert never blocks a fresh open alert for the same key',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert(
        'breeder_performance_alerts',
        alertRow(id: 'alert-1', state: 'closed'),
      );
      // Same customer/flock/house/metric/period, but the prior row is
      // closed, so a fresh open row for the same key is allowed.
      await db.insert(
        'breeder_performance_alerts',
        alertRow(id: 'alert-2', state: 'new'),
      );
      final open = await db.query(
        'breeder_performance_alerts',
        where: "state <> 'closed'",
      );
      expect(open, hasLength(1));
      expect(open.single['id'], 'alert-2');
    },
  );

  test(
    'flock-scope dedupe (houseId NULL) still collides: two NULL houseIds '
    'are not treated as distinct',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('breeder_performance_alerts', alertRow(houseId: null));
      await expectLater(
        db.insert(
          'breeder_performance_alerts',
          alertRow(id: 'alert-2', houseId: null),
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'a house-scope alert for a different flock (different houseId) does '
    'not collide with a flock-scope alert on the same metric/period',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('breeder_performance_alerts', alertRow(houseId: null));
      // Same flock, but scoped to a real house instead: different key.
      await db.insert(
        'breeder_performance_alerts',
        alertRow(id: 'alert-2', houseId: 'house-1'),
      );
      final rows = await db.query('breeder_performance_alerts');
      expect(rows, hasLength(2));
    },
  );

  test(
    'the house-scope guard trigger rejects a house that does not belong '
    'to the alert\'s own flock',
    () async {
      final db = await DatabaseHelper().db;
      await expectLater(
        db.insert(
          'breeder_performance_alerts',
          alertRow(id: 'alert-1', flockId: 'flock-1', houseId: 'house-2'),
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'a house that does belong to the alert\'s flock is accepted',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert(
        'breeder_performance_alerts',
        alertRow(flockId: 'flock-1', houseId: 'house-1'),
      );
      final rows = await db.query('breeder_performance_alerts');
      expect(rows, hasLength(1));
    },
  );
}
