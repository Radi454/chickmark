import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/flock_model.dart';
import '../models/poultry_hierarchy_models.dart';

class ActiveHousePlacementConflict implements Exception {
  ActiveHousePlacementConflict(this.houseId);

  final String houseId;

  @override
  String toString() => 'House $houseId already has an active flock placement';
}

class SectorNotEnabledException implements Exception {
  SectorNotEnabledException(this.customerId, this.sector);

  final String customerId;
  final PoultrySector sector;

  @override
  String toString() =>
      '${sector.storageKey} is not enabled for customer $customerId';
}

class PoultryHierarchyRepository {
  PoultryHierarchyRepository({
    DatabaseHelper? dbHelper,
    Uuid uuid = const Uuid(),
  }) : _dbHelper = dbHelper ?? DatabaseHelper(),
       _uuid = uuid;

  final DatabaseHelper _dbHelper;
  final Uuid _uuid;

  Future<List<CustomerSectorModel>> listCustomerSectors(
    String customerId,
  ) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'customer_sectors',
      where: 'customerId = ?',
      whereArgs: [customerId],
      orderBy: 'sectorKey',
    );
    return rows.map(CustomerSectorModel.fromMap).toList();
  }

  Future<void> replaceCustomerSectors(
    String customerId,
    Set<PoultrySector> sectors,
  ) async {
    await _dbHelper.assertForeignKeys(customerId: customerId);
    final db = await _dbHelper.db;
    await db.transaction<void>((txn) async {
      final existingRows = await txn.query(
        'customer_sectors',
        where: 'customerId = ?',
        whereArgs: [customerId],
      );
      final existing = {
        for (final row in existingRows)
          PoultrySector.fromStorage(row['sectorKey']?.toString()): row,
      };
      for (final sector in PoultrySector.values) {
        final row = existing[sector];
        if (row == null && !sectors.contains(sector)) continue;
        final model = CustomerSectorModel(
          id: row?['id']?.toString() ?? _uuid.v4(),
          customerId: customerId,
          sector: sector,
          isActive: sectors.contains(sector),
          createdAt: _parseDate(row?['createdAt']),
        );
        await _upsertById(txn, 'customer_sectors', _localRow(model.toMap()));
      }
    });
  }

  Future<List<FarmModel>> listFarms(
    String customerId, {
    PoultrySector? sector,
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.db;
    final clauses = <String>['customerId = ?'];
    final args = <Object?>[customerId];
    if (sector != null) {
      clauses.add('sectorKey = ?');
      args.add(sector.storageKey);
    }
    if (activeOnly) clauses.add('isActive = 1');
    final rows = await db.query(
      'farms',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(FarmModel.fromMap).toList();
  }

  Future<void> saveFarm(FarmModel farm) async {
    final db = await _dbHelper.db;
    final enabled = await db.query(
      'customer_sectors',
      columns: ['id'],
      where: 'customerId = ? AND sectorKey = ? AND isActive = 1',
      whereArgs: [farm.customerId, farm.sector.storageKey],
      limit: 1,
    );
    if (enabled.isEmpty) {
      throw SectorNotEnabledException(farm.customerId, farm.sector);
    }
    await _upsertById(db, 'farms', _localRow(farm.toMap()));
  }

  Future<List<HouseModel>> listHouses(
    String farmId, {
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'houses',
      where: activeOnly ? 'farmId = ? AND isActive = 1' : 'farmId = ?',
      whereArgs: [farmId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(HouseModel.fromMap).toList();
  }

  Future<void> saveHouse(HouseModel house) async {
    final db = await _dbHelper.db;
    final farm = await db.query(
      'farms',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [house.farmId],
      limit: 1,
    );
    if (farm.isEmpty) {
      throw ArgumentError.value(house.farmId, 'farmId', 'Farm does not exist');
    }
    await _upsertById(db, 'houses', _localRow(house.toMap()));
  }

  Future<List<FlockPlacementModel>> listPlacements(
    String flockId, {
    bool activeOnly = false,
  }) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'flock_placements',
      where: activeOnly
          ? "flockId = ? AND status = 'active' AND endedAt IS NULL"
          : 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'placedAt, houseId',
    );
    return rows.map(FlockPlacementModel.fromMap).toList();
  }

  Future<void> createBroilerFlockWithPlacements(
    FlockModel flock,
    List<FlockPlacementModel> placements,
  ) async {
    if (flock.sector != PoultrySector.broiler || flock.farmId == null) {
      throw ArgumentError('A new Broiler flock requires a Broiler farm');
    }
    if (placements.isEmpty) {
      throw ArgumentError.value(placements, 'placements', 'Must not be empty');
    }
    if (placements.any((placement) => placement.flockId != flock.id)) {
      throw ArgumentError('Every placement must belong to the new flock');
    }

    final db = await _dbHelper.db;
    try {
      await db.transaction<void>((txn) async {
        final houseIds = placements
            .map((placement) => placement.houseId)
            .toSet()
            .toList();
        final placeholders = List.filled(houseIds.length, '?').join(', ');
        final houseRows = await txn.rawQuery(
          'SELECT id FROM houses WHERE farmId = ? '
          'AND id IN ($placeholders)',
          [flock.farmId, ...houseIds],
        );
        if (houseRows.length != houseIds.length) {
          throw ArgumentError('Every placement house must belong to the farm');
        }
        await txn.insert(
          'flocks',
          _localRow(flock.toMap(), includeCreatedAt: false),
        );
        for (final placement in placements) {
          await txn.insert('flock_placements', _localRow(placement.toMap()));
        }
      });
    } on DatabaseException catch (error) {
      _throwPlacementConflict(error, placements.map((row) => row.houseId));
      rethrow;
    }
  }

  Future<void> createPlacement(FlockPlacementModel placement) async {
    final db = await _dbHelper.db;
    try {
      await db.insert('flock_placements', _localRow(placement.toMap()));
    } on DatabaseException catch (error) {
      _throwPlacementConflict(error, [placement.houseId]);
      rethrow;
    }
  }

  Future<void> endPlacement(String placementId, DateTime endedAt) async {
    final db = await _dbHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'flock_placements',
      {
        'endedAt': endedAt.toUtc().toIso8601String(),
        'status': PlacementStatus.ended.storageKey,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [placementId],
    );
  }

  void _throwPlacementConflict(
    DatabaseException error,
    Iterable<String> houseIds,
  ) {
    final message = error.toString();
    if (message.contains('idx_active_placement_per_house') ||
        message.contains('flock_placements.houseId')) {
      throw ActiveHousePlacementConflict(houseIds.first);
    }
  }
}

Map<String, dynamic> _localRow(
  Map<String, dynamic> row, {
  bool includeCreatedAt = true,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    ...row,
    if (includeCreatedAt) 'createdAt': row['createdAt'] ?? now,
    'updatedAt': now,
    'syncStatus': 'pending',
    'dirtyAt': now,
    'syncError': null,
  };
}

Future<void> _upsertById(
  DatabaseExecutor db,
  String table,
  Map<String, dynamic> row,
) async {
  final existing = await db.query(
    table,
    columns: ['id'],
    where: 'id = ?',
    whereArgs: [row['id']],
    limit: 1,
  );
  if (existing.isEmpty) {
    await db.insert(table, row);
    return;
  }
  await db.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
}

DateTime? _parseDate(Object? value) {
  return value == null ? null : DateTime.tryParse(value.toString());
}
