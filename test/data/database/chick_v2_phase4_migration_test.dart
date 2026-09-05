import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async => useIsolatedAppDatabase());
  tearDown(resetAppDatabase);

  test('fresh database exposes constrained observation storage', () async {
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
    expect(await db.getVersion(), 81);
    final columns = await db.rawQuery(
      'PRAGMA table_info(chick_quality_observation)',
    );
    expect(
      columns.map((row) => row['name']),
      containsAll(const [
        'id',
        'sampleId',
        'customerId',
        'sessionId',
        'domain',
        'kind',
        'observationKey',
        'ordinal',
        'numericValue',
        'textValue',
        'unit',
        'qualityFlags',
        'source',
        'observedAt',
        'createdAt',
        'updatedAt',
        'syncStatus',
        'dirtyAt',
        'lastSyncedAt',
        'syncError',
      ]),
    );

    await _insertWeightParent(db, id: 'weight-parent');
    await db.insert('chick_quality_observation', _observation());
    await expectLater(
      db.insert('chick_quality_observation', {
        ..._observation(id: 'duplicate-logical'),
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('chick_quality_observation', {
        ..._observation(id: 'two-values', ordinal: 1),
        'textValue': 'forty one',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('chick_quality_observation', {
        ..._observation(id: 'spoofed-owner', ordinal: 2),
        'customerId': 'customer-b',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'v66 preserves parents and backfills only valid exact weights',
    () async {
      final db = await DatabaseHelper().db;
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP TABLE chick_quality_observation');
      await _insertWeightParent(
        db,
        id: 'weight-valid',
        weightsJson: '[41,0,43.5]',
      );
      await _insertWeightParent(
        db,
        id: 'weight-malformed',
        weightsJson: 'not-json',
        sampleKey: 'weight-malformed-key',
      );
      await _insertQualityParent(db, id: 'legacy-quality');
      final parentsBefore = await db.query('chick_weights', orderBy: 'id');

      await DatabaseHelper().applyV66UpgradeForTest(db);

      expect(await db.query('chick_weights', orderBy: 'id'), parentsBefore);
      final observations = await db.query(
        'chick_quality_observation',
        orderBy: 'sampleId, ordinal',
      );
      expect(observations, hasLength(3));
      expect(observations.map((row) => row['sampleId']).toSet(), {
        'weight-valid',
      });
      expect(observations.map((row) => row['numericValue']), [41.0, 0.0, 43.5]);
      expect(
        observations.every((row) => row['syncStatus'] == 'pending'),
        isTrue,
      );
      expect(observations.every((row) => row['dirtyAt'] != null), isTrue);
      expect(
        await db.query(
          'chick_quality_observation',
          where: 'sampleId = ?',
          whereArgs: ['legacy-quality'],
        ),
        isEmpty,
        reason: 'untouched combined rows must not be bulk split or guessed',
      );

      final snapshot = await db.query(
        'chick_quality_observation',
        orderBy: 'id',
      );
      await DatabaseHelper().applyV66UpgradeForTest(db);
      expect(
        await db.query('chick_quality_observation', orderBy: 'id'),
        snapshot,
      );
    },
  );

  test('v66 quarantines a nonempty divergent observation table', () async {
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
    for (final trigger in const [
      'trg_chick_quality_observation_owner_insert',
      'trg_chick_quality_observation_owner_update',
      'trg_chick_quality_observation_identity_update',
      'trg_chick_quality_observation_parent_quality_delete',
      'trg_chick_quality_observation_parent_weights_delete',
      'trg_chick_quality_observation_photo_unlink',
      'trg_photo_observation_owner_insert',
      'trg_photo_observation_owner_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    await db.execute('DROP TABLE chick_quality_observation');
    await db.execute('''CREATE TABLE chick_quality_observation (
      id TEXT PRIMARY KEY,
      sampleId TEXT,
      numericValue REAL
    )''');
    await db.insert('chick_quality_observation', {
      'id': 'divergent-evidence',
      'sampleId': 'unknown-parent',
      'numericValue': 7.0,
    });

    await DatabaseHelper().applyV66UpgradeForTest(db);

    expect(await db.query('chick_quality_observation_v66_quarantine'), [
      {
        'id': 'divergent-evidence',
        'sampleId': 'unknown-parent',
        'numericValue': 7.0,
      },
    ]);
    final columns = await db.rawQuery(
      'PRAGMA table_info(chick_quality_observation)',
    );
    expect(columns.map((row) => row['name']), contains('qualityFlags'));
    expect(await db.query('chick_quality_observation'), isEmpty);
  });
}

Future<void> _insertWeightParent(
  Database db, {
  required String id,
  String weightsJson = '[41]',
  String sampleKey = 'weight-key',
}) {
  return db.insert('chick_weights', {
    'id': id,
    'sessionId': 'session-a',
    'customerId': 'customer-a',
    'date': '2026-08-24',
    'domain': 'chicks.weights',
    'schemaVersion': 1,
    'scopeType': 'pool',
    'scopeKey': '{}',
    'replicate': sampleKey == 'weight-key' ? 1 : 2,
    'sampleKey': sampleKey,
    'source': 'legacy',
    'captureMethod': 'unknown',
    'observedAt': '2026-08-24T05:00:00.000Z',
    'weightsJson': weightsJson,
    'qualityStatus': 'OK',
    'qualityFlags': '[]',
    'createdAt': '2026-08-24T05:00:00.000Z',
    'updatedAt': '2026-08-24T05:00:00.000Z',
    'syncStatus': 'synced',
  });
}

Future<void> _insertQualityParent(Database db, {required String id}) {
  return db.insert('chick_quality', {
    'id': id,
    'sessionId': 'session-a',
    'customerId': 'customer-a',
    'date': '2026-08-24',
    'domain': 'chicks.legacy_combined',
    'schemaVersion': 1,
    'scopeType': 'pool',
    'scopeKey': '{}',
    'replicate': 1,
    'sampleKey': 'legacy-quality-key',
    'source': 'legacy',
    'captureMethod': 'unknown',
    'observedAt': '2026-08-24T05:00:00.000Z',
    'cvtReadingsJson': '[99,100]',
    'qualityStatus': 'OK',
    'qualityFlags': '[]',
    'createdAt': '2026-08-24T05:00:00.000Z',
    'updatedAt': '2026-08-24T05:00:00.000Z',
    'syncStatus': 'synced',
  });
}

Map<String, Object?> _observation({
  String id = 'observation-a',
  int? ordinal,
}) => {
  'id': id,
  'sampleId': 'weight-parent',
  'customerId': 'customer-a',
  'sessionId': 'session-a',
  'domain': 'chicks.weights',
  'kind': 'series',
  'observationKey': 'weightsJson',
  'ordinal': ordinal,
  'numericValue': 41.0,
  'textValue': null,
  'unit': 'grams',
  'qualityFlags': '[]',
  'source': null,
  'observedAt': '2026-08-24T05:00:00.000Z',
  'createdAt': '2026-08-24T05:00:00.000Z',
  'updatedAt': '2026-08-24T05:00:00.000Z',
  'syncStatus': 'pending',
  'dirtyAt': '2026-08-24T05:00:00.000Z',
};
