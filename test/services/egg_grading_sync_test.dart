import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

import '../support/test_database.dart';
import 'supabase/startup_sync_harness.dart' as harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(useIsolatedAppDatabase);
  tearDown(resetAppDatabase);

  Future<void> seedDirtyGrading(String suffix) async {
    final now = DateTime.utc(
      2026,
      8,
      23,
      10,
    ).add(Duration(minutes: suffix.length));
    final customerId = 'grading-customer-$suffix';
    final flockId = 'grading-flock-$suffix';
    final hatcheryId = 'grading-hatchery-$suffix';
    final sessionId = 'grading-session-$suffix';
    final eggQualityId = 'grading-egg-quality-$suffix';

    await CustomerRepository().insertCustomer(
      CustomerModel(
        id: customerId,
        name: 'Grading customer $suffix',
        createdAt: now,
        createdBy: 'test',
      ),
    );
    await FlockRepository().insertFlock(
      FlockModel(
        id: flockId,
        customerId: customerId,
        flockId: 'Flock $suffix',
        breed: 'Ross 308',
        entryDate: now,
      ),
    );
    await HatcheryRepository().insertHatchery(
      HatcheryModel(
        id: hatcheryId,
        customerId: customerId,
        name: 'Grading hatchery $suffix',
        createdAt: now,
        createdBy: 'test',
      ),
    );
    await AuditSessionRepository().insertSession(
      AuditSessionModel(
        id: sessionId,
        customerId: customerId,
        flockId: flockId,
        hatcheryId: hatcheryId,
        date: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await PanelSampleRepository().upsertRow(
      tableName: 'egg_quality',
      deriveAggregates: false,
      row: {
        'id': eggQualityId,
        'sessionId': sessionId,
        'customerId': customerId,
        'flockId': flockId,
        'hatcheryId': hatcheryId,
        'date': now.toIso8601String(),
        'sampleMode': 'pool',
        'scopeType': 'pool',
        'sampleLabel': 'Pool',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'syncStatus': 'pending',
        'dirtyAt': now.toIso8601String(),
      },
    );
    await EggGradingRepository().replaceCountsForSample(
      eggQualityId: eggQualityId,
      sessionId: sessionId,
      customerId: customerId,
      flockId: flockId,
      hatcheryId: hatcheryId,
      date: now.toIso8601String(),
      scopeType: 'pool',
      sampleLabel: 'Pool',
      sampleSize: 100,
      counts: const {'dirty': 4},
    );
  }

  test('grading rows are pushed after their panel rows', () async {
    await seedDirtyGrading('push-order');

    await harness.buildService().run();

    final pushedTables = harness.fakeSupabase.upserts.keys.toList();
    expect(pushedTables, isNotEmpty);
    expect(
      pushedTables.indexOf(EggGradingRepository.table),
      greaterThan(pushedTables.indexOf('egg_quality')),
    );
  });

  test('sync metadata is stripped before grading upload', () async {
    await seedDirtyGrading('meta');

    await harness.buildService().run();

    final uploadedRows =
        harness.fakeSupabase.upserts[EggGradingRepository.table];
    expect(uploadedRows, isNotEmpty);
    for (final key in const [
      'syncStatus',
      'dirtyAt',
      'lastSyncedAt',
      'syncError',
    ]) {
      expect(uploadedRows!.first.keys, isNot(contains(key)));
    }
  });

  test('local camelCase grading columns map to snake_case', () {
    final payload = toSupabaseUpsertPayload(EggGradingRepository.table, {
      'id': 'c1',
      'eggQualityId': 'eq-1',
      'defectCode': 'dirty',
      'pctOfSample': 4.0,
    });

    expect(
      payload.keys,
      containsAll(const ['egg_quality_id', 'defect_code', 'pct_of_sample']),
    );
  });

  test(
    'pulls grading rows after panels and includes them in the summary',
    () async {
      await seedDirtyGrading('pull');
      await (await DatabaseHelper().db).delete(
        EggGradingRepository.table,
        where: 'id = ?',
        whereArgs: ['grading-egg-quality-pull:dirty'],
      );
      final service = harness.buildService(
        remoteRows: {
          'egg_quality': [
            {
              'id': 'grading-egg-quality-pull',
              'session_id': 'grading-session-pull',
              'customer_id': 'grading-customer-pull',
              'date': '2026-08-23T10:00:00.000Z',
              'created_at': '2026-08-23T10:00:00.000Z',
              'updated_at': '2026-08-23T10:00:00.000Z',
            },
          ],
          EggGradingRepository.table: [
            {
              'id': 'grading-egg-quality-pull:dirty',
              'egg_quality_id': 'grading-egg-quality-pull',
              'session_id': 'grading-session-pull',
              'customer_id': 'grading-customer-pull',
              'date': '2026-08-23T10:00:00.000Z',
              'defect_code': 'dirty',
              'count': 4,
              'created_at': '2026-08-23T10:00:00.000Z',
              'updated_at': '2026-08-23T10:00:00.000Z',
            },
          ],
        },
      );

      final outcome = await service.run(canPush: false);
      final rows = await (await DatabaseHelper().db).query(
        EggGradingRepository.table,
        where: 'id = ?',
        whereArgs: ['grading-egg-quality-pull:dirty'],
      );

      expect(outcome.pulled, greaterThan(0));
      expect(harness.fakeSupabase.pulledTables, isNotEmpty);
      expect(
        harness.fakeSupabase.pulledTables.indexOf(EggGradingRepository.table),
        greaterThan(harness.fakeSupabase.pulledTables.indexOf('egg_quality')),
      );
      expect(rows, isNotEmpty);
      expect(rows.single['eggQualityId'], 'grading-egg-quality-pull');
      expect(rows.single['syncStatus'], 'synced');
    },
  );

  test('pending grading tombstones are deleted remotely and drained', () async {
    const rowId = 'grading-egg-quality-delete:dirty';
    await SyncTombstoneRepository().queueDelete(
      EggGradingRepository.table,
      rowId,
    );
    expect(await SyncTombstoneRepository().getPendingDeletes(), isNotEmpty);

    await harness.buildService().run();

    expect(harness.fakeSupabase.deletes[EggGradingRepository.table], [rowId]);
    final pending = await SyncTombstoneRepository().getPendingDeletes();
    expect(
      pending.where(
        (tombstone) => tombstone.tableName == EggGradingRepository.table,
      ),
      isEmpty,
    );
  });

  test('grading tombstones are ordered before their egg_quality parent', () {
    final order = SyncTombstoneRepository.deleteOrder;

    expect(order, isNotEmpty);
    expect(order, contains(EggGradingRepository.table));
    expect(
      order.indexOf(EggGradingRepository.table),
      lessThan(order.indexOf('egg_quality')),
    );
  });
}
