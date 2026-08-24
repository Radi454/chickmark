import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/chick_sample_identity.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useIsolatedAppDatabase();
  });

  tearDown(resetAppDatabase);

  test(
    'v64 preserves duplicate legacy samples as deterministic replicates',
    () async {
      final db = await DatabaseHelper().db;
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('DROP INDEX IF EXISTS idx_chick_quality_unique_row');
      await db.execute('DROP INDEX IF EXISTS idx_chick_weights_unique_row');

      await db.insert(
        'chick_quality',
        _legacyRow(
          id: 'quality-b',
          createdAt: '2026-08-24T09:01:00.000Z',
          setter: 'Setter A',
          hatcher: 'Hatcher A',
          measurement: const {'pasgarSampleSize': 40},
        ),
      );
      await db.insert(
        'chick_quality',
        _legacyRow(
          id: 'quality-extra-hierarchy',
          createdAt: '2026-08-24T09:02:45.000Z',
          house: 'House X',
          setter: 'Setter X',
          hatcher: 'Hatcher X',
          scopeType: 'house',
          measurement: const {
            'trolley': 'Trolley X',
            'tray': 'Tray X',
            'position': 'Position X',
            'pasgarSampleSize': 7,
          },
        ),
      );
      await db.insert(
        'chick_quality',
        _legacyRow(
          id: 'quality-incomplete',
          createdAt: '2026-08-24T09:02:30.000Z',
          setter: 'Setter B',
          scopeType: 'setter_hatcher',
          measurement: const {'pasgarSampleSize': 5},
        ),
      );
      await db.insert(
        'chick_quality',
        _legacyRow(
          id: 'quality-a',
          createdAt: '2026-08-24T09:00:00.000Z',
          setter: 'Setter A',
          hatcher: 'Hatcher A',
          measurement: const {'pasgarSampleSize': 20},
        ),
      );
      await db.insert(
        'chick_quality',
        _legacyRow(
          id: 'quality-pool',
          createdAt: '2026-08-24T09:02:00.000Z',
          measurement: const {'pasgarSampleSize': 10},
        ),
      );
      await db.insert(
        'chick_weights',
        _legacyRow(
          id: 'weight-b',
          createdAt: '2026-08-24T09:04:00.000Z',
          house: 'House A',
          measurement: const {'weightsJson': '[42.0,43.0]'},
        ),
      );
      await db.insert(
        'chick_weights',
        _legacyRow(
          id: 'weight-extra-hierarchy',
          createdAt: '2026-08-24T09:04:30.000Z',
          house: 'House B',
          setter: 'Ignored Setter',
          scopeType: 'setter_hatcher',
          measurement: const {'weightsJson': '[44.0]'},
        ),
      );
      await db.insert(
        'chick_weights',
        _legacyRow(
          id: 'weight-a',
          createdAt: '2026-08-24T09:03:00.000Z',
          house: 'House A',
          measurement: const {'weightsJson': '[40.0,41.0]'},
        ),
      );

      await DatabaseHelper().applyV64UpgradeForTest(db);

      final quality = {
        for (final row in await db.query('chick_quality'))
          row['id'] as String: row,
      };
      final weights = {
        for (final row in await db.query('chick_weights'))
          row['id'] as String: row,
      };

      expect(quality.keys, {
        'quality-a',
        'quality-b',
        'quality-incomplete',
        'quality-extra-hierarchy',
        'quality-pool',
      });
      expect(weights.keys, {'weight-a', 'weight-b', 'weight-extra-hierarchy'});
      expect(quality['quality-a']!['pasgarSampleSize'], 20);
      expect(quality['quality-b']!['pasgarSampleSize'], 40);
      expect(weights['weight-a']!['weightsJson'], '[40.0,41.0]');
      expect(weights['weight-b']!['weightsJson'], '[42.0,43.0]');

      expect(quality['quality-a']!['domain'], 'chicks.legacy_combined');
      expect(quality['quality-b']!['domain'], 'chicks.legacy_combined');
      expect(quality['quality-pool']!['domain'], 'chicks.legacy_combined');
      expect(weights['weight-a']!['domain'], 'chicks.weights');
      expect(weights['weight-b']!['domain'], 'chicks.weights');
      expect(quality['quality-a']!['schemaVersion'], 1);
      expect(weights['weight-a']!['schemaVersion'], 1);

      const machineScope = '{"hatcher":"Hatcher A","setter":"Setter A"}';
      expect(quality['quality-a']!['scopeType'], 'setter_hatcher');
      expect(quality['quality-a']!['scopeKey'], machineScope);
      expect(quality['quality-a']!['replicate'], 1);
      expect(quality['quality-b']!['replicate'], 2);
      expect(quality['quality-pool']!['scopeType'], 'pool');
      expect(quality['quality-pool']!['scopeKey'], '{}');
      expect(quality['quality-pool']!['replicate'], 1);
      expect(quality['quality-incomplete']!['scopeType'], 'setter_hatcher');
      expect(
        quality['quality-incomplete']!['scopeKey'],
        '{"hatcher":null,"setter":"Setter B"}',
      );
      expect(weights['weight-a']!['scopeType'], 'house');
      expect(weights['weight-a']!['scopeKey'], '{"house":"House A"}');
      expect(weights['weight-a']!['replicate'], 1);
      expect(weights['weight-b']!['replicate'], 2);
      expect(
        quality['quality-extra-hierarchy']!['scopeType'],
        'setter_hatcher',
      );
      expect(
        quality['quality-extra-hierarchy']!['scopeKey'],
        '{"hatcher":"Hatcher X","house":"House X","position":"Position X","setter":"Setter X","tray":"Tray X","trolley":"Trolley X"}',
      );
      expect(weights['weight-extra-hierarchy']!['scopeType'], 'house');
      expect(
        weights['weight-extra-hierarchy']!['scopeKey'],
        '{"house":"House B","setter":"Ignored Setter"}',
      );

      expect(
        quality['quality-a']!['sampleKey'],
        ChickSampleIdentity.buildSampleKey(
          domain: 'chicks.legacy_combined',
          sessionId: 'session-1',
          scopeType: SamplingLayer.setterHatcher,
          scopeKey: machineScope,
          replicate: 1,
        ),
      );
      expect({
        ...quality.values.map((row) => row['sampleKey']),
        ...weights.values.map((row) => row['sampleKey']),
      }, hasLength(8));

      for (final row in [...quality.values, ...weights.values]) {
        expect(row['source'], 'legacy');
        expect(row['captureMethod'], 'unknown');
        expect(row['observedAt'], row['createdAt']);
        expect(row['syncStatus'], 'pending');
      }

      final snapshot = await _identitySnapshot(db);
      await DatabaseHelper().applyV64UpgradeForTest(db);
      expect(await _identitySnapshot(db), snapshot);

      expect(
        await _indexNames(db, 'chick_quality'),
        contains('idx_chick_quality_sample_key'),
      );
      expect(
        await _indexNames(db, 'chick_weights'),
        contains('idx_chick_weights_sample_key'),
      );
      expect(
        await _indexNames(db, 'chick_quality'),
        isNot(contains('idx_chick_quality_unique_row')),
      );
      expect(
        await _indexNames(db, 'chick_weights'),
        isNot(contains('idx_chick_weights_unique_row')),
      );
    },
  );
}

