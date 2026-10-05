import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

Future<Set<String>> _columns(Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toSet();

Future<void> _insertSession(Database db, String suffix) async {
  await db.insert('customers', {
    'id': 'customer-$suffix',
    'name': 'Schema test',
  });
  await db.insert('flocks', {
    'id': 'flock-$suffix',
    'customerId': 'customer-$suffix',
  });
  await db.insert('hatcheries', {
    'id': 'hatchery-$suffix',
    'customerId': 'customer-$suffix',
    'name': 'Schema test hatchery',
  });
  await db.insert('audit_sessions', {
    'id': 'session-$suffix',
    'customerId': 'customer-$suffix',
    'flockId': 'flock-$suffix',
    'hatcheryId': 'hatchery-$suffix',
    'date': '2026-10-05',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);
  tearDown(resetAppDatabase);

  test(
    'fresh database creates sampling state, nodes, and reservations',
    () async {
      await useIsolatedAppDatabase();
      final db = await DatabaseHelper().db;
      final version = (await db.rawQuery('PRAGMA user_version')).single;
      expect(version['user_version'], 82);

      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((row) => row['name']).toSet();
      expect(
        tables,
        containsAll([
          'panel_sampling_states',
          'panel_sampling_nodes',
          'panel_sample_serial_reservations',
        ]),
      );

      expect(
        await _columns(db, 'panel_sampling_states'),
        containsAll([
          'id',
          'sessionId',
          'panelKey',
          'serialHighWatermark',
          'createdAt',
          'updatedAt',
          'syncStatus',
          'dirtyAt',
          'lastSyncedAt',
          'syncError',
        ]),
      );
      expect(
        await _columns(db, 'panel_sampling_nodes'),
        containsAll([
          'id',
          'sessionId',
          'panelKey',
          'parentId',
          'level',
          'identityKey',
          'identityJson',
          'sampleId',
          'sampleNumber',
          'isTerminal',
          'createdAt',
          'updatedAt',
          'syncStatus',
          'dirtyAt',
          'lastSyncedAt',
          'syncError',
        ]),
      );
      expect(
        await _columns(db, 'panel_sample_serial_reservations'),
        containsAll([
          'id',
          'sessionId',
          'panelKey',
          'sampleNumber',
          'sampleId',
          'createdAt',
          'syncStatus',
          'dirtyAt',
          'lastSyncedAt',
          'syncError',
        ]),
      );
      for (final table in [
        'egg_storage',
        'egg_quality',
        'chick_quality',
        'chick_weights',
        'fresh_egg_breakout',
        'candled_egg_breakout',
        'residue_breakout',
        'setter_optimizing',
        'hatcher_optimizing',
      ]) {
        expect(
          await _columns(db, table),
          containsAll(['sampleId', 'sampleNumber', 'samplingPathJson']),
          reason: '$table stores sampling identity alongside its measurements',
        );
      }
      expect(await _columns(db, 'customers'), contains('samplingCode'));
      expect(await _columns(db, 'hatcheries'), contains('samplingCode'));
      expect(await _columns(db, 'flocks'), contains('samplingCode'));
    },
  );

  test(
    'same-parent identity is unique while offline serial collisions persist',
    () async {
      await useIsolatedAppDatabase();
      final db = await DatabaseHelper().db;
      final now = DateTime.utc(2026, 10, 5).toIso8601String();
      await db.insert('panel_sampling_nodes', {
        'id': 'node-a',
        'sessionId': 'session-a',
        'panelKey': 'breakout.candled',
        'parentId': '',
        'level': 'house',
        'identityKey': 'house-1',
        'isTerminal': 0,
        'createdAt': now,
        'updatedAt': now,
      });
      expect(
        () => db.insert('panel_sampling_nodes', {
          'id': 'node-b',
          'sessionId': 'session-a',
          'panelKey': 'breakout.candled',
          'parentId': '',
          'level': 'house',
          'identityKey': 'house-1',
          'isTerminal': 0,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(isA<DatabaseException>()),
      );

      await db.insert('panel_sample_serial_reservations', {
        'id': 'reservation-a',
        'sessionId': 'session-a',
        'panelKey': 'breakout.candled',
        'sampleNumber': 4,
        'sampleId': 'sample-a',
        'createdAt': now,
      });
      await db.insert('panel_sample_serial_reservations', {
        'id': 'reservation-b',
        'sessionId': 'session-a',
        'panelKey': 'breakout.candled',
        'sampleNumber': 4,
        'sampleId': 'sample-b',
        'createdAt': now,
      });
      await db.insert('panel_sampling_nodes', {
        'id': 'terminal-a',
        'sessionId': 'session-a',
        'panelKey': 'breakout.candled',
        'parentId': 'house-a',
        'level': 'tray',
        'sampleId': 'sample-a',
        'sampleNumber': 4,
        'isTerminal': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      await db.insert('panel_sampling_nodes', {
        'id': 'terminal-b',
        'sessionId': 'session-a',
        'panelKey': 'breakout.candled',
        'parentId': 'house-b',
        'level': 'tray',
        'sampleId': 'sample-b',
        'sampleNumber': 4,
        'isTerminal': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      await db.delete(
        'panel_sampling_nodes',
        where: 'id = ?',
        whereArgs: ['terminal-a'],
      );
      expect(await db.query('panel_sample_serial_reservations'), hasLength(2));
      expect(
        await db.query(
          'panel_sample_serial_reservations',
          where: 'sampleId = ?',
          whereArgs: ['sample-a'],
        ),
        hasLength(1),
        reason: 'deleting a node does not release its consumed serial',
      );
    },
  );

  test(
    'v81 upgrade preserves existing measurement identity and values',
    () async {
      await useIsolatedAppDatabase();
      final db = await DatabaseHelper().db;
      await _insertSession(db, 'legacy');
      final row = {
        'id': 'legacy-panel-row',
        'sessionId': 'session-legacy',
        'customerId': 'customer-legacy',
        'date': '2026-10-05',
        'house': 'House 7',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
        'syncStatus': 'synced',
      };
      await db.insert('egg_quality', row);
      for (final table in [
        'panel_sampling_states',
        'panel_sampling_nodes',
        'panel_sample_serial_reservations',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      for (final column in ['sampleId', 'sampleNumber', 'samplingPathJson']) {
        await db.execute('ALTER TABLE egg_quality DROP COLUMN $column');
      }
      await db.setVersion(81);
      await DatabaseHelper().close();
      final upgradedDb = await DatabaseHelper().db;

      final preserved = (await upgradedDb.query(
        'egg_quality',
        where: 'id = ?',
        whereArgs: ['legacy-panel-row'],
      )).single;
      expect(preserved['house'], 'House 7');
      expect(preserved['syncStatus'], 'synced');
      expect(preserved['sampleId'], isNull);
      expect(preserved['sampleNumber'], isNull);
      expect(
        (await upgradedDb.query(
          'egg_quality',
          where: 'id = ?',
          whereArgs: ['legacy-panel-row'],
        )),
        hasLength(1),
      );
      expect(
        await _columns(upgradedDb, 'panel_sampling_states'),
        contains('serialHighWatermark'),
      );
    },
  );

  test(
    'opening repairs missing sampling tables and panel columns in place',
    () async {
      await useIsolatedAppDatabase();
      var db = await DatabaseHelper().db;
      await _insertSession(db, 'repair');
      await db.insert('egg_quality', {
        'id': 'repair-row',
        'sessionId': 'session-repair',
        'customerId': 'customer-repair',
        'date': '2026-10-05',
        'house': 'House 2',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
      await db.execute('DROP TABLE panel_sampling_nodes');
      await db.execute('ALTER TABLE egg_quality DROP COLUMN samplingPathJson');
      await DatabaseHelper().close();
      db = await DatabaseHelper().db;

      expect(await _columns(db, 'panel_sampling_nodes'), contains('id'));
      expect(await _columns(db, 'egg_quality'), contains('samplingPathJson'));
      final repaired = (await db.query(
        'egg_quality',
        where: 'id = ?',
        whereArgs: ['repair-row'],
      )).single;
      expect(repaired['house'], 'House 2');
    },
  );

  test('separate sampled rows may share the same physical hierarchy', () async {
    await useIsolatedAppDatabase();
    final db = await DatabaseHelper().db;
    await _insertSession(db, 'duplicate-path');
    for (final sampleId in ['sample-a', 'sample-b']) {
      await db.insert('residue_breakout', {
        'id': 'row-$sampleId',
        'sampleId': sampleId,
        'sampleNumber': sampleId == 'sample-a' ? 1 : 2,
        'sessionId': 'session-duplicate-path',
        'customerId': 'customer-duplicate-path',
        'date': '2026-10-05',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      });
    }
    await db.insert('residue_breakout', {
      'id': 'legacy-row-a',
      'sessionId': 'session-duplicate-path',
      'customerId': 'customer-duplicate-path',
      'date': '2026-10-05',
      'createdAt': '2026-10-05T00:00:00.000Z',
      'updatedAt': '2026-10-05T00:00:00.000Z',
    });
    expect(
      () => db.insert('residue_breakout', {
        'id': 'legacy-row-b',
        'sessionId': 'session-duplicate-path',
        'customerId': 'customer-duplicate-path',
        'date': '2026-10-05',
        'createdAt': '2026-10-05T00:00:00.000Z',
        'updatedAt': '2026-10-05T00:00:00.000Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('residue_breakout'), hasLength(3));
  });
}
