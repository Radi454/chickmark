import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/broiler_daily_record_repository.dart';
import 'package:hatchaudit/data/repositories/broiler_target_repository.dart';
import 'package:hatchaudit/features/performance/providers/performance_provider.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() async => databaseDirectory = await useIsolatedAppDatabase());
  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
  });
  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('SQLite source aggregates current house revisions into KPIs', () async {
    final profileRepository = BroilerTargetRepository();
    await profileRepository.ensureOfficialCatalogueSeeded();
    final profile = (await profileRepository.listProfiles(
      breed: 'Ross 308',
      sexProfile: FlockSexProfile.asHatched,
      activeOnly: true,
    )).single;
    final flock = await _seedScope(profile.id);
    await BroilerDailyRecordRepository().saveRevision(
      BroilerDailyRecordDraft(
        placementId: 'placement-1',
        recordDate: DateTime.utc(2026, 7, 24),
        verificationStatus: VerificationStatus.verified,
        reportedBy: 'farm-manager',
        enteredBy: 'auditor-1',
        enteredAt: DateTime.utc(2026, 7, 24, 8),
        verifiedBy: 'auditor-1',
        verifiedAt: DateTime.utc(2026, 7, 24, 9),
        openingBirdCount: 1000,
        dailyMortality: 10,
        dailyCulls: 5,
        closingLiveBirdCount: 985,
        dailyFeedConsumedKg: 100,
        waterConsumedLiters: 170,
        averageBodyWeightG: 1000,
        birdsWeighed: 100,
      ),
    );

    final snapshot = await SqlitePerformanceWorkspaceDataSource().loadSnapshot(
      flock: flock,
      rangeStart: DateTime.utc(2026, 7, 24),
      rangeEnd: DateTime.utc(2026, 7, 24),
    );

    expect(snapshot.metrics['water_to_feed_ratio']!.value, 1.7);
    expect(snapshot.metrics['average_live_birds']!.value, 992.5);
    expect(snapshot.verificationStatus, VerificationStatus.verified);
    expect(snapshot.reportedData, isTrue);
    expect(snapshot.targetSourceLabel!.toLowerCase(), contains('ross 308'));
    expect(snapshot.trendPoints, hasLength(1));
  });
}

Future<FlockModel> _seedScope(String targetProfileId) async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Customer',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'createdBy': 'test',
  });
  await db.insert('customer_sectors', {
    'id': 'sector-1',
    'customerId': 'customer-1',
    'sectorKey': 'broiler',
  });
  await db.insert('farms', {
    'id': 'farm-1',
    'customerId': 'customer-1',
    'sectorKey': 'broiler',
    'name': 'Farm',
  });
  await db.insert('houses', {
    'id': 'house-1',
    'farmId': 'farm-1',
    'name': 'House 1',
  });
  final flock = FlockModel(
    id: 'flock-1',
    customerId: 'customer-1',
    flockId: 'F-1',
    breed: 'Ross 308',
    entryDate: DateTime.utc(2026, 7, 1),
    farmId: 'farm-1',
    sector: PoultrySector.broiler,
    targetProfileId: targetProfileId,
  );
  await db.insert('flocks', flock.toMap());
  await db.insert('flock_placements', {
    'id': 'placement-1',
    'flockId': flock.id,
    'houseId': 'house-1',
    'placedBirds': 1000,
    'placedAt': flock.entryDate.toIso8601String(),
  });
  return flock;
}
