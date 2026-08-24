import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async => useIsolatedAppDatabase());
  tearDown(resetAppDatabase);

  test(
    'v65 backfills deterministic advisory quality without changing data',
    () async {
      final db = await DatabaseHelper().db;
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.insert(
        'chick_weights',
        _row(
          id: 'valid-weight',
          domain: 'chicks.weights',
          scopeType: 'house',
          scopeKey: '{"house":"H1"}',
          sampleKey: 'key-valid',
          values: {'weightsJson': '[40,41]'},
        ),
      );
      await db.insert(
        'chick_weights',
        _row(
          id: 'warn-weight',
          domain: 'chicks.weights',
          scopeType: 'house',
          scopeKey: '{"house":"H2"}',
          sampleKey: 'key-warn',
          values: {'weightsJson': '[0,201]'},
        ),
      );
      await db.insert(
        'chick_quality',
        _row(
          id: 'incomplete-quality',
          domain: 'chicks.legacy_combined',
          scopeType: 'pool',
          scopeKey: '{}',
          sampleKey: 'key-incomplete',
          values: {'pasgarSampleSize': 40},
        ),
      );
      await db.insert(
        'chick_quality',
        _row(
          id: 'malformed-culled-quality',
          domain: 'chicks.culled_analysis',
          scopeType: 'pool',
          scopeKey: '{}',
          sampleKey: 'key-malformed-culled',
          values: {
            'culledChicksTotalEggSet': 100,
            'culledChicksAnalysisJson':
                '[{"id":"sticky_dehydrated_burned_chick"}]',
            'culledChicksAffectedPct': 1.0,
          },
        ),
      );
      await db.insert(
        'chick_quality',
        _row(
          id: 'malformed-quality',
          domain: 'chicks.pasgar',
          scopeType: 'pool',
          scopeKey: '{}',
          sampleKey: 'key-malformed',
          values: {
            'pasgarSampleSize': 20,
            'pasgarReflexesCount': 'not-a-number',
            'pasgarReflexesPct': 5.0,
          },
        ),
      );

      final before = await db.query('chick_weights', orderBy: 'id');
      await DatabaseHelper().applyV65UpgradeForTest(db);
      final after = await db.query('chick_weights', orderBy: 'id');

      expect(after.map((row) => row['id']), before.map((row) => row['id']));
      expect(
        after.map((row) => row['weightsJson']),
        before.map((row) => row['weightsJson']),
      );
      expect(
        after.firstWhere((row) => row['id'] == 'valid-weight')['qualityStatus'],
        'OK',
      );
      final warned = after.firstWhere((row) => row['id'] == 'warn-weight');
      expect(warned['qualityStatus'], 'WARN');
      expect(
        (jsonDecode(warned['qualityFlags']! as String) as List).map(
          (flag) => (flag as Map)['code'],
        ),
        contains('item_out_of_range'),
      );
      final incomplete = (await db.query(
        'chick_quality',
        where: 'id = ?',
        whereArgs: ['incomplete-quality'],
      )).single;
      expect(incomplete['qualityStatus'], 'FLAG');
      expect(
        (jsonDecode(incomplete['qualityFlags']! as String) as List).map(
          (flag) => (flag as Map)['code'],
        ),
        contains('missing_required'),
      );
      final malformed = (await db.query(
        'chick_quality',
        where: 'id = ?',
        whereArgs: ['malformed-quality'],
      )).single;
      expect(malformed['qualityStatus'], 'BLOCK');
      expect(
        (jsonDecode(malformed['qualityFlags']! as String) as List).map(
          (flag) => (flag as Map)['code'],
        ),
        containsAll(['invalid_type', 'derived_cache_mismatch']),
      );
      final malformedCulled = (await db.query(
        'chick_quality',
        where: 'id = ?',
        whereArgs: ['malformed-culled-quality'],
      )).single;
      expect(malformedCulled['qualityStatus'], 'WARN');
      expect(
        (jsonDecode(malformedCulled['qualityFlags']! as String) as List).map(
          (flag) => (flag as Map)['code'],
        ),
        containsAll(['item_required', 'derived_cache_mismatch']),
      );

      final snapshot = await db.query('chick_weights', orderBy: 'id');
      await DatabaseHelper().applyV65UpgradeForTest(db);
      expect(await db.query('chick_weights', orderBy: 'id'), snapshot);
    },
  );
}

Map<String, Object?> _row({
  required String id,
  required String domain,
  required String scopeType,
  required String scopeKey,
  required String sampleKey,
  required Map<String, Object?> values,
}) => {
  'id': id,
  'sessionId': 'session-1',
  'customerId': 'customer-1',
  'date': '2026-08-24',
  'scopeType': scopeType,
  'scopeKey': scopeKey,
  'domain': domain,
  'schemaVersion': 1,
  'replicate': 1,
  'sampleKey': sampleKey,
  'source': 'legacy',
  'captureMethod': 'unknown',
  'createdAt': '2026-08-24T00:00:00.000Z',
  'updatedAt': '2026-08-24T00:00:00.000Z',
  'syncStatus': 'synced',
  ...values,
};
