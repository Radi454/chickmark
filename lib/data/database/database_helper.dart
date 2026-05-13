import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/panel_sample_schema.dart';
import '../models/station_sample_model.dart';
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
    _db = await openDatabase(
      await _databasePath(),
      version: 34,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
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
    await db.execute('''CREATE TABLE audits (
      id TEXT PRIMARY KEY,
      customerId TEXT,
      flockId TEXT,
      auditType TEXT,
      date TEXT,
      hatchNumber INTEGER NOT NULL DEFAULT 1,
      setterId TEXT,
      hatcherId TEXT,
      status TEXT,
      createdBy TEXT,
      createdAt TEXT,
      updatedAt TEXT,
      notes TEXT,
      sessionId TEXT,
      sampleMode TEXT NOT NULL DEFAULT 'pool',
      compareGroupKey TEXT,
      -- Chicks: CHA Environmental
      chaCo2 REAL,
      chaCo2Photo TEXT,
      chaPm10 REAL,
      chaPm10Photo TEXT,
      chaPm25 REAL,
      chaPm25Photo TEXT,
      chaAirVelocitySpot1 REAL,
      chaAirVelocitySpot1Photo TEXT,
      chaAirVelocitySpot2 REAL,
      chaAirVelocitySpot2Photo TEXT,
      chaAirVelocitySpot3 REAL,
      chaAirVelocitySpot3Photo TEXT,
      chaAirInlet REAL,
      chaAirInletPhoto TEXT,
      chaAirOutlet REAL,
      chaAirOutletPhoto TEXT,
      chaNoiseLevel REAL,
      chaNoiseLevelPhoto TEXT,
      -- Chicks: Pasgar
      pasgarSampleSize INTEGER,
      pasgarReflexes INTEGER,
      pasgarReflexesPhoto TEXT,
      pasgarBeak INTEGER,
      pasgarBeakPhoto TEXT,
      pasgarNavel INTEGER,
      pasgarNavelPhoto TEXT,
      pasgarBelly INTEGER,
      pasgarBellyPhoto TEXT,
      pasgarLeg INTEGER,
      pasgarLegPhoto TEXT,
      pasgarFeatherDev INTEGER,
      pasgarFeatherDevPhoto TEXT,
      pasgarFinalScore REAL,
      -- Chicks: Weights
      chickStorageDays INTEGER,
      chickSampleSize INTEGER,
      chickWeights TEXT,
      chickAvgWeight REAL,
      chickUniformityPct REAL,
      chickCvPct REAL,
      chickBmkAge INTEGER,
      chickBmkWeight REAL,
      -- Chicks: YFBM
      yfbmPhoto TEXT,
      yfbmEntries TEXT,
      yfbmAvgPct REAL,
      yfbmCvPct REAL,
      -- Chicks: CVT
      cvtSampleSize INTEGER,
      cvtTopBasket TEXT,
      cvtTopTemp REAL,
      cvtTopPhoto TEXT,
      cvtMiddleBasket TEXT,
      cvtMiddleTemp REAL,
      cvtMiddlePhoto TEXT,
      cvtBottomBasket TEXT,
      cvtBottomTemp REAL,
      cvtBottomPhoto TEXT,
      cvtAvg REAL,
      cvtCvPct REAL,
      cvtReadingsJson TEXT,
      cvtPhotosJson TEXT,
      -- Hatch Analysis & Egg Breakouts: Hatch Results
      haStorageDays INTEGER,
      haTotalEggsSet INTEGER,
      haHatched INTEGER,
      haCulled INTEGER,
      haDead INTEGER,
      haHatchability REAL,
      haFertility REAL,
      haHof REAL,
      haTrays TEXT,
      haBmkAge INTEGER,
      haPipped INTEGER,
      haInfertileClear INTEGER,
      haEarlyDead INTEGER,
      haMidDead INTEGER,
      haMidLateDead INTEGER,
      haLateDead INTEGER,
      haContaminatedExploders INTEGER,
      haBenchmarkStatusesJson TEXT,
      -- Hatch Analysis & Egg Breakouts: Egg Breakout
      ebTraySize INTEGER,
      ebBreakoutType TEXT,
      ebBreakoutAgeDays INTEGER,
      ebStorageDays INTEGER,
      ebTrays TEXT,
      ebTrayBreakoutJson TEXT,
      ebBmkAge INTEGER,
      ebInfertileCount INTEGER,
      ebEarlyDeadCount INTEGER,
      ebMidDeadCount INTEGER,
      ebLateDeadCount INTEGER,
      ebInternalPipCount INTEGER,
      ebExternalPipCount INTEGER,
      ebCrackedCount INTEGER,
      ebContaminatedCount INTEGER,
      ebMalpositionCount INTEGER,
      ebExposedBrainCount INTEGER,
      ebCrossedBeakCount INTEGER,
      ebCulledDeadCount INTEGER,
      -- Setters
      soBreed TEXT,
      soSetterId TEXT,
      soIncubationAge INTEGER,
      soIncubationHours INTEGER,
      soCo2 REAL,
      soCo2Photo TEXT,
      soEstReadings TEXT,
      soEstPhotos TEXT,
      soEstAvg REAL,
      soEstCv REAL,
      -- Hatchers
      hoBreed TEXT,
      hoHatcherId TEXT,
      hoIncubationAge INTEGER,
      hoIncubationHours INTEGER,
      hoCo2 REAL,
      hoCo2Photo TEXT,
      hoCvtReadings TEXT,
      hoCvtPhotos TEXT,
      hoCvtAvg REAL,
      hoCvtCv REAL,
      hoChickPanting INTEGER,
      hoChickPantingPhoto TEXT,
      ho_meconium TEXT,
      ho_transferDay INTEGER,
      -- Egg
      esCo2 REAL,
      esCo2Photo TEXT,
      esShellTemp REAL,
      esShellTempPhoto TEXT,
      esTurningTimes INTEGER,
      esUvTrays TEXT,
      esEggStorageDays INTEGER,
      esEggSampleSize INTEGER,
      esEggWeights TEXT,
      esEggAvgWeight REAL,
      esEggUniformityPct REAL,
      esEggCvPct REAL,
      esEggBmkAge INTEGER,
      esEggBmkWeight REAL,
      es_estReadingsJson TEXT,
      es_estPhotosJson TEXT,
      es_estAvg REAL,
      es_estCv REAL,
      es_uvSampleSize INTEGER,
      es_uvCuticleDamageCount INTEGER,
      es_uvWashingEvidenceCount INTEGER,
      es_uvFecalCount INTEGER,
      es_uvMottledCount INTEGER,
      es_uvOtherCount INTEGER,
      es_uvPhotosJson TEXT,
      es_crackPct REAL,
      es_brokenPct REAL,
      es_misshapedPct REAL,
      es_paleShellPct REAL,
      es_roughTexturePct REAL,
      es_floorEggPct REAL,
      es_eggColorDistJson TEXT,
      es_eggOrientation TEXT,
      es_traySpacing TEXT,
      es_coolerProximity TEXT,
      es_wallProximity TEXT,
      es_condensation INTEGER,
      pm_sampleSize INTEGER,
      pm_collectionPoint TEXT,
      pm_omphalitisCount INTEGER,
      pm_omphalitisSeverity TEXT,
      pm_gaseousCecaCount INTEGER,
      pm_gaseousCecaSeverity TEXT,
      pm_unabsorbedYolkCount INTEGER,
      pm_unabsorbedYolkSeverity TEXT,
      pm_perihepatitisCount INTEGER,
      pm_perihepatitisSeverity TEXT,
      pm_pericarditisCount INTEGER,
      pm_pericarditisSeverity TEXT,
      pm_airsacAcuteCount INTEGER,
      pm_airsacAcuteSeverity TEXT,
      pm_airsacChronicCount INTEGER,
      pm_airsacChronicSeverity TEXT,
      pm_pulmonaryGranulomaCount INTEGER,
      pm_pulmonaryGranulomaSeverity TEXT,
      pm_swollenJointsCount INTEGER,
      pm_swollenJointsSeverity TEXT,
      pm_stuntedOrgansCount INTEGER,
      pm_stuntedOrgansSeverity TEXT,
      pm_pulmonaryHemorrhageCount INTEGER,
      pm_pulmonaryHemorrhageSeverity TEXT,
      pm_gaspingPresent INTEGER,
      pm_gaspingType TEXT,
      pm_exposedBrainCount INTEGER,
      pm_ectopicVisceraCount INTEGER,
      pm_extraLegsCount INTEGER,
      pm_crossedBeakCount INTEGER,
      pm_absentEyeBothCount INTEGER,
      pm_absentEyeOneCount INTEGER,
      pm_smallEyeCount INTEGER,
      pm_hydrocephalyCount INTEGER,
      pm_starGazerCount INTEGER,
      pm_curledToesCount INTEGER,
      pm_shortLegsCount INTEGER,
      pm_spinalDeformityCount INTEGER,
      pm_cardiacAnomalyCount INTEGER,
      pm_conjoinedCount INTEGER,
      pm_otherDeformityCount INTEGER,
      pm_otherDeformityText TEXT,
      pm_suspectedCauseAuto TEXT,
      pm_suspectedCauseManual TEXT,
      pm_photosJson TEXT,
      so_machineType TEXT,
      so_turningAngle REAL,
      FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
      FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
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
      auditId TEXT,
      uploadStatus TEXT NOT NULL DEFAULT 'local',
      FOREIGN KEY (auditId) REFERENCES audits(id) ON DELETE CASCADE
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
    await _createStationSamplesTable(db);
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
    // Add UNIQUE constraint on audits
    await db.execute(
      'CREATE UNIQUE INDEX idx_audits_unique ON audits (customerId, flockId, date, auditType, hatchNumber, setterId, hatcherId)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE audits ADD COLUMN hatchNumber INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute('DROP INDEX IF EXISTS idx_audits_unique');
      await db.execute(
        'CREATE UNIQUE INDEX idx_audits_unique ON audits (customerId, flockId, date, auditType, hatchNumber, setterId, hatcherId)',
      );
    }
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS bmk_breeds');
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
      await db.execute('DROP TABLE IF EXISTS bmk_egg_breakout');
      await _createCleanBmkEggBreakoutTable(db);
      for (final seed in kBmkBreedSeeds) {
        await db.insert('bmk_breeds', seed);
      }
      for (final seed in kBmkEggBreakoutSeeds) {
        await db.insert('bmk_egg_breakout', _cleanBmkEggBreakoutSeed(seed));
      }
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'feathersPct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'turnedPct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'exposedBrainPct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'crossedBeakPct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'crackedPct',
        'REAL DEFAULT 0.0',
      );
    }
    if (oldVersion < 5) {
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'earlyDeadPct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'midBlackEyePct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'internalPipPct',
        'REAL DEFAULT 0.0',
      );
      await _addColumnIfMissing(
        db,
        'bmk_egg_breakout',
        'externalPipPct',
        'REAL DEFAULT 0.0',
      );
      await _ensureCompleteBmkBreedSeedData(db);
      await _backfillEggBreakoutAliases(db);
    }
    if (oldVersion < 6) {
      await _addColumnIfMissing(db, 'audits', 'ebInfertileCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebEarlyDeadCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebMidDeadCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebLateDeadCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebInternalPipCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebExternalPipCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebCrackedCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebContaminatedCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebMalpositionCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebExposedBrainCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebCrossedBeakCount', 'INTEGER');
      await _addColumnIfMissing(db, 'audits', 'ebCulledDeadCount', 'INTEGER');
    }
    if (oldVersion < 7) {
      await _ensureUserAuthColumns(db);
    }
    if (oldVersion < 8) {
      await _ensureDummyTestData(db);
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(
        db,
        'flocks',
        'isAgeEstimated',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 10) {
      await _createHatcheryTables(db);
    }
    if (oldVersion < 11) {
      await _addColumnIfMissing(
        db,
        'flocks',
        'status',
        "TEXT NOT NULL DEFAULT 'active'",
      );
      await _addColumnIfMissing(
        db,
        'flocks',
        'depletionAgeWeeks',
        'INTEGER NOT NULL DEFAULT 65',
      );
      await _addColumnIfMissing(db, 'flocks', 'soldAt', 'TEXT');
    }
    if (oldVersion < 12) {
      await _addColumnIfMissing(
        db,
        'photos',
        'uploadStatus',
        "TEXT NOT NULL DEFAULT 'local'",
      );
      await db.execute("UPDATE photos SET uploadStatus = 'synced'");
      await _seedTroubleshooting(db);
    }
    if (oldVersion < 13) {
      await _createOperationalIndexes(db);
    }
    if (oldVersion < 14) {
      await db.execute('''CREATE TABLE IF NOT EXISTS activity_log (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        action TEXT NOT NULL,
        entityType TEXT,
        entityId TEXT,
        details TEXT,
        timestamp TEXT NOT NULL
      )''');
      await _createActivityLogIndexes(db);
    }
    if (oldVersion < 15) {
      await _applyV15Upgrade(db);
    }
    if (oldVersion < 16) {
      await _applyV16Upgrade(db);
    }
    if (oldVersion < 17) {
      await _applyV17Upgrade(db);
    }
    if (oldVersion < 18) {
      await _applyV18Upgrade(db);
    }
    if (oldVersion < 19) {
      await _applyV19Upgrade(db);
    }
    if (oldVersion < 20) {
      await _applyV20Upgrade(db);
    }
    if (oldVersion < 21) {
      await _applyV21Upgrade(db);
    }
    if (oldVersion < 22) {
      await _applyV22Upgrade(db);
    }
    if (oldVersion < 23) {
      await _applyV23Upgrade(db);
    }
    if (oldVersion < 24) {
      await _applyV24Upgrade(db);
    }
    if (oldVersion < 25) {
      await _applyV25Upgrade(db);
    }
    if (oldVersion < 26) {
      await _applyV26Upgrade(db);
    }
    if (oldVersion < 27) {
      await _applyV27Upgrade(db);
    }
    if (oldVersion < 28) {
      await _applyV28Upgrade(db);
    }
    if (oldVersion < 29) {
      await _applyV29Upgrade(db);
    }
    if (oldVersion < 30) {
      await _applyV30Upgrade(db);
    }
    if (oldVersion < 31) {
      await _applyV31Upgrade(db);
    }
    if (oldVersion < 32) {
      await _applyV32Upgrade(db);
    }
    if (oldVersion < 33) {
      await _applyV33Upgrade(db);
    }
    if (oldVersion < 34) {
      await _applyV34Upgrade(db);
    }
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
