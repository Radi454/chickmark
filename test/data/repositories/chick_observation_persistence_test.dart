import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/chick_quality_observation_repository.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PanelSampleRepository repository;

  setUp(() async {
    await useIsolatedAppDatabase();
    repository = PanelSampleRepository();
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
  });
  tearDown(resetAppDatabase);

  test(
    'weight writes replace observations and reads ignore corrupt caches',
    () async {
      await repository.upsertRow(
        tableName: 'chick_weights',
        row: _weightRow(weightsJson: '[40,60]'),
      );
      final db = await DatabaseHelper().db;
      expect(
        await db.query(
          'chick_quality_observation',
          where: 'sampleId = ?',
          whereArgs: ['weight-a'],
          orderBy: 'ordinal',
        ),
        hasLength(2),
      );

      await db.update(
        'chick_weights',
        {'weightsJson': '[999]', 'avgWeight': 999.0, 'sampleSize': 1},
        where: 'id = ?',
        whereArgs: ['weight-a'],
      );
      final observationFirst = await repository.getRowsBySessionId(
        'chick_weights',
        'session-a',
      );
      expect(observationFirst.single['weightsJson'], '[40.0,60.0]');
      expect(observationFirst.single['avgWeight'], 50.0);
      expect(observationFirst.single['sampleSize'], 2);

      await repository.upsertRow(
        tableName: 'chick_weights',
        row: _weightRow(weightsJson: '[50]'),
      );
      final observations = await db.query(
        'chick_quality_observation',
        where: 'sampleId = ?',
        whereArgs: ['weight-a'],
        orderBy: 'ordinal',
      );
      expect(observations, hasLength(1));
      expect(observations.single['numericValue'], 50.0);
      expect(
        await db.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId LIKE ?',
          whereArgs: ['chick_quality_observation', '%'],
        ),
        hasLength(1),
        reason: 'the removed second reading must be remotely deleted first',
      );
    },
  );

  test(
    'legacy combined writes lazily create only touched domains once',
    () async {
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: _qualityRow(
          values: {
            'cvtReadingsJson': '[99,100]',
            'yfbmEntriesJson': '[{"chickWeight":42,"yolkWeight":4.5}]',
          },
        ),
      );
      final db = await DatabaseHelper().db;
      final firstParents = await db.query('chick_quality', orderBy: 'domain');
      expect(firstParents.map((row) => row['domain']).toSet(), {
        'chicks.legacy_combined',
        'chicks.cvt',
        'chicks.yfbm',
      });
      expect(
        firstParents
            .where((row) => row['domain'] != 'chicks.legacy_combined')
            .every(
              (row) =>
                  row['sourceRefId'] ==
                  'legacy-domain:quality-a:${row['domain']}',
            ),
        isTrue,
      );
      final helperIds = firstParents
          .where((row) => row['domain'] != 'chicks.legacy_combined')
          .map((row) => row['id'])
          .toSet();
      final helper = firstParents.firstWhere(
        (row) => row['domain'] == 'chicks.cvt',
      );
      expect(
        (await repository.getRowById(
          'chick_quality',
          helper['id']! as String,
        ))?['cvtReadingsJson'],
        '[99.0,100.0]',
        reason: 'sync conflict reads must not hide exact-domain helpers',
      );

      await repository.upsertRow(
        tableName: 'chick_quality',
        row: _qualityRow(
          values: {
            'cvtReadingsJson': '[101]',
            'yfbmEntriesJson': '[{"chickWeight":44,"yolkWeight":4.0}]',
          },
        ),
      );
      final secondParents = await db.query('chick_quality');
      expect(secondParents, hasLength(3));
      expect(
        secondParents
            .where((row) => row['domain'] != 'chicks.legacy_combined')
            .map((row) => row['id'])
            .toSet(),
        helperIds,
      );

      await db.update(
        'chick_quality',
        {'cvtReadingsJson': '[1]', 'cvtAvgTemp': 1.0},
        where: 'id = ?',
        whereArgs: ['quality-a'],
      );
      final visible = await repository.getRowsBySessionId(
        'chick_quality',
        'session-a',
      );
      expect(
        visible,
        hasLength(1),
        reason: 'helper parents are not UI replicates',
      );
      expect(visible.single['id'], 'quality-a');
      expect(visible.single['cvtReadingsJson'], '[101.0]');
      expect(visible.single['cvtAvgTemp'], 101.0);
      expect(visible.single['yfbmEntryCount'], 1);
    },
  );

  test('BLOCK failure rolls back both parent and observation rows', () async {
    await expectLater(
      repository.upsertRow(
        tableName: 'chick_weights',
        row: {
          ..._weightRow(weightsJson: '[40]'),
          'domain': 'chicks.cvt',
        },
      ),
      throwsA(isA<StateError>()),
    );
    final db = await DatabaseHelper().db;
    expect(await db.query('chick_weights'), isEmpty);
    expect(await db.query('chick_quality_observation'), isEmpty);
  });

  test(
    'malformed legacy evidence remains cached and is never guessed',
    () async {
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: _qualityRow(
          values: const {'culledChicksAnalysisJson': '[{"id":"weak"}]'},
        ),
      );
      final db = await DatabaseHelper().db;
      final legacy = (await db.query(
        'chick_quality',
        where: 'id = ?',
        whereArgs: ['quality-a'],
      )).single;
      expect(legacy['culledChicksAnalysisJson'], '[{"id":"weak"}]');
      expect(await db.query('chick_quality_observation'), isEmpty);
    },
  );

  test(
    'malformed exact-domain update rejects and preserves observations',
    () async {
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: _qualityRow(
          domain: 'chicks.yfbm',
          values: const {
            'yfbmEntriesJson': '[{"chickWeight":42,"yolkWeight":4.5}]',
          },
        ),
      );
      final db = await DatabaseHelper().db;
      final before = await db.query(
        'chick_quality_observation',
        where: 'sampleId = ? AND domain = ?',
        whereArgs: ['quality-a', 'chicks.yfbm'],
        orderBy: 'observationKey, ordinal',
      );

      await expectLater(
        repository.upsertRow(
          tableName: 'chick_quality',
          row: _qualityRow(
            domain: 'chicks.yfbm',
            values: const {'yfbmEntriesJson': '[{"chickWeight":99}]'},
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final after = await db.query(
        'chick_quality_observation',
        where: 'sampleId = ? AND domain = ?',
        whereArgs: ['quality-a', 'chicks.yfbm'],
        orderBy: 'observationKey, ordinal',
      );
      expect(
        after.map((row) => [row['id'], row['numericValue']]),
        before.map((row) => [row['id'], row['numericValue']]),
      );
      expect(
        await db.query(
          'sync_tombstones',
          where: 'tableName = ?',
          whereArgs: ['chick_quality_observation'],
        ),
        isEmpty,
      );
      final visible = await repository.getRowsBySessionId(
        'chick_quality',
        'session-a',
      );
      expect(
        visible.single['yfbmEntriesJson'],
        '[{"chickWeight":42.0,"yolkWeight":4.5}]',
      );
    },
  );

  test(
    'registry-owned photos move once and keep an exact observation link',
    () async {
      final db = await DatabaseHelper().db;
      await db.insert('photos', {
        'id': 'photo-a',
        'filePath': '/tmp/evidence.jpg',
        'createdAt': '2026-08-24T05:00:00.000Z',
        'sessionId': 'session-a',
        'panelName': 'chick_quality',
        'panelRowId': 'quality-a',
        'fieldKey': 'pasgarReflexesPhoto',
        'uploadStatus': 'synced',
      });
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: _qualityRow(
          values: const {'pasgarSampleSize': 10, 'pasgarReflexesCount': 1},
        ),
      );
      final helper = (await db.query(
        'chick_quality',
        where: 'domain = ?',
        whereArgs: ['chicks.pasgar'],
      )).single;
      final photo = (await db.query('photos')).single;
      expect(photo['panelRowId'], helper['id']);
      expect(photo['observationId'], isNotNull);
      expect(photo['uploadStatus'], 'metadata_pending');
      expect(
        await db.query(
          'chick_quality_observation',
          where: 'id = ?',
          whereArgs: [photo['observationId']],
        ),
        hasLength(1),
      );
      await db.delete(
        'chick_quality_observation',
        where: 'id = ?',
        whereArgs: [photo['observationId']],
      );
      expect((await db.query('photos')).single['observationId'], isNull);
    },
  );

  test('observation sync acknowledgement respects the dirty cutoff', () async {
    await repository.upsertRow(
      tableName: 'chick_weights',
      row: _weightRow(weightsJson: '[40]'),
    );
    final observations = ChickQualityObservationRepository();
    final dirty = await observations.getDirtyRows();
    final id = dirty.single['id']! as String;
    final db = await DatabaseHelper().db;
    await db.update(
      'chick_quality_observation',
      {
        'numericValue': 41.0,
        'dirtyAt': '2999-01-01T00:00:00.000Z',
        'syncStatus': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await observations.markRowsSynced([id]);
    final row = (await db.query(
      'chick_quality_observation',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['syncStatus'], 'pending');
    expect(row['numericValue'], 41.0);
  });

  test(
    'same parent id in quality and weights keeps both observation domains',
    () async {
      await repository.upsertRow(
        tableName: 'chick_weights',
        row: _weightRow(id: 'shared-id', weightsJson: '[40]'),
      );
      await repository.upsertRow(
        tableName: 'chick_quality',
        row: _qualityRow(
          id: 'shared-id',
          domain: 'chicks.pasgar',
          values: const {'pasgarSampleSize': 10, 'pasgarReflexesCount': 1},
        ),
      );

      final db = await DatabaseHelper().db;
      final rows = await db.query(
        'chick_quality_observation',
        where: 'sampleId = ?',
        whereArgs: ['shared-id'],
      );
      expect(rows.map((row) => row['domain']).toSet(), {
        'chicks.weights',
        'chicks.pasgar',
      });
      expect(rows.map((row) => row['id']).toSet(), hasLength(rows.length));

      await repository.upsertRow(
        tableName: 'chick_weights',
        row: _weightRow(id: 'shared-id', weightsJson: '[41]'),
      );
      expect(
        await db.query(
          'chick_quality_observation',
          where: 'sampleId = ? AND domain = ?',
          whereArgs: ['shared-id', 'chicks.pasgar'],
        ),
        isNotEmpty,
      );

      await repository.deleteRow('chick_weights', 'shared-id');
      expect(
        await db.query(
          'chick_quality_observation',
          where: 'sampleId = ?',
          whereArgs: ['shared-id'],
        ),
        everyElement(containsPair('domain', 'chicks.pasgar')),
      );
    },
  );

  test(
    'remote logical-id collision is blocked without replacing local data',
    () async {
      await repository.upsertRow(
        tableName: 'chick_weights',
        row: _weightRow(weightsJson: '[40]'),
      );
      final db = await DatabaseHelper().db;
      final local = (await db.query('chick_quality_observation')).single;
      await expectLater(
        ChickQualityObservationRepository().upsertRemoteRow({
          ...local,
          'id': 'different-id-for-same-logical-observation',
        }),
        throwsA(isA<StateError>()),
      );
      final preserved = await db.query('chick_quality_observation');
      expect(preserved, hasLength(1));
      expect(preserved.single['id'], local['id']);
      expect(preserved.single['numericValue'], 40.0);
    },
  );

  test('registry-invalid remote observation is rejected', () async {
    await repository.upsertRow(
      tableName: 'chick_weights',
      row: _weightRow(weightsJson: '[40]'),
    );
    final db = await DatabaseHelper().db;
    final local = (await db.query('chick_quality_observation')).single;
    await db.delete('chick_quality_observation');

    await expectLater(
      ChickQualityObservationRepository().upsertRemoteRow({
        ...local,
        'unit': 'fahrenheit',
      }),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('chick_quality_observation'), isEmpty);
  });

  test('quality photo cannot reference a weight observation', () async {
    await repository.upsertRow(
      tableName: 'chick_weights',
      row: _weightRow(weightsJson: '[40]'),
    );
    final db = await DatabaseHelper().db;
    final observationId =
        (await db.query('chick_quality_observation')).single['id']! as String;
    await expectLater(
      db.insert('photos', {
        'id': 'wrong-domain-photo',
        'filePath': '/tmp/wrong-domain.jpg',
        'createdAt': '2026-08-24T05:00:00.000Z',
        'sessionId': 'session-a',
        'panelName': 'chick_quality',
        'panelRowId': 'weight-a',
        'fieldKey': 'evidence',
        'uploadStatus': 'local',
        'observationId': observationId,
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('photos'), isEmpty);
  });
}

Map<String, Object?> _weightRow({
  String id = 'weight-a',
  required String weightsJson,
}) => {
  'id': id,
  'sessionId': 'session-a',
  'customerId': 'customer-a',
  'date': '2026-08-24',
  'domain': 'chicks.weights',
  'schemaVersion': 1,
  'scopeType': 'pool',
  'scopeKey': '{}',
  'replicate': 1,
  'sampleKey': 'weight-key',
  'source': 'human',
  'captureMethod': 'manual',
  'observedAt': '2026-08-24T05:00:00.000Z',
  'weightsJson': weightsJson,
  'createdAt': '2026-08-24T05:00:00.000Z',
  'updatedAt': '2026-08-24T05:00:00.000Z',
  'syncStatus': 'pending',
  'dirtyAt': '2026-08-24T05:00:00.000Z',
};

Map<String, Object?> _qualityRow({
  String id = 'quality-a',
  String domain = 'chicks.legacy_combined',
  required Map<String, Object?> values,
}) => {
  'id': id,
  'sessionId': 'session-a',
  'customerId': 'customer-a',
  'date': '2026-08-24',
  'domain': domain,
  'schemaVersion': 1,
  'scopeType': 'pool',
  'scopeKey': '{}',
  'replicate': 1,
  'sampleKey': 'quality-key',
  'source': 'human',
  'captureMethod': 'manual',
  'observedAt': '2026-08-24T05:00:00.000Z',
  'createdAt': '2026-08-24T05:00:00.000Z',
  'updatedAt': '2026-08-24T05:00:00.000Z',
  'syncStatus': 'pending',
  'dirtyAt': '2026-08-24T05:00:00.000Z',
  ...values,
};
