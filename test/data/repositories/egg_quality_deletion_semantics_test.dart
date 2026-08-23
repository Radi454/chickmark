import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/egg_grading_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/data/repositories/sync_tombstone_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late Database db;
  late PanelSampleRepository panelRepository;
  late EggGradingRepository gradingRepository;

  setUp(() async {
    databaseDirectory = await useIsolatedAppDatabase();
    db = await DatabaseHelper().db;
    expect(
      (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
      1,
      reason: 'these regressions must exercise production ON DELETE CASCADE',
    );
    panelRepository = PanelSampleRepository();
    gradingRepository = EggGradingRepository();

    await db.insert('customers', {
      'id': 'customer-delete',
      'name': 'Deletion Farm',
      'createdAt': '2026-08-23T00:00:00.000Z',
    });
    await db.insert('flocks', {
      'id': 'flock-delete',
      'customerId': 'customer-delete',
    });
    await db.insert('hatcheries', {
      'id': 'hatchery-delete',
      'customerId': 'customer-delete',
      'name': 'Deletion Hatchery',
    });
  });

  tearDown(() async {
    await resetAppDatabase();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  Future<void> insertSession(String sessionId) async {
    await db.insert('audit_sessions', {
      'id': sessionId,
      'customerId': 'customer-delete',
      'flockId': 'flock-delete',
      'hatcheryId': 'hatchery-delete',
      'date': '2026-08-23',
    });
  }

  Future<void> insertEggQuality(
    String sessionId,
    String eggQualityId, {
    String? house,
    int? sampleIndex,
  }) async {
    await db.insert('egg_quality', {
      'id': eggQualityId,
      'sessionId': sessionId,
      'customerId': 'customer-delete',
      'flockId': 'flock-delete',
      'hatcheryId': 'hatchery-delete',
      'date': '2026-08-23',
      'house': house,
      'sampleIndex': sampleIndex,
      'createdAt': '2026-08-23T00:00:00.000Z',
      'updatedAt': '2026-08-23T00:00:00.000Z',
    });
  }

  Future<void> saveDirtyCount(
    String sessionId,
    String eggQualityId, {
    int count = 4,
  }) {
    return gradingRepository.replaceCountsForSample(
      eggQualityId: eggQualityId,
      sessionId: sessionId,
      customerId: 'customer-delete',
      flockId: 'flock-delete',
      hatcheryId: 'hatchery-delete',
      date: '2026-08-23',
      scopeType: 'house',
      houseKey: 'H1',
      sampleLabel: 'House 1',
      sampleSize: 100,
      counts: {'dirty': count},
    );
  }

  Future<Set<String>> deletionTombstoneTables(String eggQualityId) async {
    final rows = await db.query(
      'sync_tombstones',
      columns: ['tableName'],
      where:
          '(tableName = ? AND rowId = ?) OR '
          '(tableName = ? AND rowId = ?)',
      whereArgs: [
        'egg_quality_defect_counts',
        '$eggQualityId:dirty',
        'egg_quality',
        eggQualityId,
      ],
    );
    return rows.map((row) => row['tableName'] as String).toSet();
  }

  test(
    'removed-sample and clear paths tombstone children before parents',
    () async {
      await insertSession('session-remove');
      await insertEggQuality('session-remove', 'eq-remove');
      await saveDirtyCount('session-remove', 'eq-remove');

      await panelRepository.deleteRowsBySessionIdForSampleIds(
        'egg_quality',
        'session-remove',
        ['eq-remove'],
      );

      expect(await db.query('egg_quality'), isEmpty);
      expect(await db.query('egg_quality_defect_counts'), isEmpty);
      expect(await deletionTombstoneTables('eq-remove'), {
        'egg_quality_defect_counts',
        'egg_quality',
      });
      expect(
        SyncTombstoneRepository.deleteOrder.indexOf(
          'egg_quality_defect_counts',
        ),
        lessThan(SyncTombstoneRepository.deleteOrder.indexOf('egg_quality')),
      );

      await insertSession('session-clear');
      await insertEggQuality('session-clear', 'eq-clear');
      await saveDirtyCount('session-clear', 'eq-clear');

      await panelRepository.deleteRowsBySessionId(
        'egg_quality',
        'session-clear',
      );

      expect(await deletionTombstoneTables('eq-clear'), {
        'egg_quality_defect_counts',
        'egg_quality',
      });
    },
  );

  test('session deletion tombstones grading children before parents', () async {
    await insertSession('session-delete');
    await insertEggQuality('session-delete', 'eq-session-delete');
    await saveDirtyCount('session-delete', 'eq-session-delete');

    await AuditSessionRepository().deleteSession('session-delete');

    expect(await db.query('egg_quality_defect_counts'), isEmpty);
    expect(await db.query('egg_quality'), isEmpty);
    expect(await deletionTombstoneTables('eq-session-delete'), {
      'egg_quality_defect_counts',
      'egg_quality',
    });
  });

  test(
    'id-keyed prune deletes duplicate and blank hierarchy rows by exact id',
    () async {
      await insertSession('session-prune');
      await insertEggQuality(
        'session-prune',
        'eq-keep-house',
        house: 'H1',
        sampleIndex: 0,
      );
      await insertEggQuality(
        'session-prune',
        'eq-stale-house',
        house: 'H1',
        sampleIndex: 1,
      );
      await insertEggQuality(
        'session-prune',
        'eq-keep-blank',
        house: '',
        sampleIndex: 2,
      );
      await insertEggQuality(
        'session-prune',
        'eq-stale-blank',
        house: '',
        sampleIndex: 3,
      );
      for (final id in const [
        'eq-keep-house',
        'eq-stale-house',
        'eq-keep-blank',
        'eq-stale-blank',
      ]) {
        await saveDirtyCount('session-prune', id);
      }

      await panelRepository.deleteHierarchyRowsBySessionIdExcept(
        'egg_quality',
        'session-prune',
        ['eq-keep-house', 'eq-keep-blank'],
        keepHierarchyRows: const [
          {'house': 'H1'},
          {'house': ''},
        ],
      );

      final parents = await db.query('egg_quality', orderBy: 'sampleIndex ASC');
      expect(parents.map((row) => row['id']), [
        'eq-keep-house',
        'eq-keep-blank',
      ]);
      final children = await db.query(
        'egg_quality_defect_counts',
        orderBy: 'eggQualityId ASC',
      );
      expect(children.map((row) => row['eggQualityId']), [
        'eq-keep-blank',
        'eq-keep-house',
      ]);
      for (final staleId in const ['eq-stale-house', 'eq-stale-blank']) {
        expect(await deletionTombstoneTables(staleId), {
          'egg_quality_defect_counts',
          'egg_quality',
        });
      }
    },
  );

  test(
    're-adding a deterministic count cancels its pending tombstone',
    () async {
      await insertSession('session-resurrect-pending');
      await insertEggQuality(
        'session-resurrect-pending',
        'eq-resurrect-pending',
      );
      await saveDirtyCount('session-resurrect-pending', 'eq-resurrect-pending');
      await gradingRepository.replaceCountsForSample(
        eggQualityId: 'eq-resurrect-pending',
        sessionId: 'session-resurrect-pending',
        customerId: 'customer-delete',
        flockId: 'flock-delete',
        hatcheryId: 'hatchery-delete',
        date: '2026-08-23',
        sampleSize: 100,
        counts: const {},
      );
      await saveDirtyCount(
        'session-resurrect-pending',
        'eq-resurrect-pending',
        count: 7,
      );

      expect(await gradingRepository.countsForSample('eq-resurrect-pending'), {
        'dirty': 7,
      });
      expect(
        await db.query(
          'sync_tombstones',
          where: 'tableName = ? AND rowId = ? AND syncedAt IS NULL',
          whereArgs: [
            'egg_quality_defect_counts',
            'eq-resurrect-pending:dirty',
          ],
        ),
        isEmpty,
      );
    },
  );

  test(
    'a newer local resurrection survives an already-synced tombstone',
    () async {
      await insertSession('session-resurrect-synced');
      await insertEggQuality('session-resurrect-synced', 'eq-resurrect-synced');
      await saveDirtyCount('session-resurrect-synced', 'eq-resurrect-synced');
      await gradingRepository.replaceCountsForSample(
        eggQualityId: 'eq-resurrect-synced',
        sessionId: 'session-resurrect-synced',
        customerId: 'customer-delete',
        flockId: 'flock-delete',
        hatcheryId: 'hatchery-delete',
        date: '2026-08-23',
        sampleSize: 100,
        counts: const {},
      );
      final tombstoneRepository = SyncTombstoneRepository();
      final tombstone = (await tombstoneRepository.getPendingDeletes())
          .singleWhere((row) => row.rowId == 'eq-resurrect-synced:dirty');
      await tombstoneRepository.markSynced(tombstone.id);
      await saveDirtyCount(
        'session-resurrect-synced',
        'eq-resurrect-synced',
        count: 8,
      );

      await tombstoneRepository.applyRemoteDeletes();

      expect(await gradingRepository.countsForSample('eq-resurrect-synced'), {
        'dirty': 8,
      });
    },
  );
}
