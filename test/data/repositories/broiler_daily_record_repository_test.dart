import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/data/repositories/broiler_daily_record_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late BroilerDailyRecordRepository repository;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    repository = BroilerDailyRecordRepository();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await _seedPlacement();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'corrections append revisions and move only the current pointer',
    () async {
      final draft = _draft(
        sources: const [
          DailyRecordSourceDraft(
            sourceKind: DailyRecordSourceKind.spreadsheet,
            localPath: '/documents/day-24.xlsx',
            originalFilename: 'day-24.xlsx',
            checksum: 'sha256:day24',
          ),
        ],
        events: [
          BroilerDailyEventDraft(
            eventType: BroilerDailyEventType.waterFailure,
            eventAt: DateTime.utc(2026, 7, 24, 8),
            isAllDay: false,
            eventState: DailyEventState.resolved,
            description: 'Water stopped for 20 minutes',
          ),
        ],
      );
      final first = await repository.saveRevision(draft);
      final corrected = await repository.saveRevision(
        draft.copyWith(
          recordId: first.record.id,
          mortality: 12,
          closingLiveBirdCount: 9986,
          verificationStatus: VerificationStatus.corrected,
          correctionReason: 'Checked farm mortality sheet',
          sources: const [],
          events: const [],
        ),
      );

      expect(first.revision.revisionNumber, 1);
      expect(corrected.revision.revisionNumber, 2);
      expect(await repository.listRevisions(first.record.id), hasLength(2));
      expect(corrected.record.currentRevisionId, corrected.revision.id);
      expect(first.sources.single.revisionId, first.revision.id);
      expect(first.events.single.revisionId, first.revision.id);

      final current = await repository.getCurrentForPlacementDate(
        'placement-1',
        DateTime.utc(2026, 7, 24),
      );
      expect(current!.revision.dailyMortality, 12);
      expect(current.revision.correctionReason, 'Checked farm mortality sheet');
    },
  );

  test(
    'placement and date identify one record even without a record id',
    () async {
      final first = await repository.saveRevision(_draft());
      final second = await repository.saveRevision(
        _draft(
          mortality: 11,
          closingLiveBirdCount: 9987,
          verificationStatus: VerificationStatus.reviewed,
        ),
      );

      expect(second.record.id, first.record.id);
      expect(second.revision.revisionNumber, 2);

      final db = await DatabaseHelper().db;
      final count = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM broiler_daily_records',
      );
      expect(count.single['count'], 1);
    },
  );

  test(
    'previous-day values and flock entry grid expose current revisions',
    () async {
      await repository.saveRevision(
        _draft(
          recordDate: DateTime.utc(2026, 7, 23),
          openingBirdCount: 10020,
          mortality: 8,
          closingLiveBirdCount: 10010,
        ),
      );
      await repository.saveRevision(_draft());

      final previous = await repository.getPreviousDay(
        'placement-1',
        DateTime.utc(2026, 7, 24),
      );
      final grid = await repository.listFlockDateGrid(
        'flock-1',
        DateTime.utc(2026, 7, 24),
      );

      expect(previous!.revision.dailyMortality, 8);
      expect(grid, hasLength(1));
      expect(grid.single.houseId, 'house-1');
      expect(grid.single.current!.revision.dailyMortality, 10);
    },
  );

  test('invalid revision rolls back the record, sources, and events', () async {
    await expectLater(
      repository.saveRevision(
        _draft(
          closingLiveBirdCount: 9999,
          sources: const [
            DailyRecordSourceDraft(
              sourceKind: DailyRecordSourceKind.image,
              localPath: '/documents/bad.jpg',
            ),
          ],
        ),
      ),
      throwsA(isA<DailyRecordValidationException>()),
    );

    final db = await DatabaseHelper().db;
    for (final table in const [
      'broiler_daily_records',
      'broiler_daily_record_revisions',
      'daily_record_sources',
      'broiler_daily_events',
    ]) {
      final count = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
      expect(count.single['count'], 0, reason: table);
    }
  });
}

BroilerDailyRecordDraft _draft({
  DateTime? recordDate,
  int openingBirdCount = 10000,
  int mortality = 10,
  int closingLiveBirdCount = 9988,
  VerificationStatus verificationStatus = VerificationStatus.entered,
  List<DailyRecordSourceDraft> sources = const [],
  List<BroilerDailyEventDraft> events = const [],
}) {
  return BroilerDailyRecordDraft(
    placementId: 'placement-1',
    recordDate: recordDate ?? DateTime.utc(2026, 7, 24),
    verificationStatus: verificationStatus,
    dataSourceType: DailyDataSourceType.manual,
    reportedBy: 'Farm clerk',
    enteredBy: 'auditor-1',
    enteredAt: DateTime.utc(2026, 7, 24, 18),
    openingBirdCount: openingBirdCount,
    dailyMortality: mortality,
    dailyCulls: 2,
    transfersIn: 0,
    transfersOut: 0,
    partialDepletion: 0,
    otherPopulationAdjustment: 0,
    closingLiveBirdCount: closingLiveBirdCount,
    dailyFeedConsumedKg: 1020,
    waterConsumedLiters: 1836,
    sources: sources,
    events: events,
  );
}

Future<void> _seedPlacement() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {'id': 'customer-1', 'name': 'Customer'});
  await db.insert('farms', {
    'id': 'farm-1',
    'customerId': 'customer-1',
    'sectorKey': 'broiler',
    'name': 'Farm 1',
  });
  await db.insert('houses', {
    'id': 'house-1',
    'farmId': 'farm-1',
    'name': 'House 1',
  });
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'F-1',
    'farmId': 'farm-1',
    'sectorKey': 'broiler',
    'entryDate': '2026-07-01T00:00:00.000Z',
  });
  await db.insert('flock_placements', {
    'id': 'placement-1',
    'flockId': 'flock-1',
    'houseId': 'house-1',
    'placedBirds': 10020,
    'placedAt': '2026-07-01T00:00:00.000Z',
    'status': 'active',
  });
}
