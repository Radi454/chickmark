import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';
import 'package:hatchaudit/data/repositories/broiler_daily_record_repository.dart';
import 'package:hatchaudit/data/repositories/broiler_target_repository.dart';
import 'package:hatchaudit/features/performance/providers/broiler_daily_entry_provider.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await _seedQuickEntryHierarchy();
    await BroilerTargetRepository().ensureOfficialCatalogueSeeded();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'selector order loads all active houses with previous and target context',
    () async {
      final dailyRepository = BroilerDailyRecordRepository();
      await dailyRepository.saveRevision(
        _dailyDraft(
          placementId: 'placement-1',
          date: DateTime.utc(2026, 7, 23),
          opening: 10000,
          mortality: 7,
          closing: 9991,
        ),
      );
      final provider = BroilerDailyEntryProvider();

      await provider.load(enteredBy: 'auditor-1');
      expect(provider.customers.single.id, 'customer-1');
      expect(provider.farms, isEmpty);
      expect(provider.flocks, isEmpty);

      await provider.selectCustomer('customer-1');
      expect(provider.farms.single.id, 'farm-1');
      expect(provider.flocks, isEmpty);

      await provider.selectFarm('farm-1');
      expect(provider.flocks.single.id, 'flock-1');

      provider.setDate(DateTime.utc(2026, 7, 24));
      await provider.selectFlock('flock-1');

      expect(provider.houseEntries, hasLength(2));
      final house1 = provider.houseEntries.firstWhere(
        (entry) => entry.house.id == 'house-1',
      );
      expect(house1.ageDay, 23);
      expect(house1.flock.breed, 'Ross 308');
      expect(house1.placement.placedBirds, 10000);
      expect(house1.previous!.revision.dailyMortality, 7);
      expect(house1.target?.bodyWeightG, 1174);
      expect(house1.draft.dailyMortality, isNull);
      expect(house1.draft.closingLiveBirdCount, isNull);
    },
  );

  test(
    'valid houses save while invalid drafts remain with a per-house summary',
    () async {
      final provider = BroilerDailyEntryProvider();
      await provider.load(enteredBy: 'auditor-1');
      await provider.selectCustomer('customer-1');
      await provider.selectFarm('farm-1');
      provider.setDate(DateTime.utc(2026, 7, 24));
      await provider.selectFlock('flock-1');

      final first = provider.houseEntries[0];
      final second = provider.houseEntries[1];
      provider.updateDraft(
        first.placement.id,
        first.draft.copyWith(
          openingBirdCount: 10000,
          mortality: 10,
          dailyCulls: 2,
          transfersIn: 0,
          transfersOut: 0,
          partialDepletion: 0,
          otherPopulationAdjustment: 0,
          closingLiveBirdCount: 9988,
          dailyFeedConsumedKg: 1020,
          waterConsumedLiters: 1836,
        ),
      );
      provider.updateDraft(
        second.placement.id,
        second.draft.copyWith(
          openingBirdCount: 9000,
          mortality: 10,
          dailyCulls: 0,
          transfersIn: 0,
          transfersOut: 0,
          partialDepletion: 0,
          otherPopulationAdjustment: 0,
          closingLiveBirdCount: 8999,
        ),
      );

      final result = await provider.saveValidDrafts();

      expect(result.savedPlacementIds, [first.placement.id]);
      expect(result.errorsByPlacement.keys, [second.placement.id]);
      expect(
        provider.houseEntries
            .firstWhere((entry) => entry.placement.id == second.placement.id)
            .draft
            .closingLiveBirdCount,
        8999,
      );
      expect(
        await BroilerDailyRecordRepository().getCurrentForPlacementDate(
          first.placement.id,
          DateTime.utc(2026, 7, 24),
        ),
        isNotNull,
      );
    },
  );
}

Future<void> _seedQuickEntryHierarchy() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Integrated Poultry Co.',
  });
  await db.insert('customer_sectors', {
    'id': 'customer-sector-1',
    'customerId': 'customer-1',
    'sectorKey': 'broiler',
    'isActive': 1,
  });
  await db.insert('farms', {
    'id': 'farm-1',
    'customerId': 'customer-1',
    'sectorKey': 'broiler',
    'name': 'Broiler Farm',
  });
  for (final house in const [('house-1', 'House 1'), ('house-2', 'House 2')]) {
    await db.insert('houses', {
      'id': house.$1,
      'farmId': 'farm-1',
      'name': house.$2,
      'isActive': 1,
    });
  }
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'BR-2026-01',
    'breed': 'Ross 308',
    'entryDate': '2026-07-01T00:00:00.000Z',
    'farmId': 'farm-1',
    'sectorKey': 'broiler',
    'sexProfile': 'as_hatched',
    'targetProfileId': 'ross-308-2022-as-hatched',
  });
  for (final placement in const [
    ('placement-1', 'house-1', 10000),
    ('placement-2', 'house-2', 9000),
  ]) {
    await db.insert('flock_placements', {
      'id': placement.$1,
      'flockId': 'flock-1',
      'houseId': placement.$2,
      'placedBirds': placement.$3,
      'placedAt': '2026-07-01T00:00:00.000Z',
      'status': 'active',
    });
  }
}

BroilerDailyRecordDraft _dailyDraft({
  required String placementId,
  required DateTime date,
  required int opening,
  required int mortality,
  required int closing,
}) {
  return BroilerDailyRecordDraft(
    placementId: placementId,
    recordDate: date,
    verificationStatus: VerificationStatus.entered,
    enteredBy: 'auditor-1',
    enteredAt: date.add(const Duration(hours: 18)),
    openingBirdCount: opening,
    dailyMortality: mortality,
    dailyCulls: 2,
    transfersIn: 0,
    transfersOut: 0,
    partialDepletion: 0,
    otherPopulationAdjustment: 0,
    closingLiveBirdCount: closing,
  );
}
