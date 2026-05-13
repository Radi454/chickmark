import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  group('AuditRepository.getPasgarAvg', () {
    late MockDatabaseHelper mockDbHelper;
    late MockDatabase mockDb;
    late AuditRepository repository;

    setUp(() {
      mockDbHelper = MockDatabaseHelper();
      mockDb = MockDatabase();
      when(() => mockDbHelper.db).thenAnswer((_) async => mockDb);
      repository = AuditRepository(dbHelper: mockDbHelper);
    });

    test('normalizes defect counts by sample size in SQL', () async {
      when(() => mockDb.rawQuery(any(), any())).thenAnswer(
        (_) async => [
          {
            'score': 9.3,
            'reflexesPct': 5.0,
            'beakPct': 2.5,
            'navelPct': 12.5,
            'bellyPct': 7.5,
            'legPct': 10.0,
            'featherDevPct': 15.0,
          },
        ],
      );

      await repository.getPasgarAvg(DashboardFilter(customerId: 'cust-1'));

      final captured = verify(
        () => mockDb.rawQuery(captureAny(), captureAny()),
      ).captured;
      final sql = captured.first as String;

      expect(sql, contains('pasgarReflexes * 100.0 / pasgarSampleSize'));
      expect(sql, contains('pasgarFeatherDev * 100.0 / pasgarSampleSize'));
      expect(sql, contains('pasgarReflexes BETWEEN 0 AND pasgarSampleSize'));
      expect(sql, contains('pasgarFeatherDev BETWEEN 0 AND pasgarSampleSize'));
    });
  });
}
