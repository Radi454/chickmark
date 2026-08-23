import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(resetAppDatabase);

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'fresh v61 database preserves the performance monitoring contract',
    () async {
      final db = await DatabaseHelper().db;

      expect(await _userVersion(db), 61);
      expect(
        await _tableNames(db),
        containsAll(const <String>[
          'customer_sectors',
          'farms',
          'houses',
          'flock_placements',
          'broiler_daily_records',
          'broiler_daily_record_revisions',
          'daily_record_sources',
          'broiler_daily_events',
          'broiler_target_profiles',
          'broiler_target_rows',
          'performance_alert_rules',
          'performance_concerns',
          'farm_visit_sessions',
          'farm_visit_houses',
          'visit_investigations',
          'visit_findings',
          'cause_assessments',
          'corrective_actions',
          'action_kpi_evaluations',
        ]),
      );
      expect(
        await _columnNames(db, 'flocks'),
        containsAll(const [
          'farmId',
          'sectorKey',
          'sexProfile',
          'targetProfileId',
          'productionPhase',
        ]),
      );
      expect(
        await _indexNames(db),
        containsAll(const [
          'idx_customer_sectors_unique',
          'idx_broiler_daily_records_placement_date',
          'idx_broiler_target_rows_profile_age',
          'idx_active_placement_per_house',
        ]),
      );
    },
  );

  test('one house cannot have two active flock placements', () async {
    final db = await DatabaseHelper().db;
    await db.insert('customers', {'id': 'customer-1', 'name': 'Customer'});
    await db.insert('customer_sectors', {
      'id': 'sector-1',
      'customerId': 'customer-1',
      'sectorKey': 'broiler',
      'isActive': 1,
    });
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
    for (final flockId in const ['flock-1', 'flock-2']) {
      await db.insert('flocks', {
        'id': flockId,
        'customerId': 'customer-1',
        'flockId': flockId,
        'farmId': 'farm-1',
        'sectorKey': 'broiler',
      });
    }
    await db.insert('flock_placements', {
      'id': 'placement-1',
      'flockId': 'flock-1',
      'houseId': 'house-1',
      'placedBirds': 10000,
      'placedAt': '2026-07-01',
      'status': 'active',
    });

    await expectLater(
      db.insert('flock_placements', {
        'id': 'placement-2',
        'flockId': 'flock-2',
        'houseId': 'house-1',
        'placedBirds': 9000,
        'placedAt': '2026-07-02',
        'status': 'active',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('one placement has only one logical record per date', () async {
    final db = await DatabaseHelper().db;
    await db.insert('customers', {'id': 'customer-2', 'name': 'Customer'});
    await db.insert('farms', {
      'id': 'farm-2',
      'customerId': 'customer-2',
      'sectorKey': 'broiler',
      'name': 'Farm',
    });
    await db.insert('houses', {
      'id': 'house-2',
      'farmId': 'farm-2',
      'name': 'House 2',
    });
    await db.insert('flocks', {
      'id': 'flock-3',
      'customerId': 'customer-2',
      'flockId': 'flock-3',
      'farmId': 'farm-2',
      'sectorKey': 'broiler',
    });
    await db.insert('flock_placements', {
      'id': 'placement-3',
      'flockId': 'flock-3',
      'houseId': 'house-2',
      'placedBirds': 8000,
      'placedAt': '2026-07-01',
      'status': 'active',
    });
    await db.insert('broiler_daily_records', {
      'id': 'record-1',
      'placementId': 'placement-3',
      'recordDate': '2026-07-24',
      'verificationStatus': 'entered',
    });

    await expectLater(
      db.insert('broiler_daily_records', {
        'id': 'record-2',
        'placementId': 'placement-3',
        'recordDate': '2026-07-24',
        'verificationStatus': 'entered',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.single['user_version']! as int;
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name']! as String).toSet();
}

Future<Set<String>> _indexNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}
