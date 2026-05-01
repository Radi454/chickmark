import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'seeds/bmk_seeds.dart' hide kTroubleshootingSeeds;
import 'seeds/dummy_data_seeds.dart';
import 'seeds/troubleshooting_seeds.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const String _stationSamplesRebuildTable =
      'station_samples__v20_rebuild';

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      await _databasePath(),
      version: 20,
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
      soldAt TEXT
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
      -- Chick Quality: CHA Environmental
      chaGoveeConnected INTEGER,
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
      -- Chick Quality: Pasgar
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
      -- Chick Quality: Weights
      chickStorageDays INTEGER,
      chickSampleSize INTEGER,
      chickWeights TEXT,
      chickAvgWeight REAL,
      chickUniformityPct REAL,
      chickCvPct REAL,
      chickBmkAge INTEGER,
      chickBmkWeight REAL,
      -- Chick Quality: YFBM
      yfbmPhoto TEXT,
      yfbmEntries TEXT,
      yfbmAvgPct REAL,
      yfbmCvPct REAL,
      -- Chick Quality: CVT
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
      -- Hatch Analysis: Hatch Results
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
      -- Hatch Analysis: Egg Breakout
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
      -- Setter Optimizing
      soBreed TEXT,
      soSetterId TEXT,
      soIncubationAge INTEGER,
      soGoveeConnected INTEGER,
      soGoveeTemp REAL,
      soGoveeHumidity REAL,
      soCo2 REAL,
      soCo2Photo TEXT,
      soEstReadings TEXT,
      soEstPhotos TEXT,
      soEstAvg REAL,
      soEstCv REAL,
      -- Hatcher Optimizing
      hoBreed TEXT,
      hoHatcherId TEXT,
      hoIncubationAge INTEGER,
      hoGoveeConnected INTEGER,
      hoGoveeTemp REAL,
      hoGoveeHumidity REAL,
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
      -- Egg Storage
      esGoveeConnected INTEGER,
      esGoveeTemp REAL,
      esGoveeHumidity REAL,
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
      so_turningAngle REAL
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
    await db.execute('''CREATE TABLE bmk_egg_breakout (
      id TEXT PRIMARY KEY,
      ageWeek INTEGER NOT NULL UNIQUE,
      infertilePct REAL DEFAULT 0.0,
      early24hPct REAL DEFAULT 0.0,
      early48hPct REAL DEFAULT 0.0,
      bloodRingPct REAL DEFAULT 0.0,
      blackEyePct REAL DEFAULT 0.0,
      midDeadPct REAL DEFAULT 0.0,
      lateDeadPct REAL DEFAULT 0.0,
      pippedInternalPct REAL DEFAULT 0.0,
      pippedExternalPct REAL DEFAULT 0.0,
      explodedPct REAL DEFAULT 0.0,
      mushyPct REAL DEFAULT 0.0,
      contamPct REAL DEFAULT 0.0,
      cullPct REAL DEFAULT 0.0,
      seeperPct REAL DEFAULT 0.0,
      otherPct REAL DEFAULT 0.0,
      feathersPct REAL DEFAULT 0.0,
      turnedPct REAL DEFAULT 0.0,
      exposedBrainPct REAL DEFAULT 0.0,
      crossedBeakPct REAL DEFAULT 0.0,
      crackedPct REAL DEFAULT 0.0,
      earlyDeadPct REAL DEFAULT 0.0,
      midBlackEyePct REAL DEFAULT 0.0,
      internalPipPct REAL DEFAULT 0.0,
      externalPipPct REAL DEFAULT 0.0
    )''');
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
      uploadStatus TEXT NOT NULL DEFAULT 'local'
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
    await _createTemperatureRhTables(db);
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
      await db.execute('''CREATE TABLE bmk_egg_breakout (
        id TEXT PRIMARY KEY,
        ageWeek INTEGER NOT NULL UNIQUE,
        infertilePct REAL DEFAULT 0.0,
        early24hPct REAL DEFAULT 0.0,
        early48hPct REAL DEFAULT 0.0,
        bloodRingPct REAL DEFAULT 0.0,
        blackEyePct REAL DEFAULT 0.0,
        midDeadPct REAL DEFAULT 0.0,
        lateDeadPct REAL DEFAULT 0.0,
        pippedInternalPct REAL DEFAULT 0.0,
        pippedExternalPct REAL DEFAULT 0.0,
        explodedPct REAL DEFAULT 0.0,
        mushyPct REAL DEFAULT 0.0,
        contamPct REAL DEFAULT 0.0,
        cullPct REAL DEFAULT 0.0,
        seeperPct REAL DEFAULT 0.0,
        otherPct REAL DEFAULT 0.0
      )''');
      for (final seed in kBmkBreedSeeds) {
        await db.insert('bmk_breeds', seed);
      }
      for (final seed in kBmkEggBreakoutSeeds) {
        await db.insert('bmk_egg_breakout', seed);
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
      await _createTemperatureRhTables(db);
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
  }

  Future<void> _createHatcheryTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS hatcheries (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      name TEXT NOT NULL,
      location TEXT,
      notes TEXT,
      createdAt TEXT,
      createdBy TEXT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hatcheries_customer ON hatcheries (customerId)',
    );
  }

  Future<void> _createAuditSessionTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS audit_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      flockId TEXT NOT NULL,
      hatcheryId TEXT NOT NULL,
      date TEXT NOT NULL,
      breed TEXT,
      flockAgeWeeks INTEGER,
      status TEXT DEFAULT 'in_progress',
      selectedStationKeys TEXT,
      stationsCompleted TEXT,
      findingsJson TEXT,
      scorecardJson TEXT,
      notes TEXT,
      createdBy TEXT,
      createdAt TEXT,
      updatedAt TEXT,
      completedAt TEXT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_sessions_customer_date ON audit_sessions (customerId, date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_sessions_flock_date ON audit_sessions (flockId, date DESC)',
    );
  }

  Future<void> _createStationSamplesTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS station_samples (
      id TEXT PRIMARY KEY,
      auditSessionId TEXT NOT NULL,
      legacyAuditId TEXT,
      stationType TEXT NOT NULL,
      sampleMode TEXT NOT NULL DEFAULT 'pooled',
      comparisonType TEXT,
      sampleIndex INTEGER NOT NULL DEFAULT 1,
      sampleLabel TEXT,
      sampleType TEXT,
      breakoutType TEXT,
      groupKey TEXT,
      groupLabel TEXT,
      batchNo TEXT,
      houseNo TEXT,
      houseLabel TEXT,
      hatchNo TEXT,
      eggProductionDate TEXT,
      settingDate TEXT,
      hatchDate TEXT,
      storageDays INTEGER,
      incubationDay INTEGER,
      setterNo TEXT,
      hatcherNo TEXT,
      calculatedBmkAgeDays INTEGER,
      benchmarkBreed TEXT,
      benchmarkAgeDays INTEGER,
      benchmarkSource TEXT,
      benchmarkSnapshotJson TEXT,
      resultSummaryJson TEXT,
      notes TEXT,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      FOREIGN KEY (auditSessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
      FOREIGN KEY (legacyAuditId) REFERENCES audits(id) ON DELETE CASCADE
    )''');
    await _createStationSamplesIndexes(db);
  }

  Future<void> _createStationSamplesIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_station_samples_session_station ON station_samples (auditSessionId, stationType)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_station_samples_group ON station_samples (auditSessionId, groupKey)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_station_samples_legacy_audit ON station_samples (legacyAuditId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_station_samples_bmk_age ON station_samples (calculatedBmkAgeDays)',
    );
  }

  Future<void> _createTemperatureRhTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS temperature_sessions (
      id TEXT PRIMARY KEY,
      customerId TEXT NOT NULL,
      hatcheryId TEXT NOT NULL,
      deviceId TEXT,
      deviceName TEXT,
      startedAt TEXT NOT NULL,
      endedAt TEXT,
      activePlace TEXT NOT NULL,
      status TEXT NOT NULL,
      tempAvg REAL,
      tempMin REAL,
      tempMax REAL,
      tempCvPct REAL,
      rhAvg REAL,
      rhMin REAL,
      rhMax REAL,
      rhCvPct REAL,
      readingCount INTEGER,
      alertCount INTEGER,
      tempChartPointsJson TEXT,
      rhChartPointsJson TEXT,
      warmupSeconds INTEGER DEFAULT 120,
      auditSessionId TEXT,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS temperature_readings (
      id TEXT PRIMARY KEY,
      sessionId TEXT NOT NULL,
      customerId TEXT NOT NULL,
      hatcheryId TEXT NOT NULL,
      place TEXT NOT NULL,
      temperatureFahrenheit REAL NOT NULL,
      humidity REAL NOT NULL,
      rssi INTEGER,
      deviceName TEXT,
      recordedAt TEXT NOT NULL,
      createdAt TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_temperature_sessions_hatchery ON temperature_sessions (hatcheryId, startedAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_temperature_sessions_audit_session ON temperature_sessions (auditSessionId, startedAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_temperature_readings_session_time ON temperature_readings (sessionId, recordedAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_temperature_readings_hatchery_time ON temperature_readings (hatcheryId, recordedAt)',
    );
  }

  Future<void> _createOperationalIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_customer ON audits (customerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_flock ON audits (flockId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_date ON audits (date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_type ON audits (auditType)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_customer_type ON audits (customerId, auditType)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_customer_date ON audits (customerId, date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_session ON audits (sessionId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_audit ON photos (auditId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_flocks_customer ON flocks (customerId, status)',
    );
  }

  Future<void> _createActivityLogIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_log_user ON activity_log (userId, timestamp DESC)',
    );
  }

  Future<void> _applyV15Upgrade(Database db) async {
    await _createAuditSessionTables(db);

    await _addColumnIfMissing(db, 'audits', 'sessionId', 'TEXT');

    await _addColumnIfMissing(db, 'audits', 'pm_sampleSize', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_collectionPoint', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_omphalitisCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_omphalitisSeverity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_gaseousCecaCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_gaseousCecaSeverity', 'TEXT');
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_unabsorbedYolkCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_unabsorbedYolkSeverity',
      'TEXT',
    );
    await _addColumnIfMissing(db, 'audits', 'pm_perihepatitisCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_perihepatitisSeverity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_pericarditisCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_pericarditisSeverity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_airsacAcuteCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_airsacAcuteSeverity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_airsacChronicCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_airsacChronicSeverity', 'TEXT');
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_pulmonaryGranulomaCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_pulmonaryGranulomaSeverity',
      'TEXT',
    );
    await _addColumnIfMissing(db, 'audits', 'pm_swollenJointsCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_swollenJointsSeverity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_stuntedOrgansCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_stuntedOrgansSeverity', 'TEXT');
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_pulmonaryHemorrhageCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_pulmonaryHemorrhageSeverity',
      'TEXT',
    );
    await _addColumnIfMissing(db, 'audits', 'pm_gaspingPresent', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_gaspingType', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_exposedBrainCount', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_ectopicVisceraCount',
      'INTEGER',
    );
    await _addColumnIfMissing(db, 'audits', 'pm_extraLegsCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_crossedBeakCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_absentEyeBothCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_absentEyeOneCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_smallEyeCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_hydrocephalyCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_starGazerCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_curledToesCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'pm_shortLegsCount', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_spinalDeformityCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_cardiacAnomalyCount',
      'INTEGER',
    );
    await _addColumnIfMissing(db, 'audits', 'pm_conjoinedCount', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'audits',
      'pm_otherDeformityCount',
      'INTEGER',
    );
    await _addColumnIfMissing(db, 'audits', 'pm_otherDeformityText', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_suspectedCauseAuto', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_suspectedCauseManual', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'pm_photosJson', 'TEXT');

    await _addColumnIfMissing(db, 'audits', 'es_estReadingsJson', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_estAvg', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_estCv', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_uvSampleSize', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'audits',
      'es_uvCuticleDamageCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'audits',
      'es_uvWashingEvidenceCount',
      'INTEGER',
    );
    await _addColumnIfMissing(db, 'audits', 'es_uvFecalCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'es_uvMottledCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'es_uvOtherCount', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'es_uvPhotosJson', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_crackPct', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_brokenPct', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_misshapedPct', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_paleShellPct', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_roughTexturePct', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_floorEggPct', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'es_eggColorDistJson', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_eggOrientation', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_traySpacing', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_coolerProximity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_wallProximity', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'es_condensation', 'INTEGER');

    await _addColumnIfMissing(db, 'audits', 'so_machineType', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'so_turningAngle', 'REAL');
    await _addColumnIfMissing(db, 'audits', 'ho_meconium', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'ho_transferDay', 'INTEGER');

    await _addColumnIfMissing(db, 'audits', 'haPipped', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'haInfertileClear', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'haEarlyDead', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'haMidDead', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'haMidLateDead', 'INTEGER');
    await _addColumnIfMissing(db, 'audits', 'haLateDead', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'audits',
      'haContaminatedExploders',
      'INTEGER',
    );
    await _addColumnIfMissing(db, 'audits', 'haBenchmarkStatusesJson', 'TEXT');

    await _addColumnIfMissing(db, 'temperature_sessions', 'tempAvg', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'tempMin', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'tempMax', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'tempCvPct', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'rhAvg', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'rhMin', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'rhMax', 'REAL');
    await _addColumnIfMissing(db, 'temperature_sessions', 'rhCvPct', 'REAL');
    await _addColumnIfMissing(
      db,
      'temperature_sessions',
      'readingCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'temperature_sessions',
      'alertCount',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'temperature_sessions',
      'tempChartPointsJson',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'temperature_sessions',
      'rhChartPointsJson',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      'temperature_sessions',
      'warmupSeconds',
      'INTEGER DEFAULT 120',
    );
    await _addColumnIfMissing(
      db,
      'temperature_sessions',
      'auditSessionId',
      'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_temperature_sessions_audit_session ON temperature_sessions (auditSessionId, startedAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audits_session ON audits (sessionId)',
    );
  }

  Future<void> _applyV16Upgrade(Database db) async {
    await _addColumnIfMissing(
      db,
      'audit_sessions',
      'selectedStationKeys',
      'TEXT',
    );
  }

  Future<void> _applyV17Upgrade(Database db) async {
    await _addColumnIfMissing(db, 'audits', 'es_estPhotosJson', 'TEXT');
  }

  Future<void> _applyV18Upgrade(Database db) async {
    await _addColumnIfMissing(
      db,
      'audits',
      'sampleMode',
      "TEXT NOT NULL DEFAULT 'pool'",
    );
    await _addColumnIfMissing(db, 'audits', 'compareGroupKey', 'TEXT');
    await _addColumnIfMissing(db, 'audits', 'ebTrayBreakoutJson', 'TEXT');
    await _addColumnIfMissing(db, 'troubleshooting', 'benchmarkJson', 'TEXT');
    await _addColumnIfMissing(
      db,
      'troubleshooting',
      'interpretationJson',
      'TEXT',
    );
    await _addColumnIfMissing(db, 'troubleshooting', 'sourceRefsJson', 'TEXT');
    await db.execute("""
      UPDATE audits
      SET sampleMode = 'pool'
      WHERE sampleMode IS NULL OR sampleMode NOT IN ('pool', 'compare')
    """);
    await db.execute("""
      UPDATE audits
      SET sampleMode = 'compare',
          compareGroupKey = COALESCE(
            compareGroupKey,
            customerId || '|' || COALESCE(flockId, '') || '|' || date || '|' || auditType
          )
      WHERE hatchNumber > 1
         OR id IN (
           SELECT a1.id
           FROM audits a1
           WHERE EXISTS (
             SELECT 1
             FROM audits a2
             WHERE a2.customerId = a1.customerId
               AND COALESCE(a2.flockId, '') = COALESCE(a1.flockId, '')
               AND a2.date = a1.date
               AND a2.auditType = a1.auditType
               AND a2.hatchNumber > 1
           )
         )
    """);
    await _seedTroubleshooting(db);
  }

  @visibleForTesting
  Future<void> applyV18UpgradeForTest(Database db) => _applyV18Upgrade(db);

  Future<void> _applyV19Upgrade(Database db) async {
    await _createStationSamplesTable(db);
  }

  @visibleForTesting
  Future<void> applyV19UpgradeForTest(Database db) => _applyV19Upgrade(db);

  Future<void> _applyV20Upgrade(Database db) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info(station_samples)');
    if (tableInfo.isEmpty) {
      await _createStationSamplesTable(db);
      return;
    }

    final foreignKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(station_samples)',
    );
    if (_hasStationSamplesForeignKeys(foreignKeys)) {
      await _addStationSampleHouseColumns(db, _columnNames(tableInfo));
      await _createStationSamplesIndexes(db);
      return;
    }

    final columnNames = _columnNames(tableInfo);
    if (!columnNames.contains('auditSessionId') ||
        !columnNames.contains('legacyAuditId')) {
      throw StateError(
        'station_samples must contain auditSessionId and legacyAuditId '
        'before the v20 corrective rebuild can add foreign keys.',
      );
    }

    await db.transaction<void>((txn) async {
      await _rebuildStationSamplesTableForV20(txn, tableInfo);
    });
  }

  @visibleForTesting
  Future<void> applyV20UpgradeForTest(Database db) => _applyV20Upgrade(db);

  Future<void> _addStationSampleHouseColumns(
    DatabaseExecutor db,
    Set<String> columnNames,
  ) async {
    if (!columnNames.contains('houseNo')) {
      await db.execute('ALTER TABLE station_samples ADD COLUMN houseNo TEXT');
    }
    if (!columnNames.contains('houseLabel')) {
      await db.execute(
        'ALTER TABLE station_samples ADD COLUMN houseLabel TEXT',
      );
    }
  }

  Future<void> _rebuildStationSamplesTableForV20(
    DatabaseExecutor db,
    List<Map<String, Object?>> existingColumns,
  ) async {
    final existingNames = _columnNames(existingColumns);
    final columnDefinitions = <String>[];
    final insertColumns = <String>[];
    final selectExpressions = <String>[];

    for (final column in existingColumns) {
      final name = column['name']?.toString();
      if (name == null || name.isEmpty) continue;
      final quotedName = _quoteSqlIdentifier(name);
      columnDefinitions.add(_columnDefinitionForRebuild(column));
      insertColumns.add(quotedName);
      selectExpressions.add(quotedName);
    }

    for (final name in const ['houseNo', 'houseLabel']) {
      if (existingNames.contains(name)) continue;
      columnDefinitions.add('$name TEXT');
      insertColumns.add(_quoteSqlIdentifier(name));
      selectExpressions.add('NULL');
    }

    final createSql =
        '''
CREATE TABLE "$_stationSamplesRebuildTable" (
  ${columnDefinitions.join(',\n  ')},
  FOREIGN KEY ("auditSessionId") REFERENCES audit_sessions(id) ON DELETE CASCADE,
  FOREIGN KEY ("legacyAuditId") REFERENCES audits(id) ON DELETE CASCADE
)''';

    await db.execute('DROP TABLE IF EXISTS "$_stationSamplesRebuildTable"');
    await db.execute(createSql);
    await db.execute(
      'INSERT INTO "$_stationSamplesRebuildTable" '
      '(${insertColumns.join(', ')}) '
      'SELECT ${selectExpressions.join(', ')} FROM station_samples',
    );
    await db.execute('DROP TABLE station_samples');
    await db.execute(
      'ALTER TABLE "$_stationSamplesRebuildTable" RENAME TO station_samples',
    );
    await _createStationSamplesIndexes(db);
  }

  bool _hasStationSamplesForeignKeys(List<Map<String, Object?>> foreignKeys) {
    final hasAuditSessionFk = foreignKeys.any(
      (row) =>
          row['from'] == 'auditSessionId' &&
          row['table'] == 'audit_sessions' &&
          row['to'] == 'id',
    );
    final hasAuditFk = foreignKeys.any(
      (row) =>
          row['from'] == 'legacyAuditId' &&
          row['table'] == 'audits' &&
          row['to'] == 'id',
    );
    return hasAuditSessionFk && hasAuditFk;
  }

  Set<String> _columnNames(List<Map<String, Object?>> tableInfo) {
    return {
      for (final row in tableInfo)
        if (row['name'] != null) row['name'].toString(),
    };
  }

  String _columnDefinitionForRebuild(Map<String, Object?> column) {
    final name = column['name']?.toString() ?? '';
    final type = column['type']?.toString().trim() ?? '';
    final defaultValue = column['dflt_value'];
    final isNotNull = _pragmaInt(column['notnull']) == 1;
    final isPrimaryKey = _pragmaInt(column['pk']) > 0;
    final parts = <String>[_quoteSqlIdentifier(name)];
    if (type.isNotEmpty) parts.add(type);
    if (isPrimaryKey) parts.add('PRIMARY KEY');
    if (isNotNull) parts.add('NOT NULL');
    if (defaultValue != null) parts.add('DEFAULT $defaultValue');
    return parts.join(' ');
  }

  int _pragmaInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _quoteSqlIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<void> _ensureDummyTestData(Database db) async {
    if (kReleaseMode) return;
    for (final seed in kDummyCustomerSeeds) {
      await db.insert(
        'customers',
        seed,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final seed in kDummyFlockSeeds) {
      await db.insert(
        'flocks',
        seed,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final seed in kDummyAuditSeeds) {
      await db.insert(
        'audits',
        seed,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _seedTroubleshooting(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(troubleshooting)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();

    for (final entry in kTroubleshootingSeeds.entries) {
      final row = <String, Object?>{
        'id': entry.key,
        'hatcheryCauses': jsonEncode(entry.value['hatcheryCauses']),
        'farmFlockCauses': jsonEncode(entry.value['farmFlockCauses']),
      };

      if (columnNames.contains('benchmarkJson')) {
        row['benchmarkJson'] = entry.value['benchmark'] == null
            ? null
            : jsonEncode(entry.value['benchmark']);
      }
      if (columnNames.contains('interpretationJson')) {
        row['interpretationJson'] = entry.value['interpretation'] == null
            ? null
            : jsonEncode(entry.value['interpretation']);
      }
      if (columnNames.contains('sourceRefsJson')) {
        row['sourceRefsJson'] = entry.value['sourceRefs'] == null
            ? null
            : jsonEncode(entry.value['sourceRefs']);
      }

      await db.insert(
        'troubleshooting',
        row,
        conflictAlgorithm: entry.value.containsKey('sourceRefs')
            ? ConflictAlgorithm.replace
            : ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _ensureUserAuthColumns(Database db) async {
    final existingTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users'",
    );
    if (existingTables.isEmpty) {
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
      return;
    }

    await _addColumnIfMissing(db, 'users', 'fullName', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'email', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'role', "TEXT DEFAULT 'auditor'");
    await _addColumnIfMissing(db, 'users', 'status', "TEXT DEFAULT 'pending'");
    await _addColumnIfMissing(db, 'users', 'customerId', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'accessToken', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'tokenExpiry', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'createdAt', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'lastLoginAt', 'TEXT');
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _backfillEggBreakoutAliases(Database db) async {
    await db.execute('''
      UPDATE bmk_egg_breakout
      SET
        earlyDeadPct = CASE WHEN earlyDeadPct = 0 THEN midDeadPct ELSE earlyDeadPct END,
        midBlackEyePct = CASE WHEN midBlackEyePct = 0 THEN blackEyePct ELSE midBlackEyePct END,
        internalPipPct = CASE WHEN internalPipPct = 0 THEN pippedInternalPct ELSE internalPipPct END,
        externalPipPct = CASE WHEN externalPipPct = 0 THEN pippedExternalPct ELSE externalPipPct END
    ''');
  }

  Future<void> _ensureCompleteBmkBreedSeedData(Database db) async {
    const breeds = ['Ross308', 'Arbo', 'Avian', 'Cobb500', 'Hubbard', 'IR'];
    for (final breed in breeds) {
      final startAge = breed == 'Cobb500' ? 24 : 25;
      for (var age = startAge; age <= 65; age++) {
        final existing = await db.query(
          'bmk_breeds',
          where: 'breed = ? AND ageWeek = ?',
          whereArgs: [breed, age],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;

        final template = await _nearestBmkBreedRow(db, breed, age);
        if (template == null) continue;
        await db.insert('bmk_breeds', {
          'id': '${breed.toLowerCase()}-$age',
          'breed': breed,
          'ageWeek': age,
          'hatchabilityPct': template['hatchabilityPct'],
          'fertilityPct': template['fertilityPct'],
          'hofPct': template['hofPct'],
          'productionPct': template['productionPct'],
          'eggWeightG': template['eggWeightG'],
          'chickWeightG': template['chickWeightG'],
        });
      }
    }
  }

  Future<Map<String, Object?>?> _nearestBmkBreedRow(
    Database db,
    String breed,
    int age,
  ) async {
    final rows = await db.query(
      'bmk_breeds',
      where: 'breed = ?',
      whereArgs: [breed],
      orderBy: 'ABS(ageWeek - $age) ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

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
