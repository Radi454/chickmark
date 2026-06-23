import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/panel_sample_schema.dart';
import 'seeds/bmk_seeds.dart' hide kTroubleshootingSeeds;
import 'seeds/dashboard_demo_seeds.dart';
import 'seeds/dummy_data_seeds.dart';
import 'seeds/troubleshooting_seeds.dart';

part 'database_schema.dart';
part 'database_migrations.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  /// When true, a database open seeds the Dashboard demo customer (debug aid).
  /// Off by default so unit/widget tests open a clean DB; the app turns it on
  /// at startup (see `main`) and end-to-end seed tests opt in explicitly.
  static bool seedDemoData = false;

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
      version: 45,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _surgicalSchemaRepair(db);
        await _dropPanelUniqueRowIndexes(db);
        await _dropDeprecatedPanelColumns(db);
        await _ensurePanelSampleSchemaColumns(db);
        await _ensurePanelUniqueRowIndexes(db);
        await db.execute('PRAGMA foreign_keys = ON');
        if (seedDemoData) await ensureDashboardDemoData(db);
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
    await _createCoreTablesIfMissing(db);
    await _createCleanBmkEggBreakoutTable(db);
    await _createBmkOperationalStandardsTable(db);
    await _createHatcheryTables(db);
    await _createAuditSessionTables(db);
    await _createPanelSampleSchemaTables(db);
    await _createSyncTombstoneTable(db);
    await _createSyncConflictTable(db);
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
      for (final seed in kBmkOperationalStandardSeeds) {
        batch.insert(
          'bmk_operational_standards',
          seed,
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

  /// Critical tables the surgical repair pass guarantees exist. Panel sample
  /// tables are appended dynamically from `PanelSampleSchema.panels`.
  static const _criticalTables = <String>[
    'users',
    'customers',
    'flocks',
    'hatcheries',
    'audit_sessions',
    'photos',
    'activity_log',
    'sync_tombstones',
    'sync_conflicts',
    'bmk_breeds',
    'bmk_egg_breakout',
    'bmk_operational_standards',
    'troubleshooting',
    'govee_daily_captures',
  ];

  /// Expected columns for tables most likely to drift after manual edits or
  /// future migrations. Missing columns are added via ALTER TABLE ADD COLUMN
  /// during surgical repair. Existing rows keep their values (NULL for new
  /// columns without DEFAULT clauses).
  static const Map<String, List<String>> _criticalColumns = {
    'audit_sessions': [
      'customerId TEXT NOT NULL',
      'flockId TEXT NOT NULL',
      'hatcheryId TEXT NOT NULL',
      'date TEXT NOT NULL',
      'breed TEXT',
      'flockAgeWeeks INTEGER',
      "status TEXT DEFAULT 'in_progress'",
      'selectedStationKeys TEXT',
      'stationsCompleted TEXT',
      'findingsJson TEXT',
      'scorecardJson TEXT',
      'notes TEXT',
      'createdBy TEXT',
      'createdAt TEXT',
      'updatedAt TEXT',
      'completedAt TEXT',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'sync_conflicts': [
      'tableName TEXT NOT NULL',
      'rowId TEXT NOT NULL',
      'localUpdatedAt TEXT',
      'remoteUpdatedAt TEXT',
      'winner TEXT NOT NULL',
      'detectedAt TEXT NOT NULL',
      'reviewedAt TEXT',
      'reviewedBy TEXT',
    ],
    'sync_tombstones': [
      'tableName TEXT NOT NULL',
      'rowId TEXT NOT NULL',
      'deletedAt TEXT NOT NULL',
      'createdAt TEXT NOT NULL',
      'syncedAt TEXT',
      'lastError TEXT',
    ],
    // Per-row dirty-tracking columns added to the bulk-synced Govee table so an
    // existing database gains them via ALTER (no destructive reset needed).
    'govee_daily_captures': [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
  };

  /// Surgical schema repair: detect missing tables/columns/indexes and restore
  /// them in place. **Never drops, recreates, or reseeds intact tables** — only
  /// the specific objects detected as missing are created. Existing user data
  /// is preserved bit-for-bit.
  ///
  /// Replaces the previous destructive heal, which reset the entire DB if a
  /// single table was missing.
  Future<void> _surgicalSchemaRepair(Database db) async {
    final report = <String>[];

    final missingTables = <String>[];
    for (final table in _criticalTables) {
      if (!await _tableExists(db, table)) missingTables.add(table);
    }
    for (final panel in PanelSampleSchema.panels) {
      if (!await _tableExists(db, panel.tableName)) {
        missingTables.add(panel.tableName);
      }
    }

    // Step 1: column-level repair FIRST. An existing critical table that
    // drifted (missing columns) gets them via ALTER before any index below
    // references them — otherwise CREATE INDEX idx_audit_sessions_sync ON
    // (syncStatus), which lives inside _createAuditSessionTables, throws
    // "no such column: syncStatus" on a pre-existing drifted table. Guarded by
    // _tableExists, so genuinely missing tables are skipped here and created
    // whole (columns + indexes) in Step 2.
    final addedColumns = await _repairCriticalColumns(db);
    if (addedColumns.isNotEmpty) {
      report.add('columns added: ${addedColumns.join(", ")}');
    }

    // Step 2: idempotent CREATE TABLE / INDEX IF NOT EXISTS for every critical
    // table. Tables that already exist are untouched; their indexes now find
    // the columns repaired in Step 1. Missing tables are created whole.
    await _createCoreTablesIfMissing(db);
    await _createCleanBmkEggBreakoutTable(db);
    await _createBmkOperationalStandardsTable(db);
    await _createHatcheryTables(db);
    await _createAuditSessionTables(db);
    await _createPanelSampleSchemaTables(db);
    await _createSyncTombstoneTable(db);
    await _createSyncConflictTable(db);
    await _createGoveeCaptureTables(db);

    if (missingTables.isNotEmpty) {
      report.add('tables restored: ${missingTables.join(", ")}');
    }

    // Step 3: idempotent CREATE INDEX IF NOT EXISTS for operational indexes
    // and panel unique row indexes.
    await _createOperationalIndexes(db);
    await _createActivityLogIndexes(db);
    await _ensurePanelUniqueRowIndexes(db);

    // Step 4: re-seed reference data **only for tables that were missing**.
    // Intact bmk_breeds / bmk_egg_breakout / troubleshooting rows (including
    // any user overrides) are not touched.
    if (missingTables.contains('bmk_breeds') ||
        missingTables.contains('bmk_egg_breakout') ||
        missingTables.contains('bmk_operational_standards')) {
      await _reseedReferenceBmkData(db);
      report.add('reseeded bmk reference rows');
    }
    if (missingTables.contains('troubleshooting')) {
      await _seedTroubleshooting(db);
      report.add('reseeded troubleshooting');
    }

    if (report.isNotEmpty) {
      debugPrint('[DB REPAIR] ${report.join(" | ")}');
    }
  }

  /// For every entry in [_criticalColumns], ALTER TABLE ADD COLUMN any missing
  /// columns. Returns a list of `table.column` strings actually added.
  Future<List<String>> _repairCriticalColumns(Database db) async {
    final added = <String>[];
    for (final entry in _criticalColumns.entries) {
      final table = entry.key;
      if (!await _tableExists(db, table)) continue;
      final existing = _columnNames(
        await db.rawQuery('PRAGMA table_info($table)'),
      );
      for (final definition in entry.value) {
        final name = _columnNameFromDefinition(definition);
        if (existing.contains(name)) continue;
        // SQLite forbids ADD COLUMN with NOT NULL unless a DEFAULT or the
        // table is empty. Strip a bare NOT NULL constraint to keep the add
        // safe; the application layer enforces non-nullness at write time.
        final safeDefinition = definition.replaceAll(
          RegExp(r'\s+NOT\s+NULL', caseSensitive: false),
          '',
        );
        await db.execute('ALTER TABLE $table ADD COLUMN $safeDefinition');
        added.add('$table.$name');
      }
    }
    return added;
  }

  /// Re-apply BMK reference data using REPLACE. Existing rows that share a
  /// seed PK are refreshed; user-added rows with other PKs survive untouched.
  Future<void> _reseedReferenceBmkData(Database db) async {
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
      for (final seed in kBmkOperationalStandardSeeds) {
        batch.insert(
          'bmk_operational_standards',
          seed,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    await _ensureCompleteBmkBreedSeedData(db);
    await _backfillEggBreakoutAliases(db);
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
      'sync_conflicts',
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