Map<String, Object?> _legacyRow({
  required String id,
  required String createdAt,
  String? house,
  String? setter,
  String? hatcher,
  String? scopeType,
  required Map<String, Object?> measurement,
}) {
  return {
    'id': id,
    'sessionId': 'session-1',
    'customerId': 'customer-1',
    'date': '2026-08-24',
    'house': house,
    'setter': setter,
    'hatcher': hatcher,
    'scopeType': scopeType,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'syncStatus': 'synced',
    ...measurement,
  };
}

Future<List<Map<String, Object?>>> _identitySnapshot(Database db) async {
  final result = <Map<String, Object?>>[];
  for (final table in const ['chick_quality', 'chick_weights']) {
    for (final row in await db.query(table, orderBy: 'id')) {
      result.add({
        'table': table,
        'id': row['id'],
        'domain': row['domain'],
        'schemaVersion': row['schemaVersion'],
        'scopeType': row['scopeType'],
        'scopeKey': row['scopeKey'],
        'replicate': row['replicate'],
        'sampleKey': row['sampleKey'],
        'source': row['source'],
        'captureMethod': row['captureMethod'],
        'observedAt': row['observedAt'],
      });
    }
  }
  return result;
}

Future<Set<String>> _indexNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA index_list($table)');
  return rows.map((row) => row['name'] as String).toSet();
}
