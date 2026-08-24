import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';

import '../../support/test_database.dart';
import 'startup_sync_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useIsolatedAppDatabase();
    final db = await DatabaseHelper().db;
    await db.execute('PRAGMA foreign_keys = OFF');
  });
  tearDown(resetAppDatabase);

  test('sync pushes Chick parents before their raw observations', () async {
    await PanelSampleRepository().upsertRow(
      tableName: 'chick_weights',
      row: {
        'id': 'weight-sync',
        'sessionId': 'session-sync',
        'customerId': 'customer-sync',
        'date': '2026-08-24',
        'domain': 'chicks.weights',
        'schemaVersion': 1,
        'scopeType': 'pool',
        'scopeKey': '{}',
        'replicate': 1,
        'sampleKey': 'weight-sync-key',
        'source': 'human',
        'captureMethod': 'manual',
        'observedAt': '2026-08-24T05:00:00.000Z',
        'weightsJson': '[41,42]',
        'createdAt': '2026-08-24T05:00:00.000Z',
        'updatedAt': '2026-08-24T05:00:00.000Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-08-24T05:00:00.000Z',
      },
    );

    final service = buildService();
    await service.run();

    expect(fakeSupabase.upsertOrder, contains('chick_weights'));
    expect(fakeSupabase.upsertOrder, contains('chick_quality_observation'));
    expect(
      fakeSupabase.upsertOrder.indexOf('chick_weights'),
      lessThan(fakeSupabase.upsertOrder.indexOf('chick_quality_observation')),
    );
    final pushed = fakeSupabase.upserts['chick_quality_observation']!;
    expect(pushed, hasLength(2));
    expect(pushed.first['syncStatus'], isNull);
    expect(pushed.first['sampleId'], 'weight-sync');
  });

  test('observation tombstones delete before either Chick parent', () {
    final order = SyncTombstoneRepository.deleteOrder;
    expect(
      order.indexOf('chick_quality_observation'),
      lessThan(order.indexOf('chick_quality')),
    );
    expect(
      order.indexOf('chick_quality_observation'),
      lessThan(order.indexOf('chick_weights')),
    );
  });

  test(
    'pull-only sync applies parents before observation-first children',
    () async {
      await PanelSampleRepository().upsertRow(
        tableName: 'chick_weights',
        row: {
          'id': 'remote-weight',
          'sessionId': 'session-remote',
          'customerId': 'customer-remote',
          'date': '2026-08-24',
          'domain': 'chicks.weights',
          'schemaVersion': 1,
          'scopeType': 'pool',
          'scopeKey': '{}',
          'replicate': 1,
          'sampleKey': 'remote-weight-key',
          'source': 'human',
          'captureMethod': 'manual',
          'observedAt': '2026-08-24T05:00:00.000Z',
          'weightsJson': '[99]',
          'createdAt': '2026-08-24T05:00:00.000Z',
          'updatedAt': '2026-08-24T06:00:00.000Z',
          'syncStatus': 'pending',
          'dirtyAt': '2026-08-24T06:00:00.000Z',
        },
      );
      final db = await DatabaseHelper().db;
      final existingObservationId =
          (await db.query(
                'chick_quality_observation',
                columns: ['id'],
                where: 'sampleId = ? AND domain = ?',
                whereArgs: ['remote-weight', 'chicks.weights'],
              )).single['id']!
              as String;
      final service = buildService(
        remoteRows: {
          'chick_weights': [
            {
              'id': 'remote-weight',
              'session_id': 'session-remote',
              'customer_id': 'customer-remote',
              'date': '2026-08-24',
              'domain': 'chicks.weights',
              'schema_version': 1,
              'scope_type': 'pool',
              'scope_key': '{}',
              'replicate': 1,
              'sample_key': 'remote-weight-key',
              'source': 'human',
              'capture_method': 'manual',
              'observed_at': '2026-08-24T05:00:00.000Z',
              'weights_json': '[999]',
              'quality_status': 'FLAG',
              'quality_flags': '[]',
              'created_at': '2026-08-24T05:00:00.000Z',
              'updated_at': '2999-08-24T05:00:00.000Z',
            },
          ],
          'chick_quality_observation': [
            {
              'id': existingObservationId,
              'sample_id': 'remote-weight',
              'customer_id': 'customer-remote',
              'session_id': 'session-remote',
              'domain': 'chicks.weights',
              'kind': 'series',
              'observation_key': 'weightsJson',
              'ordinal': 0,
              'numeric_value': 42.0,
              'text_value': null,
              'unit': 'grams',
              'quality_flags': '[]',
              'source': null,
              'observed_at': '2026-08-24T05:00:00.000Z',
              'created_at': '2026-08-24T05:00:00.000Z',
              'updated_at': '2999-08-24T05:01:00.000Z',
            },
          ],
        },
      );

      await service.run(canPush: false);

      expect(fakeSupabase.pulledTables, [
        'chick_weights',
        'chick_quality_observation',
      ]);
      final rows = await PanelSampleRepository().getRowsBySessionId(
        'chick_weights',
        'session-remote',
      );
      expect(rows.single['weightsJson'], '[42.0]');
      expect(rows.single['avgWeight'], 42.0);
    },
  );
}
