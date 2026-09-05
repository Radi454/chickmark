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

  test('customer can enable multiple sectors', () async {
    await repository.replaceCustomerSectors('customer-1', {
      PoultrySector.breeder,
      PoultrySector.broiler,
    });

    final sectors = await repository.listCustomerSectors('customer-1');
    expect(
      sectors.where((sector) => sector.isActive).map((sector) => sector.sector),
      containsAll([PoultrySector.breeder, PoultrySector.broiler]),
    );
  });

  test('a house belongs to a flock and carries its opening counts', () async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {
      'id': 'flock-1',
      'customerId': 'customer-1',
      'flockId': 'BR-2026-01',
      'breed': 'Ross 308',
      'entryDate': '2026-07-01T00:00:00.000Z',
      'sectorKey': 'breeder',
    });

    await repository.saveHouse(
      HouseModel(
        id: 'house-1',
        flockId: 'flock-1',
        name: 'House 1',
        openingFemales: 10000,
        openingMales: 1000,
      ),
    );
    await repository.saveHouse(
      HouseModel(
        id: 'house-2',
        flockId: 'flock-1',
        name: 'House 2',
        openingFemales: 9500,
        openingMales: 950,
      ),
    );

    final houses = await repository.listHouses('flock-1');
    expect(houses, hasLength(2));
    expect(
      houses.map((house) => house.openingFemales),
      containsAll([10000, 9500]),
    );
  });

  test('saving a house against a missing flock is rejected', () async {
    await expectLater(
      repository.saveHouse(
        HouseModel(id: 'house-1', flockId: 'missing-flock', name: 'House 1'),
      ),
      throwsArgumentError,
    );
  });

  test('house name is unique within a flock but not across flocks', () async {
    final db = await DatabaseHelper().db;
    for (final flockId in const ['flock-1', 'flock-2']) {
      await db.insert('flocks', {
        'id': flockId,
        'customerId': 'customer-1',
        'flockId': flockId,
        'breed': 'Cobb500',
        'entryDate': '2026-07-01T00:00:00.000Z',
        'sectorKey': 'breeder',
      });
    }

    await repository.saveHouse(
      HouseModel(id: 'house-1', flockId: 'flock-1', name: 'House 1'),
    );
    // Same name, different flock: allowed.
    await repository.saveHouse(
      HouseModel(id: 'house-2', flockId: 'flock-2', name: 'House 1'),
    );

    await expectLater(
      db.insert('houses', {
        'id': 'house-3',
        'flockId': 'flock-1',
        'name': 'House 1',
        'isActive': 1,
        'syncStatus': 'pending',
      }),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'a flock without a farmId or a separate placement table can still own houses',
    () {
      final flock = FlockModel(
        id: 'flock-3',
        customerId: 'customer-1',
        flockId: 'BR-2026-02',
        breed: 'Ross 308',
        entryDate: DateTime.utc(2026, 7, 1),
        sector: PoultrySector.breeder,
        sexProfile: FlockSexProfile.asHatched,
      );
      expect(flock.toMap().containsKey('farmId'), isFalse);
    },
  );
}
