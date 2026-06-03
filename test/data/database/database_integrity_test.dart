import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(_resetDatabase);

  tearDown(() async {
    await DatabaseHelper().close();
  });

  test(
    'current schema enforces parent links for sessions and panel rows',
    () async {
      final db = await DatabaseHelper().db;
      await _insertValidGraph(db);

      expect(
        () => db.insert('audit_sessions', {
          'id': 'bad-session',
          'customerId': 'customer-1',
          'flockId': 'missing-flock',
          'hatcheryId': 'hatchery-1',
          'date': '2026-05-13',
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => db.insert('egg_storage', {
          'id': 'bad-panel-row',
          'sessionId': 'missing-session',
          'customerId': 'customer-1',
          'flockId': 'flock-1',
          'hatcheryId': 'hatchery-1',
          'date': '2026-05-13',
          'createdAt': '2026-05-13T08:00:00.000',
          'updatedAt': '2026-05-13T08:00:00.000',
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('current schema cascades session and customer children', () async {
    final db = await DatabaseHelper().db;
    await _insertValidGraph(db);

    await db.delete(
      'audit_sessions',
      where: 'id = ?',
      whereArgs: ['session-1'],
    );
    expect(await db.query('egg_storage'), isEmpty);
    expect(await db.query('photos'), isEmpty);

    await _insertSessionWithPanelRow(db, id: 'session-2');
    await db.delete('customers', where: 'id = ?', whereArgs: ['customer-1']);
    expect(
      await db.query(
        'flocks',
        where: 'customerId = ?',
        whereArgs: ['customer-1'],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'hatcheries',
        where: 'customerId = ?',
        whereArgs: ['customer-1'],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'audit_sessions',
        where: 'customerId = ?',
        whereArgs: ['customer-1'],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'egg_storage',
        where: 'customerId = ?',
        whereArgs: ['customer-1'],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'govee_daily_captures',
        where: 'customerId = ?',
        whereArgs: ['customer-1'],
      ),
      isEmpty,
    );
  });
}

Future<void> _insertValidGraph(Database db) async {
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Farm One',
    'createdAt': '2026-05-13T08:00:00.000',
  });
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'F-1',
    'breed': 'Ross308',
    'entryDate': '2026-01-01',
    'status': 'active',
  });
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Hatchery One',
    'createdAt': '2026-05-13T08:00:00.000',
  });
  await _insertSessionWithPanelRow(db, id: 'session-1');
  await db.insert('govee_daily_captures', {
    'id': 'capture-1',
    'customerId': 'customer-1',
    'hatcheryId': 'hatchery-1',
    'stationKey': 'egg',
    'place': 'eggStorage',
    'machineId': '',
    'captureDate': '2026-05-13',
    'status': 'completed',
    'readingCount': 0,
    'chartPointsJson': '[]',
    'createdAt': '2026-05-13T08:00:00.000',
    'updatedAt': '2026-05-13T08:00:00.000',
  });
}

Future<void> _insertSessionWithPanelRow(
  Database db, {
  required String id,
}) async {
  await db.insert('audit_sessions', {
    'id': id,
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'hatcheryId': 'hatchery-1',
    'date': '2026-05-13',
    'createdAt': '2026-05-13T08:00:00.000',
    'updatedAt': '2026-05-13T08:00:00.000',
  });
  await db.insert('egg_storage', {
    'id': 'egg-storage-$id',
    'sessionId': id,
    'customerId': 'customer-1',
    'flockId': 'flock-1',
    'hatcheryId': 'hatchery-1',
    'date': '2026-05-13',
    'createdAt': '2026-05-13T08:00:00.000',
    'updatedAt': '2026-05-13T08:00:00.000',
  });
  await db.insert('photos', {
    'id': 'photo-$id',
    'filePath': '/tmp/photo.jpg',
    'sessionId': id,
    'panelName': 'egg_storage',
    'panelRowId': 'egg-storage-$id',
    'fieldKey': 'shellTemp',
    'uploadStatus': 'local',
  });
}

Future<void> _resetDatabase() async {
  await DatabaseHelper().close();
  final dbPath = p.join(
    await databaseFactory.getDatabasesPath(),
    'hatchaudit.db',
  );
  await databaseFactory.deleteDatabase(dbPath);
}
