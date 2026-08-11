import '../models/customer_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'sync_tombstone_repository.dart';

class CustomerRepository {
  CustomerRepository({DatabaseHelper? dbHelper})
    : dbHelper = dbHelper ?? DatabaseHelper();
  final DatabaseHelper dbHelper;

  static const _table = 'customers';

  String _nowStamp() => DateTime.now().toIso8601String();

  /// dirtyAt value captured at the last getDirtyRows() call. markRowsSynced
  /// only clears rows whose dirtyAt is at or before this cutoff, so an edit
  /// landing while a push is in flight stays pending.
  String? _dirtyReadCutoff;

  Future<List<Map<String, dynamic>>> getDirtyRows() async {
    final db = await dbHelper.db;
    _dirtyReadCutoff = _nowStamp();
    final rows = await db.query(
      _table,
      where: "syncStatus IN ('pending', 'failed')",
      orderBy: 'dirtyAt ASC, id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> markRowsSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final cutoff = _dirtyReadCutoff ?? _nowStamp();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _table,
      {
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      },
      where: 'id IN ($placeholders) AND (dirtyAt IS NULL OR dirtyAt <= ?)',
      whereArgs: [...ids, cutoff],
    );
  }

  Future<void> markRowsFailed(List<String> ids, Object error) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.update(
      _table,
      {'syncStatus': 'failed', 'syncError': error.toString()},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<String?> getRowSyncStatus(String id) async {
    final db = await dbHelper.db;
    final rows = await db.query(
      _table,
      columns: ['syncStatus'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['syncStatus']?.toString();
  }

  Future<void> insertCustomer(CustomerModel customer) async {
    final db = await dbHelper.db;
    await _upsertById(db, 'customers', {
      ...customer.toMap(),
      'syncStatus': 'pending',
      'dirtyAt': _nowStamp(),
    });
  }

  Future<List<CustomerModel>> getAllCustomers() async {
    final db = await dbHelper.db;
    final result = await db.query('customers');
    return result.map((e) => CustomerModel.fromMap(e)).toList();
  }

  Future<CustomerModel?> getCustomerById(String id) async {
    final db = await dbHelper.db;
    final result = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isNotEmpty) {
      return CustomerModel.fromMap(result.first);
    }
    return null;
  }

  Future<void> updateCustomer(CustomerModel customer) async {
    final db = await dbHelper.db;
    await db.update(
      'customers',
      {
        ...customer.toMap(),
        'syncStatus': 'pending',
        'dirtyAt': _nowStamp(),
      },
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> deleteCustomer(String id) async {
    final db = await dbHelper.db;
    await db.transaction<void>((txn) async {
      await SyncTombstoneRepository.queueDeleteWithExecutor(
        txn,
        'customers',
        id,
      );
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> upsertCustomer(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'customers');
    final normalized = _filterColumns(_normalizeCustomerRow(row), columns)
      ..addAll({
        'syncStatus': 'synced',
        'dirtyAt': null,
        'lastSyncedAt': _nowStamp(),
        'syncError': null,
      });
    await _upsertById(db, 'customers', normalized);
  }

  Future<void> _upsertById(
    Database db,
    String table,
    Map<String, dynamic> row,
  ) async {
    final inserted = await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    await db.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
  }

  Future<Set<String>> _tableColumns(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  Map<String, dynamic> _filterColumns(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    return Map.fromEntries(
      row.entries.where((entry) {
        return columns.contains(entry.key);
      }),
    );
  }

  Map<String, dynamic> _normalizeCustomerRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      normalized[_camelize(entry.key)] = entry.value;
    }
    return normalized;
  }

  String _camelize(String key) {
    if (!key.contains('_')) return key;
    final parts = key.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }
}
