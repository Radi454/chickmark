part of 'database_helper.dart';

Future<void> _createCleanBmkEggBreakoutTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS bmk_egg_breakout (
    id TEXT PRIMARY KEY,
    ageWeek INTEGER NOT NULL UNIQUE,
    infertilePct REAL DEFAULT 0.0,
    early24hPct REAL DEFAULT 0.0,
    early48hPct REAL DEFAULT 0.0,
    bloodRingPct REAL DEFAULT 0.0,
    blackEyePct REAL DEFAULT 0.0,
    earlyDeadPct REAL DEFAULT 0.0,
    midDeadPct REAL DEFAULT 0.0,
    lateDeadPct REAL DEFAULT 0.0,
    externalPipPct REAL DEFAULT 0.0,
    crackedPct REAL DEFAULT 0.0,
    contamPct REAL DEFAULT 0.0,
    CHECK(ageWeek > 0)
  )''');
}

Map<String, Object?> _cleanBmkEggBreakoutSeed(Map<String, dynamic> seed) {
  return {
    'id': seed['id'],
    'ageWeek': seed['ageWeek'],
    'infertilePct': seed['infertilePct'] ?? 0.0,
    'early24hPct': seed['early24hPct'] ?? 0.0,
    'early48hPct': seed['early48hPct'] ?? 0.0,
    'bloodRingPct': seed['bloodRingPct'] ?? 0.0,
    'blackEyePct': seed['blackEyePct'] ?? 0.0,
    'earlyDeadPct': seed['earlyDeadPct'] ?? 0.0,
    'midDeadPct': seed['midDeadPct'] ?? 0.0,
    'lateDeadPct': seed['lateDeadPct'] ?? 0.0,
    'externalPipPct':
        seed['externalPipPct'] ?? seed['pippedExternalPct'] ?? 0.0,
    'crackedPct': seed['crackedPct'] ?? 0.0,
    'contamPct': seed['contamPct'] ?? 0.0,
  };
}

Future<void> _createHatcheryTables(Database db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS hatcheries (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    name TEXT NOT NULL,
    location TEXT,
    notes TEXT,
    createdAt TEXT,
    createdBy TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
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
    completedAt TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_sessions_customer_date ON audit_sessions (customerId, date DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_sessions_flock_date ON audit_sessions (flockId, date DESC)',
  );
}

Future<void> _createStationSamplesTable(Database db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS sample_records (
    id TEXT PRIMARY KEY,
    auditSessionId TEXT NOT NULL,
    legacyAuditId TEXT,
    stationType TEXT NOT NULL,
    sectorType TEXT NOT NULL DEFAULT 'station',
    sampleKind TEXT NOT NULL DEFAULT 'pooled',
    sampleMode TEXT NOT NULL DEFAULT 'pooled',
    comparisonType TEXT,
    sampleIndex INTEGER NOT NULL DEFAULT 1,
    sampleLabel TEXT,
    sampleType TEXT,
    breakoutType TEXT,
    groupKey TEXT,
    groupLabel TEXT,
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
  await db.execute('''CREATE TABLE IF NOT EXISTS sample_house_details (
    sampleRecordId TEXT PRIMARY KEY,
    houseNo TEXT,
    houseLabel TEXT,
    FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS sample_machine_details (
    sampleRecordId TEXT PRIMARY KEY,
    setterNo TEXT,
    hatcherNo TEXT,
    FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS sample_batch_details (
    sampleRecordId TEXT PRIMARY KEY,
    batchNo TEXT,
    hatchNo TEXT,
    storageDays INTEGER,
    incubationDay INTEGER,
    FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS sample_timing_details (
    sampleRecordId TEXT PRIMARY KEY,
    eggProductionDate TEXT,
    settingDate TEXT,
    hatchDate TEXT,
    FOREIGN KEY (sampleRecordId) REFERENCES sample_records(id) ON DELETE CASCADE
  )''');
  await _createStationSamplesIndexes(db);
}

Future<void> _createStationSamplesIndexes(DatabaseExecutor db) async {
  Set<String>? columns;
  try {
    columns = _columnNames(
      await db.rawQuery("PRAGMA table_info('sample_records')"),
    );
  } catch (_) {
    columns = null;
  }
  final hasColumns =
      columns == null ||
      columns.containsAll({'auditSessionId', 'stationType', 'sectorType'});
  if (hasColumns) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_records_session_station ON sample_records (auditSessionId, stationType, sectorType)',
    );
  }
  if (columns == null || columns.containsAll({'auditSessionId', 'groupKey'})) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_records_group ON sample_records (auditSessionId, groupKey)',
    );
  }
  if (columns == null || columns.contains('legacyAuditId')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_records_legacy_audit ON sample_records (legacyAuditId)',
    );
  }
  if (columns == null || columns.contains('calculatedBmkAgeDays')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sample_records_bmk_age ON sample_records (calculatedBmkAgeDays)',
    );
  }
}

Future<void> _createPanelSampleSchemaTables(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    await _createPanelTable(db, panel.tableName);
    await _createPanelSampleTable(db, panel.tableName, panel.sampleTableName);
  }
}

Future<void> _createPanelTable(DatabaseExecutor db, String tableName) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    auditId TEXT,
    customerId TEXT NOT NULL,
    flockId TEXT,
    date TEXT NOT NULL,
    hatcheryId TEXT,
    breed TEXT,
    flockAgeWeeks INTEGER,
    mode TEXT NOT NULL DEFAULT 'pool',
    compareLayer TEXT,
    notes TEXT,
    metricsJson TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    FOREIGN KEY (sessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (auditId) REFERENCES audits(id) ON DELETE SET NULL,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_${tableName}_session ON $tableName (sessionId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_${tableName}_dashboard ON $tableName (customerId, flockId, date)',
  );
}

Future<void> _createPanelSampleTable(
  DatabaseExecutor db,
  String panelTableName,
  String sampleTableName,
) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $sampleTableName (
    id TEXT PRIMARY KEY,
    panelId TEXT NOT NULL,
    scopeType TEXT NOT NULL,
    scopeLabel TEXT NOT NULL,
    sampleIndex INTEGER NOT NULL DEFAULT 0,
    houseId TEXT,
    houseName TEXT,
    setterId TEXT,
    hatcherId TEXT,
    trolleyId TEXT,
    trolleyLabel TEXT,
    trayId TEXT,
    trayLabel TEXT,
    position TEXT,
    sampleSize INTEGER,
    metricType TEXT,
    value REAL,
    unit TEXT,
    summaryJson TEXT,
    rawJson TEXT,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    FOREIGN KEY (panelId) REFERENCES $panelTableName(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_${sampleTableName}_panel ON $sampleTableName (panelId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_${sampleTableName}_scope ON $sampleTableName (scopeType, scopeLabel)',
  );
}

Future<void> _createSyncTombstoneTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS sync_tombstones (
    id TEXT PRIMARY KEY,
    tableName TEXT NOT NULL,
    rowId TEXT NOT NULL,
    deletedAt TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    syncedAt TEXT,
    lastError TEXT
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_tombstones_pending ON sync_tombstones (syncedAt, createdAt)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_tombstones_target ON sync_tombstones (tableName, rowId)',
  );
}

Future<void> _createLegacyStationSamplesIndexes(DatabaseExecutor db) async {
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

Future<void> _createGoveeCaptureTables(Database db) async {
  final hasParentTables =
      await _tableExists(db, 'customers') &&
      await _tableExists(db, 'hatcheries');
  final foreignKeys = hasParentTables
      ? ''',
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE'''
      : '';
  await db.execute('''CREATE TABLE IF NOT EXISTS govee_daily_captures (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    stationKey TEXT NOT NULL DEFAULT '',
    place TEXT NOT NULL,
    machineId TEXT NOT NULL DEFAULT '',
    captureDate TEXT NOT NULL,
    startedAt TEXT,
    endedAt TEXT,
    deviceId TEXT,
    deviceName TEXT,
    status TEXT NOT NULL,
    tempAvg REAL,
    tempMin REAL,
    tempMax REAL,
    tempSd REAL,
    tempCvPct REAL,
    rhAvg REAL,
    rhMin REAL,
    rhMax REAL,
    rhSd REAL,
    rhCvPct REAL,
    readingCount INTEGER NOT NULL,
    chartPointsJson TEXT NOT NULL DEFAULT '[]',
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    UNIQUE(customerId, hatcheryId, place, machineId, captureDate)$foreignKeys
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_govee_daily_scope ON govee_daily_captures (customerId, hatcheryId, place, machineId, captureDate)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_govee_daily_dashboard ON govee_daily_captures (customerId, hatcheryId, captureDate)',
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
