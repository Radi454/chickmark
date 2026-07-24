import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late PoultryHierarchyRepository repository;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    repository = PoultryHierarchyRepository();
    final db = await DatabaseHelper().db;
    await db.delete('customers');
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'Integrated Poultry Co.',
    });
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'customer can enable multiple sectors while each farm has one',
    () async {
      await repository.replaceCustomerSectors('customer-1', {
        PoultrySector.breeder,
        PoultrySector.broiler,
      });

      final sectors = await repository.listCustomerSectors('customer-1');
      expect(
        sectors
            .where((sector) => sector.isActive)
            .map((sector) => sector.sector),
        containsAll([PoultrySector.breeder, PoultrySector.broiler]),
      );

      await repository.saveFarm(
        FarmModel(
          id: 'farm-1',
          customerId: 'customer-1',
          sector: PoultrySector.broiler,
          name: 'Broiler Farm',
        ),
      );
      final farms = await repository.listFarms(
        'customer-1',
        sector: PoultrySector.broiler,
      );
      expect(farms.single.sector, PoultrySector.broiler);
    },
  );

  test('one flock batch can be placed in multiple houses', () async {
    await _createBroilerFarm(repository);
    final flock = FlockModel(
      id: 'flock-1',
      customerId: 'customer-1',
      flockId: 'BR-2026-01',
      breed: 'Ross 308',
      entryDate: DateTime.utc(2026, 7, 1),
      farmId: 'farm-1',
      sector: PoultrySector.broiler,
      sexProfile: FlockSexProfile.asHatched,
    );

    await repository.createBroilerFlockWithPlacements(flock, [
      FlockPlacementModel(
        id: 'placement-1',
        flockId: flock.id,
        houseId: 'house-1',
        placedBirds: 10000,
        placedAt: flock.entryDate,
      ),
      FlockPlacementModel(
        id: 'placement-2',
        flockId: flock.id,
        houseId: 'house-2',
        placedBirds: 9500,
        placedAt: flock.entryDate,
      ),
    ]);

    final placements = await repository.listPlacements(flock.id);
    expect(placements, hasLength(2));
    expect(
      placements.map((placement) => placement.placedBirds),
      containsAll([10000, 9500]),
    );
  });

  test('second active placement in a house raises a domain conflict', () async {
    await _createBroilerFarm(repository);
    final db = await DatabaseHelper().db;
    for (final flockId in const ['flock-1', 'flock-2']) {
      await db.insert('flocks', {
        'id': flockId,
        'customerId': 'customer-1',
        'flockId': flockId,
        'breed': 'Cobb500',
        'entryDate': '2026-07-01T00:00:00.000Z',
        'farmId': 'farm-1',
        'sectorKey': 'broiler',
      });
    }
    await repository.createPlacement(
      FlockPlacementModel(
        id: 'placement-1',
        flockId: 'flock-1',
        houseId: 'house-1',
        placedBirds: 10000,
        placedAt: DateTime.utc(2026, 7, 1),
      ),
    );

    await expectLater(
      repository.createPlacement(
        FlockPlacementModel(
          id: 'placement-2',
          flockId: 'flock-2',
          houseId: 'house-1',
          placedBirds: 9000,
          placedAt: DateTime.utc(2026, 7, 2),
        ),
      ),
      throwsA(isA<ActiveHousePlacementConflict>()),
    );
  });
}

Future<void> _createBroilerFarm(PoultryHierarchyRepository repository) async {
  await repository.replaceCustomerSectors('customer-1', {
    PoultrySector.broiler,
  });
  await repository.saveFarm(
    FarmModel(
      id: 'farm-1',
      customerId: 'customer-1',
      sector: PoultrySector.broiler,
      name: 'Farm 1',
    ),
  );
  await repository.saveHouse(
    HouseModel(id: 'house-1', farmId: 'farm-1', name: 'House 1'),
  );
  await repository.saveHouse(
    HouseModel(id: 'house-2', farmId: 'farm-1', name: 'House 2'),
  );
}
