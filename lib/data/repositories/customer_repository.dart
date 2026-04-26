import '../models/customer_model.dart';
import '../database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class CustomerRepository {
  final dbHelper = DatabaseHelper();

  Future<void> insertCustomer(CustomerModel customer) async {
    final db = await dbHelper.db;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> deleteCustomer(String id) async {
    final db = await dbHelper.db;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertCustomer(Map<String, dynamic> row) async {
    final db = await dbHelper.db;
    final columns = await _tableColumns(db, 'customers');
    final normalized = _filterColumns(_normalizeCustomerRow(row), columns);
    await db.insert(
      'customers',
      normalized,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
