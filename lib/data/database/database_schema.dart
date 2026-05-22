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

Future<void> _createPanelSampleSchemaTables(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    await _createPanelTable(db, panel);
  }
}

const _panelCommonColumnDefinitions = [
  'house TEXT',
  'setter TEXT',
  'hatcher TEXT',
  'trolley TEXT',
  'tray TEXT',
  'position TEXT',
  'storagePeriodDays INTEGER',
  'bmkAgeDays INTEGER',
  'bmkAgeWeeks INTEGER',
];

Future<void> _ensurePanelSampleSchemaColumns(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    final columns = _columnNames(
      await db.rawQuery('PRAGMA table_info(${panel.tableName})'),
    );
    for (final columnDefinition in [
      ..._panelCommonColumnDefinitions,
      ...panel.measurementColumns,
    ]) {
      final columnName = _columnNameFromDefinition(columnDefinition);
      if (columns.contains(columnName)) continue;
      await db.execute(
        'ALTER TABLE ${panel.tableName} ADD COLUMN $columnDefinition',
      );
    }
  }
}

String _columnNameFromDefinition(String definition) {
  return definition.trim().split(RegExp(r'\s+')).first;
}

Future<void> _createPanelTable(
  DatabaseExecutor db,
  PanelSampleDefinition panel,
) async {
  final tableName = panel.tableName;
  final extraColumns = panel.measurementColumns.isEmpty
      ? ''
      : ',\n    ${panel.measurementColumns.join(',\n    ')}';
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    ${_panelCommonColumnDefinitions.join(',\n    ')},
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    lastSyncedAt TEXT,
    syncError TEXT$extraColumns,
    FOREIGN KEY (sessionId) REFERENCES audit_sessions(id) ON DELETE CASCADE,
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
  await db.execute(
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_${tableName}_unique_row ON $tableName (sessionId, IFNULL(house, ''), IFNULL(setter, ''), IFNULL(hatcher, ''), IFNULL(trolley, ''), IFNULL(tray, ''), IFNULL(position, ''))",
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
    'CREATE INDEX IF NOT EXISTS idx_photos_panel ON photos (sessionId, panelName, panelRowId)',
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
