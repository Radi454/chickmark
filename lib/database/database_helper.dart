import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/customer.dart';
import '../models/flock.dart';
import '../models/audit_session.dart';
import '../models/chick_quality.dart';
import '../models/egg_breakout.dart';
import '../models/setter_measurements.dart';
import '../models/hatcher_measurements.dart';
import '../models/vaccine_storage.dart';
import '../models/egg_storage.dart';
import '../models/hatchery_results.dart';
import '../models/benchmark.dart';

class DatabaseHelper {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  // ── Initialisation ────────────────────────────────────────────────────────
  Future<Database> _initDatabase() async {
    String path;
    if (kIsWeb) {
      path = 'hatchaudit.db';
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'hatchaudit.db');
    }
    return openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Drop and recreate tables that changed schema
      await db.execute('DROP TABLE IF EXISTS hatchery_results');
      await db.execute('DROP TABLE IF EXISTS egg_breakout');
      await db.execute('DROP TABLE IF EXISTS chick_quality');
      await db.execute('DROP TABLE IF EXISTS benchmarks');
      // Create updated tables
      await _createHatcheryResultsTable(db);
      await _createEggBreakoutTable(db);
      await _createChickQualityTable(db);
      await _createBenchmarksTable(db);
      // Create new tables
      await _createEggBreakoutInterpretationsTable(db);
    }
    if (oldVersion < 3) {
      // Add multi-hatch JSON column to egg_breakout
      await db.execute(
          'ALTER TABLE egg_breakout ADD COLUMN hatches_json TEXT');
      // Add per-hatch YFBM and PASGAR JSON columns to chick_quality
      await db.execute(
          'ALTER TABLE chick_quality ADD COLUMN yfbm_hatch_data TEXT');
      await db.execute(
          'ALTER TABLE chick_quality ADD COLUMN pasgar_hatch_data TEXT');
    }
    if (oldVersion < 4) {
      // Seed Infertile, EarlyDead, LateDead benchmarks for existing databases
      await _seedBreakoutBenchmarks(db);
    }
    if (oldVersion < 5) {
      // Add per-hatch weights JSON column to chick_quality
      await db.execute(
          'ALTER TABLE chick_quality ADD COLUMN weights_hatch_json TEXT');
    }
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        address TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE flocks (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        flock_code TEXT NOT NULL,
        breed TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_sessions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        breed TEXT NOT NULL,
        flock_age_weeks REAL NOT NULL,
        egg_production_age_weeks REAL NOT NULL,
        audit_date TEXT NOT NULL,
        benchmark_set TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_sections TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL
      )
    ''');

    await _createChickQualityTable(db);
    await _createEggBreakoutTable(db);

    await db.execute('''
      CREATE TABLE setter_measurements (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        setter_id TEXT,
        incubation_age INTEGER,
        temperature REAL,
        humidity REAL,
        top_front REAL,
        top_middle REAL,
        top_back REAL,
        mid_front REAL,
        mid_middle REAL,
        mid_back REAL,
        bot_front REAL,
        bot_middle REAL,
        bot_back REAL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE hatcher_measurements (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        hatcher_id TEXT,
        temperature REAL,
        humidity REAL,
        top_front REAL,
        top_middle REAL,
        top_back REAL,
        mid_front REAL,
        mid_middle REAL,
        mid_back REAL,
        bot_front REAL,
        bot_middle REAL,
        bot_back REAL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE vaccine_storage (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        room_temperature REAL,
        room_humidity REAL,
        fridge_vaccines TEXT NOT NULL DEFAULT '[]',
        hvt_containers TEXT NOT NULL DEFAULT '[]',
        cold_chain_maintained INTEGER NOT NULL DEFAULT 0,
        expiry_dates_checked INTEGER NOT NULL DEFAULT 0,
        dilution_protocol_followed INTEGER NOT NULL DEFAULT 0,
        vaccination_room_biosecure INTEGER NOT NULL DEFAULT 0,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE egg_storage (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        temperature REAL,
        humidity REAL,
        eggshell_temperature REAL,
        turning_frequency TEXT,
        uv_trays TEXT,
        storage_days INTEGER,
        sanitization_method TEXT,
        sanitization_agent TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await _createHatcheryResultsTable(db);
    await _createBenchmarksTable(db);
    await _createEggBreakoutInterpretationsTable(db);
  }

  Future<void> _createChickQualityTable(Database db) async {
    await db.execute('''
      CREATE TABLE chick_quality (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        egg_storage_days INTEGER,
        temperature REAL,
        humidity REAL,
        co2_level REAL,
        pm10 REAL,
        pm25 REAL,
        air_velocity_door REAL,
        air_velocity_center REAL,
        air_velocity_corner REAL,
        noise_level REAL,
        sample_size INTEGER NOT NULL DEFAULT 100,
        weights TEXT NOT NULL DEFAULT '[]',
        yfbm_data TEXT NOT NULL DEFAULT '[]',
        yfbm_hatch_data TEXT,
        pasgar_sample_size INTEGER NOT NULL DEFAULT 0,
        reflexes_defects INTEGER NOT NULL DEFAULT 0,
        beak_defects INTEGER NOT NULL DEFAULT 0,
        navel_defects INTEGER NOT NULL DEFAULT 0,
        belly_defects INTEGER NOT NULL DEFAULT 0,
        legs_defects INTEGER NOT NULL DEFAULT 0,
        feathered_count INTEGER,
        wing_sample_size INTEGER,
        pasgar_hatch_data TEXT,
        weights_hatch_json TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createEggBreakoutTable(Database db) async {
    await db.execute('''
      CREATE TABLE egg_breakout (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        egg_storage_days INTEGER,
        egg_breakout_age_days INTEGER,
        incubator_id TEXT,
        hatcher_id TEXT,
        sample_size INTEGER,
        tray_data TEXT NOT NULL DEFAULT '[]',
        hatches_json TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createHatcheryResultsTable(Database db) async {
    await db.execute('''
      CREATE TABLE hatchery_results (
        id TEXT PRIMARY KEY,
        audit_session_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        flock_id TEXT NOT NULL,
        egg_storage_days INTEGER,
        total_hatcher_capacity INTEGER NOT NULL DEFAULT 19200,
        hatchers_json TEXT NOT NULL DEFAULT '[]',
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createBenchmarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE benchmarks (
        id TEXT PRIMARY KEY,
        breed TEXT NOT NULL,
        age_weeks INTEGER NOT NULL,
        parameter TEXT NOT NULL,
        value REAL NOT NULL
      )
    ''');
  }

  Future<void> _createEggBreakoutInterpretationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE egg_breakout_interpretations (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        condition TEXT NOT NULL,
        hatchery_causes TEXT,
        farm_causes TEXT
      )
    ''');
    await _seedEggBreakoutInterpretations(db);
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  Future<void> insertCustomer(Customer customer) async {
    final db = await database;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Customer>> getCustomers() async {
    final db = await database;
    final maps = await db.query('customers', orderBy: 'name ASC');
    return maps.map(Customer.fromMap).toList();
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = await database;
    await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> deleteCustomer(String id) async {
    final db = await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // ── Flocks ────────────────────────────────────────────────────────────────

  Future<void> insertFlock(Flock flock) async {
    final db = await database;
    await db.insert(
      'flocks',
      flock.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Flock>> getFlocksByCustomer(String customerId) async {
    final db = await database;
    final maps = await db.query(
      'flocks',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return maps.map(Flock.fromMap).toList();
  }

  Future<List<Flock>> getAllFlocks() async {
    final db = await database;
    final maps = await db.query('flocks', orderBy: 'created_at DESC');
    return maps.map(Flock.fromMap).toList();
  }

  Future<void> updateFlock(Flock flock) async {
    final db = await database;
    await db.update(
      'flocks',
      flock.toMap(),
      where: 'id = ?',
      whereArgs: [flock.id],
    );
  }

  // ── Audit Sessions ────────────────────────────────────────────────────────

  Future<void> insertAuditSession(AuditSession session) async {
    final db = await database;
    await db.insert(
      'audit_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AuditSession>> getAuditSessions({String? customerId}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (customerId != null) {
      maps = await db.query(
        'audit_sessions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'audit_date DESC',
      );
    } else {
      maps = await db.query('audit_sessions', orderBy: 'audit_date DESC');
    }
    return maps.map(AuditSession.fromMap).toList();
  }

  Future<List<AuditSession>> getAuditSessionsByFlock(String flockId) async {
    final db = await database;
    final maps = await db.query(
      'audit_sessions',
      where: 'flock_id = ?',
      whereArgs: [flockId],
      orderBy: 'audit_date DESC',
    );
    return maps.map(AuditSession.fromMap).toList();
  }

  Future<void> updateAuditSession(AuditSession session) async {
    final db = await database;
    await db.update(
      'audit_sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<AuditSession?> getLatestAuditSession(String flockId) async {
    final db = await database;
    final maps = await db.query(
      'audit_sessions',
      where: 'flock_id = ?',
      whereArgs: [flockId],
      orderBy: 'audit_date DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AuditSession.fromMap(maps.first);
  }

  // ── Chick Quality ─────────────────────────────────────────────────────────

  Future<void> insertChickQuality(ChickQuality cq) async {
    final db = await database;
    await db.insert(
      'chick_quality',
      cq.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChickQuality?> getChickQualityBySession(String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'chick_quality',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ChickQuality.fromMap(maps.first);
  }

  Future<void> updateChickQuality(ChickQuality cq) async {
    final db = await database;
    await db.update(
      'chick_quality',
      cq.toMap(),
      where: 'id = ?',
      whereArgs: [cq.id],
    );
  }

  // ── Egg Breakout ──────────────────────────────────────────────────────────

  Future<void> insertEggBreakout(EggBreakout eb) async {
    final db = await database;
    await db.insert(
      'egg_breakout',
      eb.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<EggBreakout?> getEggBreakoutBySession(String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'egg_breakout',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return EggBreakout.fromMap(maps.first);
  }

  Future<void> updateEggBreakout(EggBreakout eb) async {
    final db = await database;
    await db.update(
      'egg_breakout',
      eb.toMap(),
      where: 'id = ?',
      whereArgs: [eb.id],
    );
  }

  // ── Setter Measurements ───────────────────────────────────────────────────

  Future<void> insertSetterMeasurements(SetterMeasurements sm) async {
    final db = await database;
    await db.insert(
      'setter_measurements',
      sm.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SetterMeasurements?> getSetterMeasurementsBySession(
      String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'setter_measurements',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SetterMeasurements.fromMap(maps.first);
  }

  Future<void> updateSetterMeasurements(SetterMeasurements sm) async {
    final db = await database;
    await db.update(
      'setter_measurements',
      sm.toMap(),
      where: 'id = ?',
      whereArgs: [sm.id],
    );
  }

  // ── Hatcher Measurements ──────────────────────────────────────────────────

  Future<void> insertHatcherMeasurements(HatcherMeasurements hm) async {
    final db = await database;
    await db.insert(
      'hatcher_measurements',
      hm.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<HatcherMeasurements?> getHatcherMeasurementsBySession(
      String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'hatcher_measurements',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return HatcherMeasurements.fromMap(maps.first);
  }

  Future<void> updateHatcherMeasurements(HatcherMeasurements hm) async {
    final db = await database;
    await db.update(
      'hatcher_measurements',
      hm.toMap(),
      where: 'id = ?',
      whereArgs: [hm.id],
    );
  }

  // ── Vaccine Storage ───────────────────────────────────────────────────────

  Future<void> insertVaccineStorage(VaccineStorage vs) async {
    final db = await database;
    await db.insert(
      'vaccine_storage',
      vs.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<VaccineStorage?> getVaccineStorageBySession(
      String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'vaccine_storage',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return VaccineStorage.fromMap(maps.first);
  }

  Future<void> updateVaccineStorage(VaccineStorage vs) async {
    final db = await database;
    await db.update(
      'vaccine_storage',
      vs.toMap(),
      where: 'id = ?',
      whereArgs: [vs.id],
    );
  }

  // ── Egg Storage ───────────────────────────────────────────────────────────

  Future<void> insertEggStorage(EggStorage es) async {
    final db = await database;
    await db.insert(
      'egg_storage',
      es.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<EggStorage?> getEggStorageBySession(String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'egg_storage',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return EggStorage.fromMap(maps.first);
  }

  Future<void> updateEggStorage(EggStorage es) async {
    final db = await database;
    await db.update(
      'egg_storage',
      es.toMap(),
      where: 'id = ?',
      whereArgs: [es.id],
    );
  }

  // ── Hatchery Results ──────────────────────────────────────────────────────

  Future<void> insertHatcheryResults(HatcheryResults hr) async {
    final db = await database;
    await db.insert(
      'hatchery_results',
      hr.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<HatcheryResults?> getHatcheryResultsBySession(
      String auditSessionId) async {
    final db = await database;
    final maps = await db.query(
      'hatchery_results',
      where: 'audit_session_id = ?',
      whereArgs: [auditSessionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return HatcheryResults.fromMap(maps.first);
  }

  Future<void> updateHatcheryResults(HatcheryResults hr) async {
    final db = await database;
    await db.update(
      'hatchery_results',
      hr.toMap(),
      where: 'id = ?',
      whereArgs: [hr.id],
    );
  }

  // ── Benchmarks ────────────────────────────────────────────────────────────

  Future<void> insertBenchmark(Benchmark benchmark) async {
    final db = await database;
    await db.insert(
      'benchmarks',
      benchmark.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double?> getBenchmark(
      String breed, double ageWeeks, String parameter) async {
    final db = await database;
    final maps = await db.query(
      'benchmarks',
      where: 'breed = ? AND parameter = ? AND age_weeks <= ?',
      whereArgs: [breed, parameter, ageWeeks.floor()],
      orderBy: 'age_weeks DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return (maps.first['value'] as num).toDouble();
    }
    final fallback = await db.query(
      'benchmarks',
      where: 'breed = ? AND parameter = ?',
      whereArgs: [breed, parameter],
      orderBy: 'age_weeks ASC',
      limit: 1,
    );
    if (fallback.isEmpty) return null;
    return (fallback.first['value'] as num).toDouble();
  }

  Future<void> updateBenchmarkValue(
      String breed, int ageWeeks, String parameter, double value) async {
    final db = await database;
    await db.update(
      'benchmarks',
      {'value': value},
      where: 'breed = ? AND age_weeks = ? AND parameter = ?',
      whereArgs: [breed, ageWeeks, parameter],
    );
  }

  Future<void> resetBenchmarks() async {
    final db = await database;
    await db.delete('benchmarks');
    await seedDefaultBenchmarks();
  }

  Future<void> insertDefaultBenchmarks() async {
    await seedDefaultBenchmarks();
  }

  /// Seeds Arbo and Ross 308 benchmark data if the table is empty.
  Future<void> seedDefaultBenchmarks() async {
    final db = await database;
    final existing = await db.query('benchmarks', limit: 1);
    if (existing.isNotEmpty) return;

    final data = <Map<String, dynamic>>[
      // ── Arbo — Hatchability ───────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'Hatchability', 'value': 0.0},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'Hatchability', 'value': 78.0},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'Hatchability', 'value': 81.3},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'Hatchability', 'value': 83.9},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'Hatchability', 'value': 85.9},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'Hatchability', 'value': 87.5},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'Hatchability', 'value': 88.7},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'Hatchability', 'value': 89.5},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'Hatchability', 'value': 90.1},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'Hatchability', 'value': 90.5},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'Hatchability', 'value': 90.7},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'Hatchability', 'value': 90.8},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'Hatchability', 'value': 90.7},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'Hatchability', 'value': 90.6},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'Hatchability', 'value': 90.3},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'Hatchability', 'value': 90.0},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'Hatchability', 'value': 89.7},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'Hatchability', 'value': 89.3},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'Hatchability', 'value': 88.8},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'Hatchability', 'value': 88.3},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'Hatchability', 'value': 87.8},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'Hatchability', 'value': 87.2},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'Hatchability', 'value': 86.7},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'Hatchability', 'value': 86.1},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'Hatchability', 'value': 85.4},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'Hatchability', 'value': 84.8},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'Hatchability', 'value': 84.1},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'Hatchability', 'value': 83.4},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'Hatchability', 'value': 82.7},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'Hatchability', 'value': 82.0},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'Hatchability', 'value': 81.3},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'Hatchability', 'value': 80.5},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'Hatchability', 'value': 79.8},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'Hatchability', 'value': 79.0},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'Hatchability', 'value': 78.2},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'Hatchability', 'value': 77.4},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'Hatchability', 'value': 76.6},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'Hatchability', 'value': 75.7},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'Hatchability', 'value': 74.9},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'Hatchability', 'value': 74.0},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'Hatchability', 'value': 73.17},
      // ── Arbo — Fertility ──────────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'Fertility', 'value': 0.0},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'Fertility', 'value': 92.8},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'Fertility', 'value': 94.0},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'Fertility', 'value': 95.0},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'Fertility', 'value': 95.5},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'Fertility', 'value': 96.0},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'Fertility', 'value': 96.4},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'Fertility', 'value': 96.6},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'Fertility', 'value': 96.7},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'Fertility', 'value': 96.7},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'Fertility', 'value': 96.7},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'Fertility', 'value': 96.7},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'Fertility', 'value': 96.6},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'Fertility', 'value': 96.6},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'Fertility', 'value': 96.6},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'Fertility', 'value': 96.5},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'Fertility', 'value': 96.4},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'Fertility', 'value': 96.3},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'Fertility', 'value': 96.2},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'Fertility', 'value': 96.1},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'Fertility', 'value': 96.1},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'Fertility', 'value': 96.0},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'Fertility', 'value': 95.8},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'Fertility', 'value': 95.5},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'Fertility', 'value': 95.3},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'Fertility', 'value': 95.0},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'Fertility', 'value': 94.8},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'Fertility', 'value': 94.5},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'Fertility', 'value': 94.2},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'Fertility', 'value': 93.8},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'Fertility', 'value': 93.3},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'Fertility', 'value': 92.7},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'Fertility', 'value': 92.2},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'Fertility', 'value': 91.7},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'Fertility', 'value': 91.3},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'Fertility', 'value': 90.8},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'Fertility', 'value': 90.4},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'Fertility', 'value': 89.9},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'Fertility', 'value': 89.4},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'Fertility', 'value': 89.0},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'Fertility', 'value': 88.53},
      // ── Arbo — HOF ────────────────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'HOF', 'value': 0.0},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'HOF', 'value': 84.05},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'HOF', 'value': 86.49},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'HOF', 'value': 88.32},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'HOF', 'value': 89.95},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'HOF', 'value': 91.15},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'HOF', 'value': 92.01},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'HOF', 'value': 92.65},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'HOF', 'value': 93.17},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'HOF', 'value': 93.59},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'HOF', 'value': 93.80},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'HOF', 'value': 93.90},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'HOF', 'value': 93.89},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'HOF', 'value': 93.79},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'HOF', 'value': 93.48},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'HOF', 'value': 93.26},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'HOF', 'value': 93.05},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'HOF', 'value': 92.73},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'HOF', 'value': 92.31},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'HOF', 'value': 91.88},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'HOF', 'value': 91.36},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'HOF', 'value': 90.83},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'HOF', 'value': 90.50},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'HOF', 'value': 90.16},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'HOF', 'value': 89.61},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'HOF', 'value': 89.26},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'HOF', 'value': 88.71},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'HOF', 'value': 88.25},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'HOF', 'value': 87.79},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'HOF', 'value': 87.42},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'HOF', 'value': 87.14},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'HOF', 'value': 86.84},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'HOF', 'value': 86.55},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'HOF', 'value': 86.15},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'HOF', 'value': 85.65},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'HOF', 'value': 85.24},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'HOF', 'value': 84.73},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'HOF', 'value': 84.20},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'HOF', 'value': 83.78},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'HOF', 'value': 83.15},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'HOF', 'value': 82.64},
      // ── Arbo — ChickWeight ────────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'ChickWeight', 'value': 50.2},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'ChickWeight', 'value': 51.9},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'ChickWeight', 'value': 53.6},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'ChickWeight', 'value': 55.2},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'ChickWeight', 'value': 56.5},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'ChickWeight', 'value': 57.6},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'ChickWeight', 'value': 58.6},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'ChickWeight', 'value': 59.5},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'ChickWeight', 'value': 60.2},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'ChickWeight', 'value': 60.9},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'ChickWeight', 'value': 61.5},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'ChickWeight', 'value': 62.1},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'ChickWeight', 'value': 62.6},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'ChickWeight', 'value': 63.1},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'ChickWeight', 'value': 63.5},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'ChickWeight', 'value': 64.0},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'ChickWeight', 'value': 64.4},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'ChickWeight', 'value': 64.8},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'ChickWeight', 'value': 65.3},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'ChickWeight', 'value': 65.7},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'ChickWeight', 'value': 66.1},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'ChickWeight', 'value': 66.5},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'ChickWeight', 'value': 66.9},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'ChickWeight', 'value': 67.3},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'ChickWeight', 'value': 67.7},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'ChickWeight', 'value': 68.0},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'ChickWeight', 'value': 68.4},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'ChickWeight', 'value': 68.7},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'ChickWeight', 'value': 69.0},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'ChickWeight', 'value': 69.3},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'ChickWeight', 'value': 69.5},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'ChickWeight', 'value': 69.8},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'ChickWeight', 'value': 70.0},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'ChickWeight', 'value': 70.2},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'ChickWeight', 'value': 70.3},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'ChickWeight', 'value': 70.5},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'ChickWeight', 'value': 70.7},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'ChickWeight', 'value': 70.8},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'ChickWeight', 'value': 71.0},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'ChickWeight', 'value': 71.2},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'ChickWeight', 'value': 71.4},
      // ── Ross 308 — Hatchability ───────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'Hatchability', 'value': 0.0},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'Hatchability', 'value': 79.3},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'Hatchability', 'value': 82.1},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'Hatchability', 'value': 84.5},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'Hatchability', 'value': 86.2},
      // ── Ross 308 — Fertility ──────────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'Fertility', 'value': 0.0},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'Fertility', 'value': 92.8},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'Fertility', 'value': 94.0},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'Fertility', 'value': 95.0},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'Fertility', 'value': 95.5},
      // ── Ross 308 — HOF ────────────────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'HOF', 'value': 0.0},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'HOF', 'value': 85.45},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'HOF', 'value': 87.34},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'HOF', 'value': 88.95},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'HOF', 'value': 90.26},
      // ── Ross 308 — ChickWeight ────────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'ChickWeight', 'value': 49.4},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'ChickWeight', 'value': 51.5},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'ChickWeight', 'value': 52.9},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'ChickWeight', 'value': 54.1},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'ChickWeight', 'value': 55.3},
    ];

    final batch = db.batch();
    for (int i = 0; i < data.length; i++) {
      final row = data[i];
      batch.insert('benchmarks', {
        'id': 'bm_${i.toString().padLeft(3, '0')}',
        'breed': row['breed'],
        'age_weeks': row['age_weeks'],
        'parameter': row['parameter'],
        'value': row['value'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    await _seedBreakoutBenchmarks(db);
  }

  /// Seeds age-varying Infertile, EarlyDead and LateDead benchmarks.
  /// Uses ConflictAlgorithm.ignore so it is safe to call on existing databases.
  Future<void> _seedBreakoutBenchmarks(Database db) async {
    // Values represent % of eggs set, varying with flock age (weeks 25-65).
    // Source: Arbo Acres and Ross 308 management guides / industry norms.
    final data = <Map<String, dynamic>>[
      // ── Arbo — Infertile % ───────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'Infertile', 'value': 8.0},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'Infertile', 'value': 6.0},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'Infertile', 'value': 5.0},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'Infertile', 'value': 4.5},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'Infertile', 'value': 4.0},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'Infertile', 'value': 3.8},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'Infertile', 'value': 3.6},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'Infertile', 'value': 3.5},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'Infertile', 'value': 3.3},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'Infertile', 'value': 3.2},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'Infertile', 'value': 3.1},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'Infertile', 'value': 3.2},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'Infertile', 'value': 3.3},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'Infertile', 'value': 3.5},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'Infertile', 'value': 3.7},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'Infertile', 'value': 3.9},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'Infertile', 'value': 4.2},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'Infertile', 'value': 4.5},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'Infertile', 'value': 4.8},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'Infertile', 'value': 5.0},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'Infertile', 'value': 5.3},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'Infertile', 'value': 5.6},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'Infertile', 'value': 5.8},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'Infertile', 'value': 6.0},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'Infertile', 'value': 6.2},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'Infertile', 'value': 6.4},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'Infertile', 'value': 6.6},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'Infertile', 'value': 6.8},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'Infertile', 'value': 7.0},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'Infertile', 'value': 7.2},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'Infertile', 'value': 7.3},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'Infertile', 'value': 7.4},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'Infertile', 'value': 7.5},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'Infertile', 'value': 7.6},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'Infertile', 'value': 7.7},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'Infertile', 'value': 7.8},
      // ── Arbo — EarlyDead % ───────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'EarlyDead', 'value': 2.0},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'EarlyDead', 'value': 1.8},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'EarlyDead', 'value': 1.6},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'EarlyDead', 'value': 1.5},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'EarlyDead', 'value': 1.4},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'EarlyDead', 'value': 1.3},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'EarlyDead', 'value': 0.9},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'EarlyDead', 'value': 0.9},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'EarlyDead', 'value': 0.9},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'EarlyDead', 'value': 0.9},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'EarlyDead', 'value': 0.9},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'EarlyDead', 'value': 1.3},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'EarlyDead', 'value': 1.3},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'EarlyDead', 'value': 1.4},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'EarlyDead', 'value': 1.4},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'EarlyDead', 'value': 1.5},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'EarlyDead', 'value': 1.5},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'EarlyDead', 'value': 1.6},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'EarlyDead', 'value': 1.6},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'EarlyDead', 'value': 1.7},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'EarlyDead', 'value': 1.7},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'EarlyDead', 'value': 1.8},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'EarlyDead', 'value': 1.8},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'EarlyDead', 'value': 1.9},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'EarlyDead', 'value': 1.9},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'EarlyDead', 'value': 2.0},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'EarlyDead', 'value': 2.0},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'EarlyDead', 'value': 2.1},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'EarlyDead', 'value': 2.2},
      // ── Arbo — LateDead % ────────────────────────────────────────────────
      {'breed': 'Arbo', 'age_weeks': 25, 'parameter': 'LateDead', 'value': 2.5},
      {'breed': 'Arbo', 'age_weeks': 26, 'parameter': 'LateDead', 'value': 2.2},
      {'breed': 'Arbo', 'age_weeks': 27, 'parameter': 'LateDead', 'value': 2.0},
      {'breed': 'Arbo', 'age_weeks': 28, 'parameter': 'LateDead', 'value': 1.8},
      {'breed': 'Arbo', 'age_weeks': 29, 'parameter': 'LateDead', 'value': 1.6},
      {'breed': 'Arbo', 'age_weeks': 30, 'parameter': 'LateDead', 'value': 1.5},
      {'breed': 'Arbo', 'age_weeks': 31, 'parameter': 'LateDead', 'value': 1.4},
      {'breed': 'Arbo', 'age_weeks': 32, 'parameter': 'LateDead', 'value': 1.3},
      {'breed': 'Arbo', 'age_weeks': 33, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 34, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 35, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 36, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 37, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 38, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 39, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Arbo', 'age_weeks': 40, 'parameter': 'LateDead', 'value': 1.3},
      {'breed': 'Arbo', 'age_weeks': 41, 'parameter': 'LateDead', 'value': 1.3},
      {'breed': 'Arbo', 'age_weeks': 42, 'parameter': 'LateDead', 'value': 1.4},
      {'breed': 'Arbo', 'age_weeks': 43, 'parameter': 'LateDead', 'value': 1.4},
      {'breed': 'Arbo', 'age_weeks': 44, 'parameter': 'LateDead', 'value': 1.5},
      {'breed': 'Arbo', 'age_weeks': 45, 'parameter': 'LateDead', 'value': 1.5},
      {'breed': 'Arbo', 'age_weeks': 46, 'parameter': 'LateDead', 'value': 1.6},
      {'breed': 'Arbo', 'age_weeks': 47, 'parameter': 'LateDead', 'value': 1.7},
      {'breed': 'Arbo', 'age_weeks': 48, 'parameter': 'LateDead', 'value': 1.8},
      {'breed': 'Arbo', 'age_weeks': 49, 'parameter': 'LateDead', 'value': 1.9},
      {'breed': 'Arbo', 'age_weeks': 50, 'parameter': 'LateDead', 'value': 2.0},
      {'breed': 'Arbo', 'age_weeks': 51, 'parameter': 'LateDead', 'value': 2.0},
      {'breed': 'Arbo', 'age_weeks': 52, 'parameter': 'LateDead', 'value': 2.1},
      {'breed': 'Arbo', 'age_weeks': 53, 'parameter': 'LateDead', 'value': 2.2},
      {'breed': 'Arbo', 'age_weeks': 54, 'parameter': 'LateDead', 'value': 2.2},
      {'breed': 'Arbo', 'age_weeks': 55, 'parameter': 'LateDead', 'value': 2.3},
      {'breed': 'Arbo', 'age_weeks': 56, 'parameter': 'LateDead', 'value': 2.4},
      {'breed': 'Arbo', 'age_weeks': 57, 'parameter': 'LateDead', 'value': 2.4},
      {'breed': 'Arbo', 'age_weeks': 58, 'parameter': 'LateDead', 'value': 2.5},
      {'breed': 'Arbo', 'age_weeks': 59, 'parameter': 'LateDead', 'value': 2.5},
      {'breed': 'Arbo', 'age_weeks': 60, 'parameter': 'LateDead', 'value': 2.6},
      {'breed': 'Arbo', 'age_weeks': 61, 'parameter': 'LateDead', 'value': 2.6},
      {'breed': 'Arbo', 'age_weeks': 62, 'parameter': 'LateDead', 'value': 2.7},
      {'breed': 'Arbo', 'age_weeks': 63, 'parameter': 'LateDead', 'value': 2.7},
      {'breed': 'Arbo', 'age_weeks': 64, 'parameter': 'LateDead', 'value': 2.8},
      {'breed': 'Arbo', 'age_weeks': 65, 'parameter': 'LateDead', 'value': 2.9},
      // ── Ross 308 — Infertile % ───────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'Infertile', 'value': 8.5},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'Infertile', 'value': 6.5},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'Infertile', 'value': 5.5},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'Infertile', 'value': 5.0},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'Infertile', 'value': 4.5},
      {'breed': 'Ross 308', 'age_weeks': 30, 'parameter': 'Infertile', 'value': 4.0},
      {'breed': 'Ross 308', 'age_weeks': 31, 'parameter': 'Infertile', 'value': 3.8},
      {'breed': 'Ross 308', 'age_weeks': 32, 'parameter': 'Infertile', 'value': 3.6},
      {'breed': 'Ross 308', 'age_weeks': 33, 'parameter': 'Infertile', 'value': 3.4},
      {'breed': 'Ross 308', 'age_weeks': 34, 'parameter': 'Infertile', 'value': 3.2},
      {'breed': 'Ross 308', 'age_weeks': 35, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 36, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 37, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 38, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 39, 'parameter': 'Infertile', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 40, 'parameter': 'Infertile', 'value': 3.2},
      {'breed': 'Ross 308', 'age_weeks': 41, 'parameter': 'Infertile', 'value': 3.4},
      {'breed': 'Ross 308', 'age_weeks': 42, 'parameter': 'Infertile', 'value': 3.6},
      {'breed': 'Ross 308', 'age_weeks': 43, 'parameter': 'Infertile', 'value': 3.8},
      {'breed': 'Ross 308', 'age_weeks': 44, 'parameter': 'Infertile', 'value': 4.0},
      {'breed': 'Ross 308', 'age_weeks': 45, 'parameter': 'Infertile', 'value': 4.2},
      {'breed': 'Ross 308', 'age_weeks': 46, 'parameter': 'Infertile', 'value': 4.5},
      {'breed': 'Ross 308', 'age_weeks': 47, 'parameter': 'Infertile', 'value': 4.8},
      {'breed': 'Ross 308', 'age_weeks': 48, 'parameter': 'Infertile', 'value': 5.0},
      {'breed': 'Ross 308', 'age_weeks': 49, 'parameter': 'Infertile', 'value': 5.3},
      {'breed': 'Ross 308', 'age_weeks': 50, 'parameter': 'Infertile', 'value': 5.5},
      {'breed': 'Ross 308', 'age_weeks': 51, 'parameter': 'Infertile', 'value': 5.8},
      {'breed': 'Ross 308', 'age_weeks': 52, 'parameter': 'Infertile', 'value': 6.0},
      {'breed': 'Ross 308', 'age_weeks': 53, 'parameter': 'Infertile', 'value': 6.2},
      {'breed': 'Ross 308', 'age_weeks': 54, 'parameter': 'Infertile', 'value': 6.4},
      {'breed': 'Ross 308', 'age_weeks': 55, 'parameter': 'Infertile', 'value': 6.6},
      {'breed': 'Ross 308', 'age_weeks': 56, 'parameter': 'Infertile', 'value': 6.8},
      {'breed': 'Ross 308', 'age_weeks': 57, 'parameter': 'Infertile', 'value': 7.0},
      {'breed': 'Ross 308', 'age_weeks': 58, 'parameter': 'Infertile', 'value': 7.2},
      {'breed': 'Ross 308', 'age_weeks': 59, 'parameter': 'Infertile', 'value': 7.4},
      {'breed': 'Ross 308', 'age_weeks': 60, 'parameter': 'Infertile', 'value': 7.5},
      {'breed': 'Ross 308', 'age_weeks': 61, 'parameter': 'Infertile', 'value': 7.6},
      {'breed': 'Ross 308', 'age_weeks': 62, 'parameter': 'Infertile', 'value': 7.7},
      {'breed': 'Ross 308', 'age_weeks': 63, 'parameter': 'Infertile', 'value': 7.8},
      {'breed': 'Ross 308', 'age_weeks': 64, 'parameter': 'Infertile', 'value': 7.9},
      {'breed': 'Ross 308', 'age_weeks': 65, 'parameter': 'Infertile', 'value': 8.0},
      // ── Ross 308 — EarlyDead % ───────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'EarlyDead', 'value': 2.2},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'EarlyDead', 'value': 2.0},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'EarlyDead', 'value': 1.8},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'EarlyDead', 'value': 1.6},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'EarlyDead', 'value': 1.5},
      {'breed': 'Ross 308', 'age_weeks': 30, 'parameter': 'EarlyDead', 'value': 1.4},
      {'breed': 'Ross 308', 'age_weeks': 31, 'parameter': 'EarlyDead', 'value': 1.3},
      {'breed': 'Ross 308', 'age_weeks': 32, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 33, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Ross 308', 'age_weeks': 34, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Ross 308', 'age_weeks': 35, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Ross 308', 'age_weeks': 36, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Ross 308', 'age_weeks': 37, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Ross 308', 'age_weeks': 38, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Ross 308', 'age_weeks': 39, 'parameter': 'EarlyDead', 'value': 1.0},
      {'breed': 'Ross 308', 'age_weeks': 40, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Ross 308', 'age_weeks': 41, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Ross 308', 'age_weeks': 42, 'parameter': 'EarlyDead', 'value': 1.1},
      {'breed': 'Ross 308', 'age_weeks': 43, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 44, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 45, 'parameter': 'EarlyDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 46, 'parameter': 'EarlyDead', 'value': 1.3},
      {'breed': 'Ross 308', 'age_weeks': 47, 'parameter': 'EarlyDead', 'value': 1.3},
      {'breed': 'Ross 308', 'age_weeks': 48, 'parameter': 'EarlyDead', 'value': 1.4},
      {'breed': 'Ross 308', 'age_weeks': 49, 'parameter': 'EarlyDead', 'value': 1.4},
      {'breed': 'Ross 308', 'age_weeks': 50, 'parameter': 'EarlyDead', 'value': 1.5},
      {'breed': 'Ross 308', 'age_weeks': 51, 'parameter': 'EarlyDead', 'value': 1.5},
      {'breed': 'Ross 308', 'age_weeks': 52, 'parameter': 'EarlyDead', 'value': 1.6},
      {'breed': 'Ross 308', 'age_weeks': 53, 'parameter': 'EarlyDead', 'value': 1.6},
      {'breed': 'Ross 308', 'age_weeks': 54, 'parameter': 'EarlyDead', 'value': 1.7},
      {'breed': 'Ross 308', 'age_weeks': 55, 'parameter': 'EarlyDead', 'value': 1.7},
      {'breed': 'Ross 308', 'age_weeks': 56, 'parameter': 'EarlyDead', 'value': 1.8},
      {'breed': 'Ross 308', 'age_weeks': 57, 'parameter': 'EarlyDead', 'value': 1.9},
      {'breed': 'Ross 308', 'age_weeks': 58, 'parameter': 'EarlyDead', 'value': 1.9},
      {'breed': 'Ross 308', 'age_weeks': 59, 'parameter': 'EarlyDead', 'value': 2.0},
      {'breed': 'Ross 308', 'age_weeks': 60, 'parameter': 'EarlyDead', 'value': 2.0},
      {'breed': 'Ross 308', 'age_weeks': 61, 'parameter': 'EarlyDead', 'value': 2.1},
      {'breed': 'Ross 308', 'age_weeks': 62, 'parameter': 'EarlyDead', 'value': 2.2},
      {'breed': 'Ross 308', 'age_weeks': 63, 'parameter': 'EarlyDead', 'value': 2.2},
      {'breed': 'Ross 308', 'age_weeks': 64, 'parameter': 'EarlyDead', 'value': 2.3},
      {'breed': 'Ross 308', 'age_weeks': 65, 'parameter': 'EarlyDead', 'value': 2.4},
      // ── Ross 308 — LateDead % ────────────────────────────────────────────
      {'breed': 'Ross 308', 'age_weeks': 25, 'parameter': 'LateDead', 'value': 2.8},
      {'breed': 'Ross 308', 'age_weeks': 26, 'parameter': 'LateDead', 'value': 2.5},
      {'breed': 'Ross 308', 'age_weeks': 27, 'parameter': 'LateDead', 'value': 2.2},
      {'breed': 'Ross 308', 'age_weeks': 28, 'parameter': 'LateDead', 'value': 2.0},
      {'breed': 'Ross 308', 'age_weeks': 29, 'parameter': 'LateDead', 'value': 1.8},
      {'breed': 'Ross 308', 'age_weeks': 30, 'parameter': 'LateDead', 'value': 1.6},
      {'breed': 'Ross 308', 'age_weeks': 31, 'parameter': 'LateDead', 'value': 1.5},
      {'breed': 'Ross 308', 'age_weeks': 32, 'parameter': 'LateDead', 'value': 1.4},
      {'breed': 'Ross 308', 'age_weeks': 33, 'parameter': 'LateDead', 'value': 1.3},
      {'breed': 'Ross 308', 'age_weeks': 34, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 35, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 36, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 37, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 38, 'parameter': 'LateDead', 'value': 1.2},
      {'breed': 'Ross 308', 'age_weeks': 39, 'parameter': 'LateDead', 'value': 1.3},
      {'breed': 'Ross 308', 'age_weeks': 40, 'parameter': 'LateDead', 'value': 1.3},
      {'breed': 'Ross 308', 'age_weeks': 41, 'parameter': 'LateDead', 'value': 1.4},
      {'breed': 'Ross 308', 'age_weeks': 42, 'parameter': 'LateDead', 'value': 1.4},
      {'breed': 'Ross 308', 'age_weeks': 43, 'parameter': 'LateDead', 'value': 1.5},
      {'breed': 'Ross 308', 'age_weeks': 44, 'parameter': 'LateDead', 'value': 1.5},
      {'breed': 'Ross 308', 'age_weeks': 45, 'parameter': 'LateDead', 'value': 1.6},
      {'breed': 'Ross 308', 'age_weeks': 46, 'parameter': 'LateDead', 'value': 1.7},
      {'breed': 'Ross 308', 'age_weeks': 47, 'parameter': 'LateDead', 'value': 1.8},
      {'breed': 'Ross 308', 'age_weeks': 48, 'parameter': 'LateDead', 'value': 1.9},
      {'breed': 'Ross 308', 'age_weeks': 49, 'parameter': 'LateDead', 'value': 2.0},
      {'breed': 'Ross 308', 'age_weeks': 50, 'parameter': 'LateDead', 'value': 2.1},
      {'breed': 'Ross 308', 'age_weeks': 51, 'parameter': 'LateDead', 'value': 2.2},
      {'breed': 'Ross 308', 'age_weeks': 52, 'parameter': 'LateDead', 'value': 2.2},
      {'breed': 'Ross 308', 'age_weeks': 53, 'parameter': 'LateDead', 'value': 2.3},
      {'breed': 'Ross 308', 'age_weeks': 54, 'parameter': 'LateDead', 'value': 2.4},
      {'breed': 'Ross 308', 'age_weeks': 55, 'parameter': 'LateDead', 'value': 2.5},
      {'breed': 'Ross 308', 'age_weeks': 56, 'parameter': 'LateDead', 'value': 2.5},
      {'breed': 'Ross 308', 'age_weeks': 57, 'parameter': 'LateDead', 'value': 2.6},
      {'breed': 'Ross 308', 'age_weeks': 58, 'parameter': 'LateDead', 'value': 2.7},
      {'breed': 'Ross 308', 'age_weeks': 59, 'parameter': 'LateDead', 'value': 2.7},
      {'breed': 'Ross 308', 'age_weeks': 60, 'parameter': 'LateDead', 'value': 2.8},
      {'breed': 'Ross 308', 'age_weeks': 61, 'parameter': 'LateDead', 'value': 2.9},
      {'breed': 'Ross 308', 'age_weeks': 62, 'parameter': 'LateDead', 'value': 2.9},
      {'breed': 'Ross 308', 'age_weeks': 63, 'parameter': 'LateDead', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 64, 'parameter': 'LateDead', 'value': 3.0},
      {'breed': 'Ross 308', 'age_weeks': 65, 'parameter': 'LateDead', 'value': 3.1},
    ];

    final batch = db.batch();
    for (int i = 0; i < data.length; i++) {
      final row = data[i];
      batch.insert('benchmarks', {
        'id': 'bm_bo_${i.toString().padLeft(3, '0')}',
        'breed': row['breed'],
        'age_weeks': row['age_weeks'],
        'parameter': row['parameter'],
        'value': row['value'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ── Egg Breakout Interpretations ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEggBreakoutInterpretations() async {
    final db = await database;
    return db.query('egg_breakout_interpretations', orderBy: 'category ASC');
  }

  Future<Map<String, dynamic>?> getInterpretationByCondition(
      String condition) async {
    final db = await database;
    final maps = await db.query(
      'egg_breakout_interpretations',
      where: 'condition = ?',
      whereArgs: [condition],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<void> _seedEggBreakoutInterpretations(Database db) async {
    final data = [
      {
        'id': 'ebi_infertile',
        'category': 'Embryo Mortality',
        'condition': 'Infertile',
        'hatchery_causes':
            'Incorrect egg storage temperature or duration. Improper setter temperature/humidity. Eggs stored too long before incubation. Poor egg handling causing embryo death before setting.',
        'farm_causes':
            'Poor male to female ratio. Male health issues (leg problems, disease). Inadequate mating. Hen age extremes (too young or too old). Nutritional deficiencies in breeders. Poor flock management.',
      },
      {
        'id': 'ebi_24h_early_dead',
        'category': 'Embryo Mortality',
        'condition': '24h Early Dead',
        'hatchery_causes':
            'Rough egg handling during collection or transport. Excessive vibration during transport. Incorrect pre-warming of eggs. Setter temperature too high at start of incubation.',
        'farm_causes':
            'Disease in breeder flock (Mycoplasma, IBD, ND). Vertical transmission of pathogens. Nutritional deficiencies (Vitamin E, Selenium). Contaminated eggs. Poor biosecurity.',
      },
      {
        'id': 'ebi_48h_early_dead',
        'category': 'Embryo Mortality',
        'condition': '48h Early Dead',
        'hatchery_causes':
            'Setter temperature fluctuations. Inadequate egg turning in early incubation. Poor ventilation in setter. Contaminated setter environment.',
        'farm_causes':
            'Viral infections in breeder flock. Nutritional deficiencies (Riboflavin, Biotin). Poor egg sanitation. High bacterial contamination of eggs. Heat/cold stress in breeders.',
      },
      {
        'id': 'ebi_blood_ring',
        'category': 'Embryo Mortality',
        'condition': 'Blood Ring',
        'hatchery_causes':
            'Temperature too low or too high during early incubation (days 1-7). Poor egg turning. Setter malfunctions. Contaminated eggs causing early bacterial infection.',
        'farm_causes':
            'Disease in breeder flock. Poor egg sanitation at farm level. Long storage time before incubation. Heat stress in breeder hens. Nutritional deficiencies.',
      },
      {
        'id': 'ebi_early_dead',
        'category': 'Embryo Mortality',
        'condition': 'Early Dead',
        'hatchery_causes':
            'Temperature deviations during days 3-7. Poor turning frequency or angle. Inadequate ventilation. Bacterial contamination in setter. Egg storage problems.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Vitamin A, E, B12, Riboflavin). Disease (Marek\'s, Mycoplasma). Flock age effects. Poor egg quality. Contaminated nest boxes.',
      },
      {
        'id': 'ebi_mid_black_eye',
        'category': 'Embryo Mortality',
        'condition': 'Mid Black Eye',
        'hatchery_causes':
            'Temperature deviations during mid-incubation (days 8-14). Inadequate turning. Poor ventilation causing CO2 buildup. Humidity too low causing excessive evaporation.',
        'farm_causes':
            'Nutritional deficiencies (Riboflavin, Pantothenic acid, Biotin). Disease in breeders. Genetic factors. Flock age. Poor breeder nutrition management.',
      },
      {
        'id': 'ebi_feathers',
        'category': 'Embryo Mortality',
        'condition': 'Feathers',
        'hatchery_causes':
            'Temperature too high during incubation causing abnormal development. Humidity fluctuations. Improper egg turning direction.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Biotin, Folic acid, Niacin). Genetic issues. Breeder flock diseases. Hormonal imbalances.',
      },
      {
        'id': 'ebi_turned',
        'category': 'Embryo Mortality',
        'condition': 'Turned',
        'hatchery_causes':
            'Turning mechanism failure. Incorrect turning angle (should be 45°). Turning stopped at wrong stage. Malposition due to poor turning.',
        'farm_causes':
            'Egg shape abnormalities making turning difficult. Small eggs with incorrect air cell position. Poor egg shell quality affecting embryo movement.',
      },
      {
        'id': 'ebi_internal_pip',
        'category': 'Embryo Mortality',
        'condition': 'Internal Pip',
        'hatchery_causes':
            'Transfer too late from setter to hatcher. Hatcher temperature too high or humidity too low, drying out membranes. Poor ventilation in hatcher. CO2 levels too high.',
        'farm_causes':
            'Nutritional deficiencies in breeders. Weak chick syndrome. Disease causing weakness. Abnormal egg size affecting air cell.',
      },
      {
        'id': 'ebi_late_dead',
        'category': 'Embryo Mortality',
        'condition': 'Late Dead',
        'hatchery_causes':
            'Hatcher temperature too high or too low. Poor ventilation and high CO2 in hatcher. Low humidity causing sticky chick syndrome. Transfer timing issues. Dirty hatcher environment.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Vitamin E, K, B12). Disease (Newcastle, IBD, Marek\'s). Flock age (young and old flocks). Egg storage too long. Contaminated eggs.',
      },
      {
        'id': 'ebi_external_pip',
        'category': 'Embryo Mortality',
        'condition': 'External Pip',
        'hatchery_causes':
            'Hatcher humidity too low causing membranes to dry and trap chick. Temperature fluctuations at hatch time. CO2 imbalance. Inadequate ventilation during hatching.',
        'farm_causes':
            'Weak chick syndrome from nutritional deficiencies. Disease causing weakness. Abnormal egg size or shape. Excessive egg storage before incubation.',
      },
      {
        'id': 'ebi_contaminated',
        'category': 'Contamination',
        'condition': 'Contaminated',
        'hatchery_causes':
            'Poor setter/hatcher sanitation. Inadequate fumigation. Cross-contamination from dirty eggs. Poor hatchery hygiene protocols. Recycled air without proper filtration.',
        'farm_causes':
            'Dirty nest boxes. Wet litter in breeding houses. Poor egg collection frequency. Cracked eggs not removed promptly. High bacterial load in breeding environment.',
      },
      {
        'id': 'ebi_cracked',
        'category': 'Contamination',
        'condition': 'Cracked',
        'hatchery_causes':
            'Rough handling during egg collection, grading, or setting. Incorrect tray loading. Mechanical egg handling equipment issues. Transport vibration.',
        'farm_causes':
            'Poor shell quality from nutritional deficiencies (Calcium, Phosphorus, Vitamin D3). Disease (IB, EDS). Flock age extremes. Heat stress. Rough handling at farm.',
      },
      {
        'id': 'ebi_exposed_brain',
        'category': 'Malformation',
        'condition': 'Exposed Brain',
        'hatchery_causes':
            'Temperature too high early in incubation (days 1-4). Exposure to disinfectants or fumes. Incorrect egg fumigation.',
        'farm_causes':
            'Nutritional deficiencies (Riboflavin, Folic acid, Vitamin A). Genetic predisposition. Mycotoxin exposure in breeder feed. Viral infections in breeders.',
      },
      {
        'id': 'ebi_crossed_beak',
        'category': 'Malformation',
        'condition': 'Crossed Peak / One Eyed',
        'hatchery_causes':
            'Temperature fluctuations during critical development periods. Mechanical pressure on eggs during incubation.',
        'farm_causes':
            'Genetic predisposition. Nutritional deficiencies (Biotin, Riboflavin). Mycotoxins in breeder feed. Infectious agents. High incidence suggests genetic line issue.',
      },
      {
        'id': 'ebi_malpositions',
        'category': 'Malformation',
        'condition': 'Malpositions',
        'hatchery_causes':
            'Incorrect egg position in trays. Poor turning during incubation. Transfer to hatcher with incorrect orientation. Temperature deviations.',
        'farm_causes':
            'Abnormal egg shape. Nutritional deficiencies. Breeder disease. Eggs set with small end up. Air cell displacement.',
      },
      {
        'id': 'ebi_general_malformation',
        'category': 'Malformation',
        'condition': 'General Malformation',
        'hatchery_causes':
            'Temperature deviations at critical developmental periods. Chemical exposure. Fumigation errors. Incubator malfunction.',
        'farm_causes':
            'Nutritional deficiencies in breeders. Genetic issues. Viral infections during laying (IBV, NDV). Mycotoxins. Drug/vaccine side effects in breeders.',
      },
      {
        'id': 'ebi_pasgar_reflexes',
        'category': 'Chick Quality',
        'condition': 'Pasgar Reflexes',
        'hatchery_causes':
            'Extended hatch window causing chick exhaustion. Hatcher temperature too high causing heat stress. Early pull causing incomplete yolk absorption. Over-holding after hatch.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Selenium, Vitamin E). Disease in breeder flock. Poor egg storage. Weak chick syndrome.',
      },
      {
        'id': 'ebi_pasgar_beak',
        'category': 'Chick Quality',
        'condition': 'Pasgar Beak',
        'hatchery_causes':
            'Temperature issues causing beak deformities. Mechanical damage during hatching.',
        'farm_causes':
            'Genetic predisposition. Nutritional deficiencies (Biotin, Riboflavin). Mycotoxin exposure. Viral infections in breeders.',
      },
      {
        'id': 'ebi_pasgar_navel',
        'category': 'Chick Quality',
        'condition': 'Pasgar Navel',
        'hatchery_causes':
            'Hatcher humidity too low drying navel. Temperature too high causing early hatch before complete yolk absorption. Dirty hatcher environment causing infection. Over-holding in hatcher.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Vitamin E, Biotin). High bacterial load in eggs. Omphalitis-causing bacteria from breeder environment. Poor egg sanitation.',
      },
      {
        'id': 'ebi_pasgar_belly',
        'category': 'Chick Quality',
        'condition': 'Pasgar Belly',
        'hatchery_causes':
            'Hatcher temperature too high or too low. Early transfer affecting yolk absorption. Extended hold time after hatching. High humidity interfering with yolk absorption.',
        'farm_causes':
            'Nutritional deficiencies in breeders. Flock age (very young flocks). Viral infections (Gumboro, Marek\'s). Mycotoxins. Overfeeding of breeders.',
      },
      {
        'id': 'ebi_pasgar_leg',
        'category': 'Chick Quality',
        'condition': 'Pasgar Leg',
        'hatchery_causes':
            'Slippery hatcher floor causing splayed legs. Extended hatch window causing leg fatigue. Overcrowding in hatcher. Incorrect basket type.',
        'farm_causes':
            'Nutritional deficiencies (Riboflavin, Manganese, Biotin). Genetic predisposition. Mycoplasma synoviae. Viral arthritis. Chilling or overheating of newly hatched chicks.',
      },
      {
        'id': 'ebi_wing_feathers',
        'category': 'Chick Quality',
        'condition': 'Well-developed Wing Feathers',
        'hatchery_causes':
            'Temperature deviations affecting feather development timing. Hatch time variation affecting feather maturity at pull.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Biotin, Niacin, Pantothenic acid, Zinc). Genetic line variation. Flock age effects on feathering quality.',
      },
      {
        'id': 'ebi_culled_navel_small_scab',
        'category': 'Chick Quality',
        'condition': 'Culled Navel - Small Scab',
        'hatchery_causes':
            'Hatcher humidity slightly low. Minor bacterial contamination. Early hatch with incomplete navel closure.',
        'farm_causes':
            'Mild omphalitis from environmental bacteria. Minor nutritional deficiency. Slight increase in breeder flock bacterial challenge.',
      },
      {
        'id': 'ebi_culled_navel_big_scab',
        'category': 'Chick Quality',
        'condition': 'Culled Navel - Big Scab',
        'hatchery_causes':
            'Significant hatcher contamination. Very low humidity. Temperature too high causing rapid but incomplete closure. Poor hatcher sanitation.',
        'farm_causes':
            'Significant bacterial challenge (E. coli, Staphylococcus). High omphalitis incidence in breeder flock. Poor nest box hygiene. Contaminated eggs.',
      },
      {
        'id': 'ebi_culled_navel_string',
        'category': 'Chick Quality',
        'condition': 'Culled Navel - String',
        'hatchery_causes':
            'Hatcher humidity too high preventing complete closure. Extended time in hatcher. Temperature issues affecting yolk reabsorption.',
        'farm_causes':
            'Nutritional deficiencies affecting yolk reabsorption. Flock age (young flocks). Overfeeding of breeders affecting yolk size.',
      },
      {
        'id': 'ebi_culled_navel_large_string',
        'category': 'Chick Quality',
        'condition': 'Culled Navel - Large String',
        'hatchery_causes':
            'Significant humidity problem. Early pull with large residual yolk. Temperature deviation causing premature hatch.',
        'farm_causes':
            'Significant nutritional issues in breeders. Very young flock (small eggs with large yolk ratio). Overfeeding causing oversized yolks.',
      },
      {
        'id': 'ebi_culled_navel_open',
        'category': 'Chick Quality',
        'condition': 'Culled Navel - Open Navel',
        'hatchery_causes':
            'Hatcher too dry or too hot. Very early hatch before closure. High bacterial contamination preventing healing. Systemic infection.',
        'farm_causes':
            'Severe omphalitis. High bacterial load in eggs. E. coli or Staphylococcal infection. Poor biosecurity in breeding operation.',
      },
      {
        'id': 'ebi_culled_leg_splayed',
        'category': 'Chick Quality',
        'condition': 'Culled Leg - Splayed',
        'hatchery_causes':
            'Slippery hatcher trays or floors. Overcrowding causing mechanical spreading. Extended hatch window. Incorrect basket surface.',
        'farm_causes':
            'Riboflavin deficiency in breeders. Manganese deficiency. Genetic predisposition. Mycoplasma infection.',
      },
      {
        'id': 'ebi_culled_leg_curled_toes',
        'category': 'Chick Quality',
        'condition': 'Culled Leg - Curled Toes',
        'hatchery_causes':
            'Temperature too high in hatcher. Riboflavin deficiency effects on nerve development. Basket material causing mechanical deformity.',
        'farm_causes':
            'Riboflavin (Vitamin B2) deficiency in breeders — primary cause. Breeder feed quality issues. Mycotoxins affecting Riboflavin metabolism.',
      },
      {
        'id': 'ebi_culled_leg_red_hock',
        'category': 'Chick Quality',
        'condition': 'Culled Leg - Red Hock',
        'hatchery_causes':
            'Abrasive hatcher surfaces causing friction burns. Overcrowding. Extended hold after hatch. Chick stress during hatch.',
        'farm_causes':
            'Viral arthritis (Reovirus). Staphylococcal infection. Selenium/Vitamin E deficiency. Wet litter in brooding environment.',
      },
      {
        'id': 'ebi_culled_leg_short',
        'category': 'Chick Quality',
        'condition': 'Culled Leg - Short Legs',
        'hatchery_causes':
            'Temperature deviations during leg development period.',
        'farm_causes':
            'Genetic factors. Nutritional deficiencies (Manganese, Zinc, Biotin). Mycotoxins. Viral infections during critical development.',
      },
      {
        'id': 'ebi_culled_leg_deformed_hock',
        'category': 'Chick Quality',
        'condition': 'Culled Leg - Deformed Hock',
        'hatchery_causes':
            'Temperature extremes during hock joint development. Mechanical injury in hatcher.',
        'farm_causes':
            'Manganese or Zinc deficiency in breeders. Genetic predisposition. Viral arthritis in breeder flock. Perosis condition from nutritional deficiency.',
      },
      {
        'id': 'ebi_culled_leg_extra_limbs',
        'category': 'Chick Quality',
        'condition': 'Culled Leg - Extra Limbs',
        'hatchery_causes':
            'Temperature deviations at very early embryonic development (days 1-3). Chemical exposure.',
        'farm_causes':
            'Genetic mutations. Folic acid deficiency causing neural tube and limb bud defects. Mycotoxin exposure in breeders. Viral infection during early incubation period.',
      },
      {
        'id': 'ebi_culled_beak_crossed',
        'category': 'Chick Quality',
        'condition': 'Culled Beak - Crossed',
        'hatchery_causes':
            'Temperature deviation during beak development. Egg handling causing mechanical pressure.',
        'farm_causes':
            'Genetic predisposition. Biotin deficiency. Riboflavin deficiency. Mycotoxins. Viral infections in breeder flock.',
      },
      {
        'id': 'ebi_culled_beak_red_dot',
        'category': 'Chick Quality',
        'condition': 'Culled Beak - Red Dot',
        'hatchery_causes':
            'Hatcher contamination causing beak tip infection. High bacterial load. Post-hatch trauma.',
        'farm_causes':
            'Bacterial infection at beak tip. High environmental bacteria in hatchery or early brooding.',
      },
      {
        'id': 'ebi_culled_belly_big',
        'category': 'Chick Quality',
        'condition': 'Culled Belly - Big Belly',
        'hatchery_causes':
            'Early hatch before complete yolk absorption. Hatcher temperature too high. Extended hold time in hatcher.',
        'farm_causes':
            'Overfeeding of breeders creating oversized yolks. Very young flock. Nutritional imbalances in breeder diet.',
      },
      {
        'id': 'ebi_culled_sticky',
        'category': 'Chick Quality',
        'condition': 'Culled Sticky Chicks',
        'hatchery_causes':
            'Humidity too low in hatcher causing membranes to dry before complete emergence. Temperature too high drying egg contents. Poor hatch timing causing some chicks to dry while others still hatching.',
        'farm_causes':
            'Egg storage too long causing excessive evaporation before setting. Poor egg shell quality. Contaminated eggs causing abnormal hatch.',
      },
      {
        'id': 'ebi_culled_poor_feathering',
        'category': 'Chick Quality',
        'condition': 'Culled Poor Feathering',
        'hatchery_causes':
            'Hatcher temperature and humidity affecting feather development at hatch.',
        'farm_causes':
            'Nutritional deficiencies in breeders (Biotin, Niacin, Zinc, Pantothenic acid). Slow feathering genetics. Mycotoxins. Infections affecting feather follicles.',
      },
      {
        'id': 'ebi_culled_small_chicks',
        'category': 'Chick Quality',
        'condition': 'Culled Small Chicks',
        'hatchery_causes':
            'Small eggs set with full-size eggs causing size variation. Early hatch due to temperature. Small egg size from farm.',
        'farm_causes':
            'Young flock producing small eggs. Poor breeder nutrition. Disease reducing egg size. Genetic variation in flock.',
      },
      {
        'id': 'ebi_culled_eye_one_eyed',
        'category': 'Chick Quality',
        'condition': 'Culled Eye - One Eyed',
        'hatchery_causes':
            'Ammonia exposure in hatcher. Chemical irritation. Mechanical injury during hatch. High dust levels.',
        'farm_causes':
            'Infectious Bronchitis affecting eye development. Marek\'s disease. Aspergillosis. Genetic predisposition. Vitamin A deficiency in breeders.',
      },
      {
        'id': 'ebi_hatching_too_early',
        'category': 'Hatch Timing & Uniformity',
        'condition': 'Hatching Too Early',
        'hatchery_causes':
            'Setter or hatcher temperature too high. Calibration error in temperature sensors. Hot spots in incubator. Incubation time too long before expected hatch.',
        'farm_causes':
            'Eggs from very old flock (thin shells, more porous, faster evaporation). Eggs stored at high temperature. Small eggs with higher surface to volume ratio. Eggs set with different ages.',
      },
      {
        'id': 'ebi_hatching_too_late',
        'category': 'Hatch Timing & Uniformity',
        'condition': 'Hatching Too Late',
        'hatchery_causes':
            'Temperature too low in setter or hatcher. Cold spots in incubator. Incorrect calibration of thermometers. Low humidity causing chick to stick in shell.',
        'farm_causes':
            'Heavy, large eggs requiring more heat to incubate. Long egg storage before setting (pre-incubation development slows). Young flock eggs (thicker shells). Low egg temperature at setting.',
      },
      {
        'id': 'ebi_wide_hatch_window',
        'category': 'Hatch Timing & Uniformity',
        'condition': 'Wide Hatch Window',
        'hatchery_causes':
            'Temperature variation within incubator (hot and cold spots). Mixed age eggs set together. Poor air circulation. Temperature fluctuations over incubation period.',
        'farm_causes':
            'Eggs collected over multiple days set together. Mix of egg sizes (large take longer). Mix of egg ages. Poor uniformity in breeder flock age. Eggs from multiple flocks mixed.',
      },
      {
        'id': 'ebi_poor_uniformity_trays',
        'category': 'Hatch Timing & Uniformity',
        'condition': 'Poor Hatch Uniformity Between Trays',
        'hatchery_causes':
            'Temperature gradients between positions in incubator. Poor air distribution. Tray position effects (top vs bottom). Transfer handling damaging some eggs. Uneven egg loading density.',
        'farm_causes':
            'Different egg ages or sizes in same set. Mix of egg sources with different characteristics. Varying egg shell porosity across the flock.',
      },
    ];

    final batch = db.batch();
    for (final row in data) {
      batch.insert(
        'egg_breakout_interpretations',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
