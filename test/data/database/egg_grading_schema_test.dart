import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/features/audits/models/egg_grading.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test('egg_quality carries the grading summary columns', () async {
    final db = await DatabaseHelper().db;
    final columns = (await db.rawQuery('PRAGMA table_info(egg_quality)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(
      columns.containsAll({
        'gradingSampleSize',
        'gradingRejectedCount',
        'gradingAcceptableCount',
        'gradingRejectedPct',
        'gradingAcceptablePct',
        'gradingDefectsJson',
        'gradingTopDefectCode',
        'gradingTopDefectPct',
      }),
      isTrue,
    );
  });

  test('the defect catalogue is seeded from the Dart catalogue', () async {
    final db = await DatabaseHelper().db;
    final seeded = await db.query('egg_defect_types');
    expect(seeded, hasLength(kEggDefectTypes.length));
    expect(
      seeded.map((row) => row['code']).toSet(),
      kEggDefectTypes.map((d) => d.code).toSet(),
    );
  });

  test('egg_quality_defect_counts exists with its uniqueness rule', () async {
    final db = await DatabaseHelper().db;
    // egg_quality_defect_counts.eggQualityId is FK-enforced (foreign_keys is
    // ON after onOpen), so the full parent chain has to exist first:
    // customers -> hatcheries/flocks -> audit_sessions -> egg_quality.
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'Defect Count Farm',
      'createdAt': '2026-08-23T00:00:00.000Z',
    });
    await db.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-1',
      'customerId': 'customer-1',
      'name': 'Defect Count Hatchery',
    });
    await db.insert('audit_sessions', {
      'id': 'session-1',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-08-23',
    });
    await db.insert('egg_quality', {
      'id': 'eq-1',
      'sessionId': 'session-1',
      'customerId': 'customer-1',
      'date': '2026-08-23',
      'createdAt': '2026-08-23T00:00:00.000Z',
      'updatedAt': '2026-08-23T00:00:00.000Z',
    });
    const base = {
      'id': 'count-1',
      'eggQualityId': 'eq-1',
      'sessionId': 'session-1',
      'customerId': 'customer-1',
      'date': '2026-08-23',
      'defectCode': 'dirty',
      'count': 4,
      'createdAt': '2026-08-23T00:00:00.000Z',
      'updatedAt': '2026-08-23T00:00:00.000Z',
    };
    await db.insert('egg_quality_defect_counts', base);
    expect(
      () => db.insert('egg_quality_defect_counts', {...base, 'id': 'count-2'}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('database version is 62', () async {
    final db = await DatabaseHelper().db;
    expect(await db.getVersion(), 62);
  });
}
