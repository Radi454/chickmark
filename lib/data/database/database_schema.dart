part of 'database_helper.dart';

/// Core table DDL extracted from `_onCreate` so the surgical repair path can
/// re-issue idempotent CREATE TABLE IF NOT EXISTS statements without nuking
/// data. Every statement is safe to run when the table already exists.
Future<void> _createCoreTablesIfMissing(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS users (
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
  await db.execute('''CREATE TABLE IF NOT EXISTS customers (
    id TEXT PRIMARY KEY,
    name TEXT,
    location TEXT,
    phone TEXT,
    email TEXT,
    createdAt TEXT,
    createdBy TEXT
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS flocks (
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
  await db.execute('''CREATE TABLE IF NOT EXISTS bmk_breeds (
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
  await db.execute('''CREATE TABLE IF NOT EXISTS troubleshooting (
    id TEXT PRIMARY KEY,
    hatcheryCauses TEXT,
    farmFlockCauses TEXT,
    benchmarkJson TEXT,
    interpretationJson TEXT,
    sourceRefsJson TEXT
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS photos (
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
  await db.execute('''CREATE TABLE IF NOT EXISTS activity_log (
    id TEXT PRIMARY KEY,
    userId TEXT NOT NULL,
    action TEXT NOT NULL,
    entityType TEXT,
    entityId TEXT,
    details TEXT,
    timestamp TEXT NOT NULL
  )''');
}

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

Future<void> _createBmkOperationalStandardsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS bmk_operational_standards (
    id TEXT PRIMARY KEY,
    hatcheryId TEXT,
    stationKey TEXT NOT NULL,
    sectorKey TEXT NOT NULL,
    metricKey TEXT NOT NULL,
    metricLabel TEXT NOT NULL,
    unit TEXT DEFAULT '',
    minValue REAL,
    maxValue REAL,
    targetValue REAL,
    source TEXT,
    notes TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    updatedAt TEXT,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_bmk_operational_scope ON bmk_operational_standards (hatcheryId, stationKey, sectorKey, metricKey)',
  );
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
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
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
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_audit_sessions_sync ON audit_sessions (syncStatus)',
  );
}

Future<void> _createPanelSampleSchemaTables(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    await _createPanelTable(db, panel);
  }
}

const _panelContextColumnDefinitions = [
  'storagePeriodDays INTEGER',
  'bmkAgeWeeks INTEGER',
];

Future<void> _ensurePanelSampleSchemaColumns(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    final columns = _columnNames(
      await db.rawQuery('PRAGMA table_info(${panel.tableName})'),
    );
    for (final columnDefinition in [
      ...panel.hierarchyColumnDefinitions,
      ..._panelContextColumnDefinitions,
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

Future<void> _dropPanelUniqueRowIndexes(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    await db.execute('DROP INDEX IF EXISTS idx_${panel.tableName}_unique_row');
  }
}

Future<void> _ensurePanelUniqueRowIndexes(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    await db.execute(_panelUniqueRowIndexSql(panel));
  }
}

Future<void> _dropDeprecatedPanelColumns(DatabaseExecutor db) async {
  final allHierarchyColumns = kPanelHierarchyColumnDefinitions
      .map(_columnNameFromDefinition)
      .toSet();
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    final columns = _columnNames(
      await db.rawQuery('PRAGMA table_info(${panel.tableName})'),
    );
    final deprecatedColumns = {
      'bmkAgeDays',
      ...allHierarchyColumns.difference(panel.hierarchyColumnNames.toSet()),
    };
    for (final column in deprecatedColumns.intersection(columns)) {
      await db.execute('ALTER TABLE ${panel.tableName} DROP COLUMN $column');
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
  final hierarchyColumns = panel.hierarchyColumnDefinitions.join(',\n    ');
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    breed TEXT,
    flockAgeWeeks INTEGER,
    $hierarchyColumns,
    ${_panelContextColumnDefinitions.join(',\n    ')},
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
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
    'CREATE INDEX IF NOT EXISTS idx_${tableName}_sync ON $tableName (syncStatus)',
  );
  await db.execute(_panelUniqueRowIndexSql(panel));
}

String _panelUniqueRowIndexSql(PanelSampleDefinition panel) {
  final tableName = panel.tableName;
  final columns = [
    'sessionId',
    ...panel.hierarchyColumnNames.map((column) => "IFNULL($column, '')"),
  ].join(', ');
  return 'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tableName}_unique_row ON $tableName ($columns)';
}

Future<void> _createSyncConflictTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS sync_conflicts (
    id TEXT PRIMARY KEY,
    tableName TEXT NOT NULL,
    rowId TEXT NOT NULL,
    localUpdatedAt TEXT,
    remoteUpdatedAt TEXT,
    winner TEXT NOT NULL,
    detectedAt TEXT NOT NULL,
    reviewedAt TEXT,
    reviewedBy TEXT
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open ON sync_conflicts (reviewedAt, detectedAt DESC)',
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
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
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
