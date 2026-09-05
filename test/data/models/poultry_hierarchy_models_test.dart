import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';

void main() {
  test('poultry sectors and flock sex profiles use stable storage keys', () {
    expect(PoultrySector.breeder.storageKey, 'breeder');
    expect(PoultrySector.broiler.storageKey, 'broiler');
    expect(PoultrySector.layer.storageKey, 'layer');
    expect(PoultrySector.fromStorage('BROILER'), PoultrySector.broiler);

    expect(FlockSexProfile.asHatched.storageKey, 'as_hatched');
    expect(FlockSexProfile.fromStorage('male'), FlockSexProfile.male);
    expect(FlockSexProfile.fromStorage(null), FlockSexProfile.asHatched);
  });

  test('hierarchy models round-trip their ownership and sync metadata', () {
    final timestamp = DateTime.utc(2026, 7, 24, 8, 30);
    final sector = CustomerSectorModel(
      id: 'sector-1',
      customerId: 'customer-1',
      sector: PoultrySector.broiler,
      isActive: true,
      createdAt: timestamp,
      updatedAt: timestamp,
      syncStatus: 'failed',
      syncError: 'offline',
    );
    // A house belongs directly to a flock: a farm and a flock are the same
    // thing in this business, so there is no separate farm row and no
    // per-house placement date. Opening female/male counts live on the
    // house itself.
    final house = HouseModel(
      id: 'house-1',
      flockId: 'flock-1',
      name: 'House 1',
      code: 'H1',
      capacity: 12000,
      openingFemales: 9500,
      openingMales: 500,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(CustomerSectorModel.fromMap(sector.toMap()).sector, sector.sector);
    expect(CustomerSectorModel.fromMap(sector.toMap()).syncError, 'offline');
    expect(HouseModel.fromMap(house.toMap()).flockId, 'flock-1');
    expect(HouseModel.fromMap(house.toMap()).capacity, 12000);
    expect(HouseModel.fromMap(house.toMap()).openingFemales, 9500);
    expect(HouseModel.fromMap(house.toMap()).openingMales, 500);
  });

  test('house rejects an empty flock id and negative opening counts', () {
    expect(
      () => HouseModel(id: 'house-1', flockId: '', name: 'House 1'),
      throwsArgumentError,
    );
    expect(
      () => HouseModel(
        id: 'house-2',
        flockId: 'flock-1',
        name: 'House 2',
        openingFemales: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => HouseModel(
        id: 'house-3',
        flockId: 'flock-1',
        name: 'House 3',
        openingMales: -1,
      ),
      throwsArgumentError,
    );
  });
}
