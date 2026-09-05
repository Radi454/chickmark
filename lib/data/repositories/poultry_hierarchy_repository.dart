import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/poultry_hierarchy_models.dart';

class SectorNotEnabledException implements Exception {
  SectorNotEnabledException(this.customerId, this.sector);

  final String customerId;
  final PoultrySector sector;

  @override
  String toString() =>
      '${sector.storageKey} is not enabled for customer $customerId';
}

/// Reads and writes the customer-sector membership and the flock-owned house
/// hierarchy. A farm and a flock are the same thing in this business, so
/// houses belong directly to a flock (`houses.flockId`) rather than to a
/// separate farm; there is no farm entity and no placement table.
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

  Future<List<HouseModel>> listHouses(
    String flockId, {
    bool activeOnly = true,
  }) async {
    final db = await _dbHelper.db;
    final rows = await db.query(
      'houses',
      where: activeOnly ? 'flockId = ? AND isActive = 1' : 'flockId = ?',
      whereArgs: [flockId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(HouseModel.fromMap).toList();
  }

  Future<void> saveHouse(HouseModel house) async {
    final db = await _dbHelper.db;
    final flock = await db.query(
      'flocks',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [house.flockId],
      limit: 1,
    );
    if (flock.isEmpty) {
      throw ArgumentError.value(
        house.flockId,
        'flockId',
        'Flock does not exist',
      );
    }
    await _upsertById(db, 'houses', _localRow(house.toMap()));
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
