import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/panel_sample_schema.dart';
import 'seeds/bmk_seeds.dart' hide kTroubleshootingSeeds;
import 'seeds/dummy_data_seeds.dart';
import 'seeds/troubleshooting_seeds.dart';

part 'database_schema.dart';
part 'database_migrations.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await _databasePath();
    _db = await _openDatabaseWithRecovery(dbPath);
    return _db!;
  }

  Future<Database> _openDatabaseWithRecovery(String dbPath) async {
    try {
      return await _openAppDatabase(dbPath);
    } catch (error) {
      if (!_shouldRecreateLocalDatabase(error)) rethrow;
      await deleteDatabase(dbPath);
      return _openAppDatabase(dbPath);
    }
  }

  Future<Database> _openAppDatabase(String dbPath) {
    return openDatabase(
      dbPath,
      version: 41,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _dropPanelUniqueRowIndexes(db);
        await _dropDeprecatedPanelColumns(db);
        await _ensurePanelSampleSchemaColumns(db);
        await _ensurePanelUniqueRowIndexes(db);
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  bool _shouldRecreateLocalDatabase(Object error) {
    if (kReleaseMode) return false;
    if (error is DatabaseException) {
      final resultCode = error.getResultCode();
      if (resultCode == 11 || resultCode == 26) return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('malformed database schema') ||
        message.contains('database disk image is malformed') ||
        message.contains('file is not a database');
  }

  Future<String> _databasePath() async {
    if (kIsWeb) return 'hatchaudit.db';
    return join(await getDatabasesPath(), 'hatchaudit.db');
  }

  Future<void> close() async {
    if (_db == null) return;
    await _db!.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE users (
      id TEXT PRIMARY KEY,
      fullName TEXT,
      email TEXT UNIQUE,
      role TEXT,
      status TEXT,
      customerId TEXT,
      accessToken TEXT,
      tokenExpiry TEXT,
      createdAt TEXT,
      lastLoginAt TEXT
    )''');
    await db.execute('''CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      name TEXT,
      location TEXT,
      phone TEXT,
      email TEXT,
      createdAt TEXT,
      createdBy TEXT
    )''');
    await db.execute('''CREATE TABLE flocks (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      flockId TEXT,
      breed TEXT,
      entryDate TEXT,
      isAgeEstimated INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      depletionAgeWeeks INTEGER NOT NULL DEFAULT 65,
      soldAt TEXT,
      FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE bmk_breeds (
      id TEXT PRIMARY KEY,
      breed TEXT NOT NULL,
      ageWeek INTEGER NOT NULL,
      hatchabilityPct REAL DEFAULT 0.0,
      fertilityPct REAL DEFAULT 0.0,
      hofPct REAL DEFAULT 0.0,
      productionPct REAL DEFAULT 0.0,
      eggWeightG REAL DEFAULT 0.0,
      chickWeightG REAL DEFAULT 0.0
    )''');
    await _createCleanBmkEggBreakoutTable(db);
    await db.execute('''CREATE TABLE troubleshooting (
      id TEXT PRIMARY KEY,
      hatcheryCauses TEXT,
      farmFlockCauses TEXT,
      benchmarkJson TEXT,
      interpretationJson TEXT,
      sourceRefsJson TEXT
    )''');
    await db.execute('''CREATE TABLE photos (
      id TEXT PRIMARY KEY,
      filePath TEXT,
      description TEXT,
      createdAt TEXT,
      sessionId TEXT NOT NULL,
      panelName TEXT NOT NULL,
      panelRowId TEXT NOT NULL,
      fieldKey TEXT NOT NULL,
      uploadStatus TEXT NOT NULL DEFAULT 'local',
      FOREIGN KEY (sessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE activity_log (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL,
      action TEXT NOT NULL,
      entityType TEXT,
      entityId TEXT,
      details TEXT,
      timestamp TEXT NOT NULL
    )''');
    await _createHatcheryTables(db);
    await _createAuditSessionTables(db);
    await _createPanelSampleSchemaTables(db);
    await _createSyncTombstoneTable(db);
    await _createGoveeCaptureTables(db);
    await _createOperationalIndexes(db);
    await _createActivityLogIndexes(db);
    // Seed data
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final seed in kBmkBreedSeeds) {
        batch.insert(
          'bmk_breeds',
          seed,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final seed in kBmkEggBreakoutSeeds) {
        batch.insert(
          'bmk_egg_breakout',
          _cleanBmkEggBreakoutSeed(seed),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    await _ensureCompleteBmkBreedSeedData(db);
    await _backfillEggBreakoutAliases(db);
    await _seedTroubleshooting(db);
    await _ensureDummyTestData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _resetForPanelCutover(db, newVersion);
  }

  Future<void> _resetForPanelCutover(Database db, int newVersion) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    const tables = [
      'egg_storage',
      'egg_storage_samples',
      'egg_quality',
      'egg_quality_samples',
      'egg_weights',
      'egg_weights_samples',
      'chick_quality',
      'chick_quality_samples',
      'chick_pasgar',
      'chick_pasgar_samples',
      'chick_weights',
      'chick_weights_samples',
      'chick_yfbm',
      'chick_yfbm_samples',
      'chick_cvt',
      'chick_cvt_samples',
      'chick_pm',
      'chick_pm_samples',
      'fresh_egg_breakout',
      'fresh_egg_breakout_samples',
      'candled_egg_breakout',
      'candled_egg_breakout_samples',
      'residue_breakout',
      'residue_breakout_samples',
      'setter_optimizing',
      'setter_optimizing_samples',
      'hatcher_optimizing',
      'hatcher_optimizing_samples',
      'sample_house_details',
      'sample_machine_details',
      'sample_batch_details',
      'sample_timing_details',
      'sample_records',
      'station_samples',
      'photos',
      'govee_daily_captures',
      'govee_place_readings',
      'govee_spot_captures',
      'govee_spot_readings',
      'temperature_sessions',
      'temperature_readings',
      'sync_tombstones',
      'audits',
      'audit_sessions',
      'hatcheries',
      'flocks',
      'customers',
      'users',
      'activity_log',
      'troubleshooting',
      'bmk_egg_breakout',
      'bmk_breeds',
    ];
    for (final table in tables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    await db.execute('PRAGMA foreign_keys = ON');
    await _onCreate(db, newVersion);
  }

  @visibleForTesting
  Future<void> applyV18UpgradeForTest(Database db) => _applyV18Upgrade(db);

  @visibleForTesting
  Future<void> applyV19UpgradeForTest(Database db) => _applyV19Upgrade(db);

  @visibleForTesting
  Future<void> applyV20UpgradeForTest(Database db) => _applyV20Upgrade(db);

  @visibleForTesting
  Future<void> applyV21UpgradeForTest(Database db) => _applyV21Upgrade(db);

  @visibleForTesting
  Future<void> applyV22UpgradeForTest(Database db) => _applyV22Upgrade(db);

  @visibleForTesting
  Future<void> applyV23UpgradeForTest(Database db) => _applyV23Upgrade(db);

  @visibleForTesting
  Future<void> applyV24UpgradeForTest(Database db) => _applyV24Upgrade(db);

  @visibleForTesting
  Future<void> applyV25UpgradeForTest(Database db) => _applyV25Upgrade(db);

  @visibleForTesting
  Future<void> applyV26UpgradeForTest(Database db) => _applyV26Upgrade(db);

  @visibleForTesting
  Future<void> applyV27UpgradeForTest(Database db) => _applyV27Upgrade(db);

  @visibleForTesting
  Future<void> applyV28UpgradeForTest(Database db) => _applyV28Upgrade(db);

  @visibleForTesting
  Future<void> applyV29UpgradeForTest(Database db) => _applyV29Upgrade(db);

  @visibleForTesting
  Future<void> applyV30UpgradeForTest(Database db) => _applyV30Upgrade(db);

  @visibleForTesting
  Future<void> applyV31UpgradeForTest(Database db) => _applyV31Upgrade(db);

  @visibleForTesting
  Future<void> applyV32UpgradeForTest(Database db) => _applyV32Upgrade(db);

  @visibleForTesting
  Future<void> applyV33UpgradeForTest(Database db) => _applyV33Upgrade(db);

  @visibleForTesting
  Future<void> applyV34UpgradeForTest(Database db) => _applyV34Upgrade(db);

  @visibleForTesting
  Future<void> applyV35UpgradeForTest(Database db) => _applyV35Upgrade(db);

  Future<bool> customerExists(String customerId) async {
    final db = await this.db;
    final result = await db.query(
      'customers',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> flockExists(String flockId) async {
    final db = await this.db;
    final result = await db.query(
      'flocks',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [flockId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> hatcheryExists(String hatcheryId) async {
    final db = await this.db;
    final result = await db.query(
      'hatcheries',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [hatcheryId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> assertForeignKeys({
    String? customerId,
    String? flockId,
    String? hatcheryId,
  }) async {
    if (customerId != null && customerId.isNotEmpty) {
      final exists = await customerExists(customerId);
      if (!exists) {
        throw Exception('Customer $customerId does not exist');
      }
    }
    if (flockId != null && flockId.isNotEmpty) {
      final exists = await flockExists(flockId);
      if (!exists) {
        throw Exception('Flock $flockId does not exist');
      }
    }
    if (hatcheryId != null && hatcheryId.isNotEmpty) {
      final exists = await hatcheryExists(hatcheryId);
      if (!exists) {
        throw Exception('Hatchery $hatcheryId does not exist');
      }
    }
  }
}
