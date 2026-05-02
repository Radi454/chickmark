import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'session_test_helpers.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      AuditSessionModel(
        id: 'fallback',
        customerId: 'fallback',
        flockId: 'fallback',
        hatcheryId: 'fallback',
        date: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  });

  late MockDatabaseHelper mockDbHelper;
  late MockDatabase mockDb;
  late AuditSessionRepository repository;

  final testSessionRow = makeAuditSessionRow();
  final testSession = AuditSessionModel.fromMap(testSessionRow);

  setUp(() {
    mockDbHelper = MockDatabaseHelper();
    mockDb = MockDatabase();
    when(() => mockDbHelper.db).thenAnswer((_) async => mockDb);

    when(
      () => mockDbHelper.assertForeignKeys(
        customerId: any(named: 'customerId'),
        flockId: any(named: 'flockId'),
        hatcheryId: any(named: 'hatcheryId'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockDb.query(
        any(),
        columns: any(named: 'columns'),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
        orderBy: any(named: 'orderBy'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => <Map<String, Object?>>[]);

    when(
      () => mockDb.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      ),
    ).thenAnswer((_) async => 1);

    when(
      () => mockDb.update(
        any(),
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);

    when(
      () => mockDb.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);

    repository = AuditSessionRepository(dbHelper: mockDbHelper);
  });

  group('AuditSessionModel', () {
    test('fromMap produces correct values', () {
      final model = AuditSessionModel.fromMap(testSessionRow);

      expect(model.id, SessionTestFixtures.testSessionId);
      expect(model.customerId, SessionTestFixtures.testCustomerId);
      expect(model.flockId, SessionTestFixtures.testFlockId);
      expect(model.hatcheryId, SessionTestFixtures.testHatcheryId);
      expect(model.breed, SessionTestFixtures.testBreed);
      expect(model.flockAgeWeeks, 42);
      expect(model.status, 'in_progress');
      expect(model.selectedStationKeys, supportedStationKeys);
      expect(model.stationsCompleted, isEmpty);
    });

    test('toMap produces round-trippable map', () {
      final map = testSession.toMap();

      expect(map['id'], testSession.id);
      expect(map['customerId'], testSession.customerId);
      expect(map['flockId'], testSession.flockId);
      expect(map['hatcheryId'], testSession.hatcheryId);
      expect(map['status'], testSession.status);
      expect(map['flockAgeWeeks'], testSession.flockAgeWeeks);
      expect(map['selectedStationKeys'], isNotNull);
    });

    test('fromMap handles selectedStationKeys JSON', () {
      final row = makeAuditSessionRow(selectedStationKeys: ['chicks', 'egg']);
      final model = AuditSessionModel.fromMap(row);

      expect(model.selectedStationKeys, ['chicks', 'egg']);
    });

    test('fromMap defaults missing selectedStationKeys to all stations', () {
      final row = makeAuditSessionRow();
      row.remove('selectedStationKeys');
      final model = AuditSessionModel.fromMap(row);

      expect(model.selectedStationKeys, supportedStationKeys);
    });

    test('fromMap handles completedAt', () {
      final now = DateTime.now();
      final row = makeAuditSessionRow(completedAt: now, status: 'completed');
      final model = AuditSessionModel.fromMap(row);

      expect(model.status, 'completed');
      expect(model.completedAt, isNotNull);
    });

    test('fromMap handles stationsCompleted JSON', () {
      final row = makeAuditSessionRow(stationsCompleted: ['egg', 'chicks']);
      final model = AuditSessionModel.fromMap(row);

      expect(model.stationsCompleted, ['egg', 'chicks']);
    });

    test('fromMap handles null stationsCompleted gracefully', () {
      final row = makeAuditSessionRow();
      row.remove('stationsCompleted');
      final model = AuditSessionModel.fromMap(row);

      expect(model.stationsCompleted, isEmpty);
    });

    test('fromMap handles empty stationsCompleted string', () {
      final row = makeAuditSessionRow();
      row['stationsCompleted'] = '';
      final model = AuditSessionModel.fromMap(row);

      expect(model.stationsCompleted, isEmpty);
    });

    test('copyWith updates specified fields', () {
      final updated = testSession.copyWith(
        status: 'completed',
        flockAgeWeeks: 43,
        notes: 'Visit completed',
      );

      expect(updated.status, 'completed');
      expect(updated.flockAgeWeeks, 43);
      expect(updated.notes, 'Visit completed');
      expect(updated.id, testSession.id);
    });

    test('copyWith preserves unspecified fields', () {
      final updated = testSession.copyWith(status: 'completed');

      expect(updated.customerId, testSession.customerId);
      expect(updated.flockId, testSession.flockId);
      expect(updated.hatcheryId, testSession.hatcheryId);
      expect(updated.date, testSession.date);
    });

    test('toMap for completed session includes completedAt', () {
      final now = DateTime.now();
      final completed = AuditSessionModel(
        id: 'test-completed',
        customerId: 'customer-1',
        flockId: 'flock-1',
        hatcheryId: 'hatchery-1',
        date: SessionTestFixtures.testVisitDate,
        status: 'completed',
        completedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      final map = completed.toMap();
      expect(map['completedAt'], now.toIso8601String());
      expect(map['status'], 'completed');
    });
  });

  group('AuditSessionRepository - insert and retrieve', () {
    test('insertSession inserts without replacing linked child rows', () async {
      when(
        () => mockDb.insert(
          'audit_sessions',
          any(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        ),
      ).thenAnswer((_) async => 1);

      await repository.insertSession(testSession);

      verify(
        () => mockDb.insert(
          'audit_sessions',
          any(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        ),
      ).called(1);
      verifyNever(
        () => mockDb.update(
          'audit_sessions',
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      );
    });

    test(
      'insertSession updates in place when the session already exists',
      () async {
        when(
          () => mockDb.insert(
            'audit_sessions',
            any(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          ),
        ).thenAnswer((_) async => 0);

        await repository.insertSession(testSession);

        verify(
          () => mockDb.update(
            'audit_sessions',
            any(),
            where: 'id = ?',
            whereArgs: [testSession.id],
          ),
        ).called(1);
      },
    );

    test('getSessionById returns model when found', () async {
      when(
        () => mockDb.query(
          'audit_sessions',
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => [testSessionRow]);

      final result = await repository.getSessionById(testSession.id);

      expect(result, isNotNull);
      expect(result!.id, testSession.id);
    });

    test('getSessionById returns null when not found', () async {
      when(
        () => mockDb.query(
          any(),
          where: any(named: 'where'),
          whereArgs: any(named: 'whereArgs'),
        ),
      ).thenAnswer((_) async => <Map<String, Object?>>[]);

      final result = await repository.getSessionById('nonexistent');

      expect(result, isNull);
    });

    test('updateSession calls database update', () async {
      when(
        () => mockDb.update(
          'audit_sessions',
          any(),
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => 1);

      await repository.updateSession(testSession);

      verify(
        () => mockDb.update(
          'audit_sessions',
          any(),
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).called(1);
    });
  });

  group('AuditSessionRepository - progress and completion', () {
    test('markStationCompleted adds station to completed list', () async {
      when(
        () => mockDb.query(
          'audit_sessions',
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => [testSessionRow]);

      when(
        () => mockDb.update(
          'audit_sessions',
          any(),
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => 1);

      await repository.markStationCompleted(testSession.id, 'egg');

      verify(
        () => mockDb.update(
          'audit_sessions',
          any(),
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).called(1);
    });

    test(
      'markStationCompleted handles invalid station key without adding',
      () async {
        when(
          () => mockDb.query(
            'audit_sessions',
            where: 'id = ?',
            whereArgs: [testSession.id],
          ),
        ).thenAnswer((_) async => [testSessionRow]);

        final capturedUpdates = <Map<String, dynamic>>[];
        when(
          () => mockDb.update(
            'audit_sessions',
            captureAny(),
            where: 'id = ?',
            whereArgs: [testSession.id],
          ),
        ).thenAnswer((invocation) async {
          capturedUpdates.add(
            invocation.positionalArguments[1] as Map<String, dynamic>,
          );
          return 1;
        });

        await repository.markStationCompleted(
          testSession.id,
          'invalid_station',
        );

        expect(capturedUpdates.isNotEmpty, isTrue);
        final update = capturedUpdates.first;
        expect(update['stationsCompleted'], isNull);
        expect(update['status'], 'in_progress');
      },
    );

    test(
      'markStationCompleted auto-completes when all stations done',
      () async {
        final row = makeAuditSessionRow(
          stationsCompleted: [
            'egg',
            'chicks',
            'hatch_analysis_egg_breakouts',
            'setters',
          ],
        );

        when(
          () => mockDb.query(
            'audit_sessions',
            where: 'id = ?',
            whereArgs: [testSession.id],
          ),
        ).thenAnswer((_) async => [row]);

        final capturedUpdates = <Map<String, dynamic>>[];
        when(
          () => mockDb.update(
            'audit_sessions',
            captureAny(),
            where: 'id = ?',
            whereArgs: [testSession.id],
          ),
        ).thenAnswer((invocation) async {
          capturedUpdates.add(
            invocation.positionalArguments[1] as Map<String, dynamic>,
          );
          return 1;
        });

        await repository.markStationCompleted(testSession.id, 'hatchers');

        expect(capturedUpdates.isNotEmpty, isTrue);
        final update = capturedUpdates.first;
        expect(update['status'], 'completed');
        expect(update['completedAt'], isNotNull);
      },
    );

    test('markStationCompleted completes selected station subset', () async {
      final row = makeAuditSessionRow(
        selectedStationKeys: ['egg', 'chicks'],
        stationsCompleted: ['egg'],
      );

      when(
        () => mockDb.query(
          'audit_sessions',
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => [row]);

      final capturedUpdates = <Map<String, dynamic>>[];
      when(
        () => mockDb.update(
          'audit_sessions',
          captureAny(),
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((invocation) async {
        capturedUpdates.add(
          invocation.positionalArguments[1] as Map<String, dynamic>,
        );
        return 1;
      });

      await repository.markStationCompleted(testSession.id, 'chicks');

      final update = capturedUpdates.first;
      expect(update['status'], 'completed');
      expect(update['completedAt'], isNotNull);
      expect(update['stationsCompleted'], contains('chicks'));
    });

    test('updateSessionProgress filters to selected station subset', () async {
      final row = makeAuditSessionRow(
        selectedStationKeys: ['hatch_analysis_egg_breakouts'],
      );

      when(
        () => mockDb.query(
          'audit_sessions',
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => [row]);

      final capturedUpdates = <Map<String, dynamic>>[];
      when(
        () => mockDb.update(
          'audit_sessions',
          captureAny(),
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((invocation) async {
        capturedUpdates.add(
          invocation.positionalArguments[1] as Map<String, dynamic>,
        );
        return 1;
      });

      await repository.updateSessionProgress(testSession.id, [
        'egg',
        'hatch_analysis_egg_breakouts',
      ]);

      final update = capturedUpdates.first;
      expect(
        update['stationsCompleted'],
        jsonEncode(['hatch_analysis_egg_breakouts']),
      );
      expect(update['status'], 'completed');
    });
  });

  group('AuditSessionRepository - queries', () {
    test('getInProgressSessions queries by status', () async {
      when(
        () => mockDb.query(
          'audit_sessions',
          where: 'status = ?',
          whereArgs: ['in_progress'],
          orderBy: 'updatedAt DESC',
        ),
      ).thenAnswer((_) async => [testSessionRow]);

      final result = await repository.getInProgressSessions();

      expect(result.length, 1);
      expect(result.first.status, 'in_progress');
    });

    test(
      'getCompletedSessions queries with optional customer filter',
      () async {
        when(
          () => mockDb.query(
            'audit_sessions',
            where: 'status = ? AND customerId = ?',
            whereArgs: ['completed', 'customer-1'],
            orderBy: 'completedAt DESC, date DESC',
            limit: 50,
            offset: 0,
          ),
        ).thenAnswer((_) async => []);

        final result = await repository.getCompletedSessions(
          customerId: 'customer-1',
        );

        expect(result, isEmpty);
      },
    );

    test('getSessionsByDateRange queries with date bounds', () async {
      when(
        () => mockDb.query(
          'audit_sessions',
          where: 'date >= ? AND date <= ?',
          whereArgs: ['2026-01-01', '2026-12-31'],
          orderBy: 'date DESC, createdAt DESC',
          limit: 50,
        ),
      ).thenAnswer((_) async => [testSessionRow]);

      final result = await repository.getSessionsByDateRange(
        '2026-01-01',
        '2026-12-31',
      );

      expect(result.length, 1);
    });
  });

  group('AuditSessionRepository - deleteSession', () {
    test('deleteSession calls database delete', () async {
      when(
        () => mockDb.delete(
          'audit_sessions',
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).thenAnswer((_) async => 1);

      await repository.deleteSession(testSession.id);

      verify(
        () => mockDb.delete(
          'audit_sessions',
          where: 'id = ?',
          whereArgs: [testSession.id],
        ),
      ).called(1);
    });
  });
}
