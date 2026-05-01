import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

void main() {
  test('extractEstPhotoPathsFromRows returns unique EST evidence paths', () {
    final paths = AuditRepository.extractEstPhotoPathsFromRows(
      [
        {
          'es_estPhotosJson':
              '{"front_top":"/tmp/front.jpg","middle_top":"/tmp/middle.jpg"}',
        },
        {
          'es_estPhotosJson':
              '{"back_top":"/tmp/front.jpg","back_middle":"","back_bottom":null}',
        },
        {'es_estPhotosJson': 'not-json'},
      ],
      existing: const ['/tmp/existing.jpg'],
    );

    expect(paths, ['/tmp/existing.jpg', '/tmp/front.jpg', '/tmp/middle.jpg']);
  });

  group('getLatestEggStorageEstEvidence', () {
    late MockDatabaseHelper dbHelper;
    late MockDatabase db;
    late AuditRepository repository;

    setUp(() {
      dbHelper = MockDatabaseHelper();
      db = MockDatabase();
      when(() => dbHelper.db).thenAnswer((_) async => db);
      repository = AuditRepository(dbHelper: dbHelper);
    });

    test('returns latest audit evidence in canonical EST order', () async {
      when(() => db.rawQuery(any(), any())).thenAnswer(
        (_) async => [
          {
            'es_estReadingsJson':
                '{"front_top":20.1,"front_middle":20.2,"back_bottom":20.9}',
            'es_estPhotosJson':
                '{"front_top":"/photos/front-top.jpg","back_bottom":"/photos/back-bottom.jpg"}',
          },
        ],
      );

      final evidence = await repository.getLatestEggStorageEstEvidence(
        DashboardFilter(customerId: 'customer-1'),
      );

      expect(evidence, isNotNull);
      expect(evidence!.points.map((point) => point.key), [
        'front_top',
        'front_middle',
        'front_bottom',
        'middle_top',
        'middle_middle',
        'middle_bottom',
        'back_top',
        'back_middle',
        'back_bottom',
      ]);
      expect(evidence.points.first.positionLabel, 'Front');
      expect(evidence.points.first.levelLabel, 'Top');
      expect(evidence.points.first.readingC, 20.1);
      expect(evidence.points.first.photoPath, '/photos/front-top.jpg');
      expect(evidence.points[8].readingC, 20.9);
      expect(evidence.points[8].photoPath, '/photos/back-bottom.jpg');

      final captured = verify(
        () => db.rawQuery(captureAny(), captureAny()),
      ).captured;
      expect(captured.first as String, contains('ORDER BY date DESC'));
      expect(captured.first as String, contains('createdAt DESC'));
      expect(captured.first as String, contains('LIMIT 1'));
    });

    test('maps legacy door keys and keeps canonical duplicate photo', () async {
      when(() => db.rawQuery(any(), any())).thenAnswer(
        (_) async => [
          {
            'es_estReadingsJson': '{"door_top":19.8}',
            'es_estPhotosJson':
                '{"door_top":"/photos/old-door.jpg","front_top":"/photos/new-front.jpg"}',
          },
        ],
      );

      final evidence = await repository.getLatestEggStorageEstEvidence(
        DashboardFilter(),
      );

      expect(evidence!.points.first.key, 'front_top');
      expect(evidence.points.first.readingC, 19.8);
      expect(evidence.points.first.photoPath, '/photos/new-front.jpg');
    });

    test('returns safe empty points for missing or malformed JSON', () async {
      when(() => db.rawQuery(any(), any())).thenAnswer(
        (_) async => [
          {
            'es_estReadingsJson': 'not-json',
            'es_estPhotosJson': '{"front_top":""}',
          },
        ],
      );

      final evidence = await repository.getLatestEggStorageEstEvidence(
        DashboardFilter(),
      );

      expect(evidence, isNotNull);
      expect(evidence!.points, hasLength(9));
      expect(evidence.points.every((point) => point.readingC == null), isTrue);
      expect(evidence.points.every((point) => point.photoPath == null), isTrue);
      expect(evidence.isComplete, isFalse);
    });
  });
}
