import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  group('AuditRepository egg breakout dashboard aggregation', () {
    late MockDatabaseHelper dbHelper;
    late MockDatabase db;
    late AuditRepository repository;

    setUp(() {
      dbHelper = MockDatabaseHelper();
      db = MockDatabase();
      when(() => dbHelper.db).thenAnswer((_) async => db);
      repository = AuditRepository(dbHelper: dbHelper);
    });

    test('guards tray count percentages against impossible counts', () async {
      when(() => db.rawQuery(any(), any())).thenAnswer(
        (_) async => [
          {
            'rowCount': 1,
            'traySize': 150.0,
            'infertileCount': 15.0,
            'earlyDeadCount': 0.0,
            'midDeadCount': 0.0,
            'lateDeadCount': 0.0,
            'internalPipCount': 0.0,
            'externalPipCount': 0.0,
            'crackedCount': 0.0,
            'contaminatedCount': 0.0,
            'malpositionCount': 0.0,
            'exposedBrainCount': 0.0,
            'crossedBeakCount': 0.0,
            'culledDeadCount': 0.0,
            'infertilePct': 10.0,
          },
        ],
      );

      await repository.getEggBreakoutAvg(
        DashboardFilter(customerId: 'cust-1'),
        'residueHatchDay',
      );

      final sql =
          verify(() => db.rawQuery(captureAny(), captureAny())).captured.first
              as String;

      expect(sql, contains('ebInfertileCount BETWEEN 0 AND ebTraySize'));
      expect(sql, contains('ebCulledDeadCount BETWEEN 0 AND ebTraySize'));
    });

    test('guards trend percentages against impossible counts', () async {
      when(() => db.rawQuery(any(), any())).thenAnswer(
        (_) async => [
          {'date': '2026-05-13', 'infertilePct': 10.0},
        ],
      );

      await repository.getEggBreakoutTrend(
        DashboardFilter(),
        'residueHatchDay',
      );

      final sql =
          verify(() => db.rawQuery(captureAny(), captureAny())).captured.first
              as String;

      expect(sql, contains('ebInfertileCount BETWEEN 0 AND ebTraySize'));
      expect(sql, contains('ebCulledDeadCount BETWEEN 0 AND ebTraySize'));
    });
  });
}
