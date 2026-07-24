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
    final farm = FarmModel(
      id: 'farm-1',
      customerId: 'customer-1',
      sector: PoultrySector.broiler,
      name: 'North Farm',
      location: 'Giza',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final house = HouseModel(
      id: 'house-1',
      farmId: farm.id,
      name: 'House 1',
      code: 'H1',
      capacity: 12000,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final placement = FlockPlacementModel(
      id: 'placement-1',
      flockId: 'flock-1',
      houseId: house.id,
      placedBirds: 11500,
      placedAt: DateTime.utc(2026, 7, 1),
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    expect(CustomerSectorModel.fromMap(sector.toMap()).sector, sector.sector);
    expect(CustomerSectorModel.fromMap(sector.toMap()).syncError, 'offline');
    expect(FarmModel.fromMap(farm.toMap()).sector, PoultrySector.broiler);
    expect(HouseModel.fromMap(house.toMap()).capacity, 12000);
    expect(
      FlockPlacementModel.fromMap(placement.toMap()).status,
      PlacementStatus.active,
    );
  });

  test('placement rejects an empty flock and non-positive bird count', () {
    expect(
      () => FlockPlacementModel(
        id: 'placement-1',
        flockId: '',
        houseId: 'house-1',
        placedBirds: 100,
        placedAt: DateTime.utc(2026, 7, 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => FlockPlacementModel(
        id: 'placement-2',
        flockId: 'flock-1',
        houseId: 'house-1',
        placedBirds: 0,
        placedAt: DateTime.utc(2026, 7, 1),
      ),
      throwsArgumentError,
    );
  });
}
