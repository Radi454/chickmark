import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'seeds/bmk_seeds.dart';
import 'seeds/dummy_data_seeds.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'hatchaudit.db'),
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
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
      entryDate TEXT
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
      -- Hatch Analysis: Egg Breakout
      ebTraySize INTEGER,
      ebBreakoutType TEXT,
      ebBreakoutAgeDays INTEGER,
      ebStorageDays INTEGER,
      ebTrays TEXT,
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
      esEggBmkWeight REAL
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
      farmFlockCauses TEXT
    )''');
    await db.execute('''CREATE TABLE photos (
      id TEXT PRIMARY KEY,
      filePath TEXT,
      description TEXT,
      createdAt TEXT,
      auditId TEXT
    )''');
    // Seed data
    for (final seed in kBmkBreedSeeds) {
      await db.insert('bmk_breeds', seed);
    }
    await _ensureCompleteBmkBreedSeedData(db);
    for (final seed in kBmkEggBreakoutSeeds) {
      await db.insert('bmk_egg_breakout', seed);
    }
    await _backfillEggBreakoutAliases(db);
    for (final seed in kTroubleshootingSeeds) {
      await db.insert('troubleshooting', seed);
    }
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
  }

  Future<void> _ensureDummyTestData(Database db) async {
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
}
