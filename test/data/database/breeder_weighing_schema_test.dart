import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';

import '../../support/test_database.dart';

/// Schema-level guarantees for `breeder_weighing_sessions` and
/// `breeder_weighing_samples` (breeder-flock-performance ticket 13): the
/// database itself refuses a session whose house belongs to a different
/// flock, a negative sample weight, and a non-positive sample size.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  String iso(DateTime d) => d.toIso8601String();

  Future<void> seedFlock(String flockId) async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {
      'id': flockId,
      'flockId': flockId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> seedHouse(String id, String flockId) async {
    await seedFlock(flockId);
    final db = await DatabaseHelper().db;
    await db.insert('houses', {'id': id, 'flockId': flockId, 'name': id});
  }

  Map<String, Object?> sessionRow({
    required String id,
    required String flockId,
    required String houseId,
    String sex = 'female',
    int sampleSize = 10,
  }) {
    final now = iso(DateTime(2026, 1, 1));
    return {
      'id': id,
      'flockId': flockId,
      'houseId': houseId,
      'sessionDate': '2026-01-01',
      'sex': sex,
      'method': 'Individual bird scale',
      'sampleSize': sampleSize,
      'createdAt': now,
      'updatedAt': now,
    };
  }

  test('house-scope trigger rejects a house from a different flock', () async {
    await seedFlock('flock-a');
    await seedFlock('flock-b');
    await seedHouse('house-b1', 'flock-b');
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert(
        'breeder_weighing_sessions',
        sessionRow(id: 'ws-1', flockId: 'flock-a', houseId: 'house-b1'),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('house-scope trigger accepts a house belonging to the flock', () async {
    await seedFlock('flock-c');
    await seedHouse('house-c1', 'flock-c');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_weighing_sessions',
      sessionRow(id: 'ws-2', flockId: 'flock-c', houseId: 'house-c1'),
    );
    final rows = await db.query(
      'breeder_weighing_sessions',
      where: 'id = ?',
      whereArgs: ['ws-2'],
    );
    expect(rows, hasLength(1));
  });

  test('house-scope trigger rejects an update that moves house to another flock', () async {
    await seedFlock('flock-d');
    await seedFlock('flock-e');
    await seedHouse('house-d1', 'flock-d');
    await seedHouse('house-e1', 'flock-e');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_weighing_sessions',
      sessionRow(id: 'ws-3', flockId: 'flock-d', houseId: 'house-d1'),
    );
    await expectLater(
      db.update(
        'breeder_weighing_sessions',
        {'houseId': 'house-e1'},
        where: 'id = ?',
        whereArgs: ['ws-3'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('sampleSize must be positive', () async {
    await seedFlock('flock-f');
    await seedHouse('house-f1', 'flock-f');
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert(
        'breeder_weighing_sessions',
        sessionRow(id: 'ws-4', flockId: 'flock-f', houseId: 'house-f1', sampleSize: 0),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('sex must be female or male', () async {
    await seedFlock('flock-g');
    await seedHouse('house-g1', 'flock-g');
    final db = await DatabaseHelper().db;
    await expectLater(
      db.insert(
        'breeder_weighing_sessions',
        sessionRow(id: 'ws-5', flockId: 'flock-g', houseId: 'house-g1', sex: 'unknown'),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a sample rejects a negative weight', () async {
    await seedFlock('flock-h');
    await seedHouse('house-h1', 'flock-h');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_weighing_sessions',
      sessionRow(id: 'ws-6', flockId: 'flock-h', houseId: 'house-h1'),
    );
    final now = iso(DateTime(2026, 1, 1));
    await expectLater(
      db.insert('breeder_weighing_samples', {
        'id': 'sample-1',
        'sessionId': 'ws-6',
        'weightGrams': -1,
        'createdAt': now,
        'updatedAt': now,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a sample accepts a zero weight (non-negative boundary)', () async {
    await seedFlock('flock-i');
    await seedHouse('house-i1', 'flock-i');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_weighing_sessions',
      sessionRow(id: 'ws-7', flockId: 'flock-i', houseId: 'house-i1'),
    );
    final now = iso(DateTime(2026, 1, 1));
    await db.insert('breeder_weighing_samples', {
      'id': 'sample-2',
      'sessionId': 'ws-7',
      'weightGrams': 0,
      'createdAt': now,
      'updatedAt': now,
    });
    final rows = await db.query(
      'breeder_weighing_samples',
      where: 'id = ?',
      whereArgs: ['sample-2'],
    );
    expect(rows, hasLength(1));
  });

  test('deleting a session cascades to its samples', () async {
    await seedFlock('flock-j');
    await seedHouse('house-j1', 'flock-j');
    final db = await DatabaseHelper().db;
    await db.insert(
      'breeder_weighing_sessions',
      sessionRow(id: 'ws-8', flockId: 'flock-j', houseId: 'house-j1'),
    );
    final now = iso(DateTime(2026, 1, 1));
    await db.insert('breeder_weighing_samples', {
      'id': 'sample-3',
      'sessionId': 'ws-8',
      'weightGrams': 100,
      'createdAt': now,
      'updatedAt': now,
    });
    await db.delete('breeder_weighing_sessions', where: 'id = ?', whereArgs: ['ws-8']);
    final rows = await db.query(
      'breeder_weighing_samples',
      where: 'sessionId = ?',
      whereArgs: ['ws-8'],
    );
    expect(rows, isEmpty);
  });
}
