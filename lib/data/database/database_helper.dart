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

  /// When true, a database open seeds the Dashboard demo customer for an
  /// explicitly opted-in test. Normal app startup and ordinary tests keep it
  /// disabled so local user data is never supplemented with demo rows.
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
      version: 57,
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
        await _ensurePanelQueryIndexes(db);
        await _ensurePanelUniqueRowIndexes(db);
        await db.execute('PRAGMA foreign_keys = ON');
        await _backfillOperationalBmkSeedSources(db);
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
    await _createDashboardActionTable(db);
    await _createLabAnalysisTables(db);
    await _createPerformanceMonitoringTables(db);
    await _createHatcheryAgentTables(db);
    await _createAgentIntakeTables(db);
    await _createUnifiedAgentHarnessTables(db);
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
    await _backfillOperationalBmkSeedSources(db);
    await _seedTroubleshooting(db);
    await _ensureDummyTestData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 41) {
      await _resetForPanelCutover(db, newVersion);
      return;
    }
    if (oldVersion < 46) {
      await _applyV46Upgrade(db);
    }
    if (oldVersion < 47) {
      await _applyV47Upgrade(db);
    }
    if (oldVersion < 48) {
      await _applyV48Upgrade(db);
    }
    if (oldVersion < 51) {
      await _applyV51Upgrade(db);
    }
    if (oldVersion < 52) {
      await _applyV52Upgrade(db);
    }
    if (oldVersion < 53) {
      await _applyV53Upgrade(db);
    }
    if (oldVersion < 54) {
      await _applyV54Upgrade(db);
    }
    if (oldVersion < 55) {
      await _applyV55Upgrade(db);
    }
    if (oldVersion < 56) {
      await _applyV56Upgrade(db);
    }
    if (oldVersion < 57) {
      await _applyV57Upgrade(db);
    }
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
    'dashboard_actions',
    'lab_analysis_reports',
    'lab_analysis_groups',
    'lab_analysis_rows',
    'customer_sectors',
    'farms',
    'houses',
    'flock_placements',
    'broiler_daily_records',
    'broiler_daily_record_revisions',
    'daily_record_sources',
    'broiler_daily_events',
    'broiler_target_profiles',
    'broiler_target_rows',
    'performance_alert_rules',
    'performance_concerns',
    'farm_visit_sessions',
    'farm_visit_houses',
    'visit_investigations',
    'visit_findings',
    'cause_assessments',
    'corrective_actions',
    'action_kpi_evaluations',
    'telegram_staff_links',
    'agent_settings',
    'agent_submissions',
    'agent_questions',
    'hatchery_draft_batches',
    'hatchery_draft_rows',
    'hatchery_agent_audit_events',
    'hatchery_daily_records',
    'agent_intake_sessions',
    'agent_intake_turns',
    'agent_intake_values',
    'agent_conversations',
    'agent_conversation_turns',
    'agent_tool_events',
    'agent_intake_visits',
  ];

  /// Expected columns for tables most likely to drift after manual edits or
  /// future migrations. Missing columns are added via ALTER TABLE ADD COLUMN
  /// during surgical repair. Existing rows keep their values (NULL for new
  /// columns without DEFAULT clauses).
  static const Map<String, List<String>> _criticalColumns = {
    'farms': ['sectorKey TEXT'],
    'customers': [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'flocks': [
      'farmId TEXT',
      'sectorKey TEXT',
      "sexProfile TEXT NOT NULL DEFAULT 'as_hatched'",
      'targetProfileId TEXT',
      'productionPhase TEXT',
      'updatedAt TEXT',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'hatcheries': [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'flock_placements': [
      'placedBirds INTEGER',
      'placedAt TEXT',
      'endedAt TEXT',
      "status TEXT NOT NULL DEFAULT 'active'",
    ],
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
    'bmk_operational_standards': [
      'sourceUrl TEXT',
      'sourcePhotoPath TEXT',
      'sourcePhotoRemotePath TEXT',
    ],
    'dashboard_actions': [
      'findingKey TEXT NOT NULL',
      'customerId TEXT NOT NULL',
      'hatcheryId TEXT NOT NULL',
      'flockId TEXT',
      'sessionId TEXT',
      'panelName TEXT',
      'panelRowId TEXT',
      'fieldKey TEXT',
      'metricKey TEXT',
      'title TEXT NOT NULL',
      'description TEXT',
      "priority TEXT NOT NULL DEFAULT 'watch'",
      "status TEXT NOT NULL DEFAULT 'open'",
      'ownerId TEXT',
      'ownerName TEXT',
      'dueAt TEXT',
      'firstObservedAt TEXT',
      'lastObservedAt TEXT',
      'resolvedAt TEXT',
      'resolutionNotes TEXT',
      'resolutionPhotoId TEXT',
      'recurrenceOfId TEXT',
      'createdBy TEXT',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'lab_analysis_reports': [
      'customerId TEXT NOT NULL',
      'flockId TEXT NOT NULL',
      'reportDate TEXT NOT NULL',
      'receivedDate TEXT',
      "labName TEXT NOT NULL DEFAULT ''",
      "sampleType TEXT NOT NULL DEFAULT ''",
      'flockAgeWeeks INTEGER',
      'title TEXT',
      'notes TEXT',
      'reportFileName TEXT',
      'reportFilePath TEXT',
      'reportFileRemotePath TEXT',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'lab_analysis_groups': [
      'reportId TEXT NOT NULL',
      'customerId TEXT NOT NULL',
      'flockId TEXT NOT NULL',
      'reportDate TEXT NOT NULL',
      'testType TEXT NOT NULL',
      "groupLabel TEXT NOT NULL DEFAULT ''",
      "sampleScope TEXT NOT NULL DEFAULT ''",
      "analyte TEXT NOT NULL DEFAULT ''",
      "method TEXT NOT NULL DEFAULT ''",
      "kitName TEXT NOT NULL DEFAULT ''",
      "productCode TEXT NOT NULL DEFAULT ''",
      "antigen TEXT NOT NULL DEFAULT ''",
      'sampleCount INTEGER',
      'meanTiter REAL',
      'minTiter REAL',
      'maxTiter REAL',
      'gmtTiter REAL',
      'cvPct REAL',
      'positiveCount INTEGER',
      'negativeCount INTEGER',
      'positivePct REAL',
      'cutoffValue REAL',
      'cutoffTiter REAL',
      'gmLog2 REAL',
      'protectiveThresholdLog2 REAL',
      'protectiveCount INTEGER',
      'protectivePct REAL',
      "interpretation TEXT NOT NULL DEFAULT ''",
      "severity TEXT NOT NULL DEFAULT 'normal'",
      'notes TEXT',
      'sortOrder INTEGER NOT NULL DEFAULT 0',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'lab_analysis_rows': [
      'groupId TEXT NOT NULL',
      'reportId TEXT NOT NULL',
      'customerId TEXT NOT NULL',
      'flockId TEXT NOT NULL',
      'reportDate TEXT NOT NULL',
      'testType TEXT NOT NULL',
      "rowLabel TEXT NOT NULL DEFAULT ''",
      "analyte TEXT NOT NULL DEFAULT ''",
      "result TEXT NOT NULL DEFAULT ''",
      "resultCategory TEXT NOT NULL DEFAULT ''",
      'numericValue REAL',
      "unit TEXT NOT NULL DEFAULT ''",
      'ctValue REAL',
      'odValue REAL',
      'spRatio REAL',
      'titer REAL',
      'titerGroup INTEGER',
      'hiLog2 INTEGER',
      'count INTEGER',
      "antibiotic TEXT NOT NULL DEFAULT ''",
      "sensitivityCategory TEXT NOT NULL DEFAULT ''",
      "interpretation TEXT NOT NULL DEFAULT ''",
      "severity TEXT NOT NULL DEFAULT 'normal'",
      'sortOrder INTEGER NOT NULL DEFAULT 0',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_submissions': [
      'sourceKind TEXT NOT NULL',
      'status TEXT NOT NULL',
      'submittedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'hatchery_draft_rows': [
      'batchId TEXT NOT NULL',
      'rowOrdinal INTEGER NOT NULL',
      'status TEXT NOT NULL',
      'customerName TEXT',
      'flockName TEXT',
      'stationName TEXT',
      'breed TEXT',
      'eggsPlaced INTEGER',
      'totalProduction INTEGER',
      'hatchabilityPct REAL',
      'confidencePct REAL',
      'warningsJson TEXT',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'hatchery_daily_records': [
      'customerId TEXT NOT NULL',
      'flockId TEXT NOT NULL',
      'stationName TEXT NOT NULL',
      'breed TEXT NOT NULL',
      'eggsPlaced INTEGER NOT NULL',
      'hatchDate TEXT NOT NULL',
      'totalProduction INTEGER NOT NULL',
      'hatchabilityPct REAL NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_intake_sessions': [
      'staffLinkId TEXT NOT NULL',
      'telegramChatId TEXT NOT NULL',
      'schemaKey TEXT NOT NULL',
      'schemaVersion INTEGER NOT NULL',
      'state TEXT NOT NULL',
      'language TEXT NOT NULL',
      'auditDate TEXT NOT NULL',
      "workingValuesJson TEXT NOT NULL DEFAULT '{}'",
      'summaryVersion INTEGER NOT NULL DEFAULT 0',
      'visitId TEXT',
      'rowVersion INTEGER NOT NULL DEFAULT 1',
      'lastToolEventId TEXT',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'telegram_staff_links': [
      "accessRole TEXT NOT NULL DEFAULT 'customer'",
      'customerId TEXT',
    ],
    'agent_conversations': [
      'staffLinkId TEXT NOT NULL',
      'telegramChatId TEXT NOT NULL',
      'stateVersion INTEGER NOT NULL DEFAULT 1',
      'contextEpoch INTEGER NOT NULL DEFAULT 1',
      'selectedCustomerId TEXT',
      'selectedFlockId TEXT',
      'selectedAuditId TEXT',
      'contextUpdatedAt TEXT',
      'pendingActionJson TEXT',
      'activeVisitId TEXT',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'synced'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_conversation_turns': [
      'conversationId TEXT NOT NULL',
      'direction TEXT NOT NULL',
      'turnIndex INTEGER',
      'contextEpoch INTEGER NOT NULL DEFAULT 1',
      'text TEXT NOT NULL',
      'language TEXT NOT NULL',
      'provider TEXT',
      'model TEXT',
      'providerResponseId TEXT',
      'replyToTurnId TEXT',
      'createdAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'synced'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_tool_events': [
      'conversationTurnId TEXT NOT NULL',
      'toolCallId TEXT NOT NULL',
      'toolName TEXT NOT NULL',
      'toolSequence INTEGER',
      "argumentsJson TEXT NOT NULL DEFAULT '{}'",
      'status TEXT NOT NULL',
      'createdAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'synced'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_intake_visits': [
      'conversationId TEXT NOT NULL',
      'auditDate TEXT NOT NULL',
      'state TEXT NOT NULL',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'synced'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_intake_turns': [
      'intakeSessionId TEXT NOT NULL',
      'direction TEXT NOT NULL',
      'text TEXT NOT NULL',
      'language TEXT NOT NULL',
      'createdAt TEXT NOT NULL',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ],
    'agent_intake_values': [
      'intakeSessionId TEXT NOT NULL',
      'fieldKey TEXT NOT NULL',
      'valueJson TEXT NOT NULL',
      'sourcePhrase TEXT NOT NULL',
      'confidence REAL NOT NULL',
      'createdAt TEXT NOT NULL',
      'updatedAt TEXT NOT NULL',
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
    await _createDashboardActionTable(db);
    await _createLabAnalysisTables(db);
    await _createPerformanceMonitoringTables(db);
    await _createHatcheryAgentTables(db);
    await _createAgentIntakeTables(db);
    await _createUnifiedAgentHarnessTables(db);

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
    await _backfillOperationalBmkSeedSources(db);
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
      'dashboard_actions',
      'lab_analysis_rows',
      'lab_analysis_groups',
      'lab_analysis_reports',
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

  @visibleForTesting
  Future<void> applyV46UpgradeForTest(Database db) => _applyV46Upgrade(db);

  @visibleForTesting
  Future<void> applyV47UpgradeForTest(Database db) => _applyV47Upgrade(db);

  @visibleForTesting
  Future<void> applyV48UpgradeForTest(Database db) => _applyV48Upgrade(db);

  @visibleForTesting
  Future<void> applyV51UpgradeForTest(Database db) => _applyV51Upgrade(db);

  @visibleForTesting
  Future<void> applyV52UpgradeForTest(Database db) => _applyV52Upgrade(db);

  @visibleForTesting
  Future<void> applyV53UpgradeForTest(Database db) => _applyV53Upgrade(db);

  @visibleForTesting
  Future<void> applyV54UpgradeForTest(Database db) => _applyV54Upgrade(db);

  @visibleForTesting
  Future<void> applyV55UpgradeForTest(Database db) => _applyV55Upgrade(db);

  @visibleForTesting
  Future<void> applyV56UpgradeForTest(Database db) => _applyV56Upgrade(db);

  @visibleForTesting
  Future<void> applyV57UpgradeForTest(Database db) => _applyV57Upgrade(db);

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
