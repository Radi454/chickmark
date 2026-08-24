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
    createdBy TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS flocks (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    flockId TEXT,
    breed TEXT,
    entryDate TEXT,
    farmId TEXT,
    sectorKey TEXT,
    sexProfile TEXT NOT NULL DEFAULT 'as_hatched',
    targetProfileId TEXT,
    productionPhase TEXT,
    isAgeEstimated INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active',
    depletionAgeWeeks INTEGER NOT NULL DEFAULT 65,
    soldAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
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
    sourceUrl TEXT,
    sourcePhotoPath TEXT,
    sourcePhotoRemotePath TEXT,
    notes TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
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
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
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
  // v61: what this row represents, recorded explicitly instead of being
  // re-inferred from the hierarchy columns on reopen.
  'sampleMode TEXT',
  'scopeType TEXT',
  'sampleLabel TEXT',
  'sampleIndex INTEGER',
  // v61: which side of the operation owns the measurement, the fix, and the
  // recommendation. Free text so the vocabulary can grow without a migration.
  'sourceDomain TEXT',
  'actionDomain TEXT',
  'recommendationTarget TEXT',
];

Future<void> ensurePanelSampleSchemaColumns(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    final columns = _columnNames(
      await db.rawQuery('PRAGMA table_info(${panel.tableName})'),
    );
    for (final columnDefinition in [
      ...panel.hierarchyColumnDefinitions,
      ..._panelContextColumnDefinitions,
      ...panel.identityColumnDefinitions,
      ...panel.qualityColumnDefinitions,
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

Future<void> _ensurePanelQueryIndexes(DatabaseExecutor db) async {
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    await _createPanelQueryIndexesIfSupported(db, panel);
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
    if (PanelSampleSchema.idKeyedPanelTables.contains(panel.tableName)) {
      // Pre-v61 databases carry this index; it is what made two comparison
      // rows with a blank or duplicate house collide.
      await db.execute(
        'DROP INDEX IF EXISTS idx_${panel.tableName}_unique_row',
      );
      continue;
    }
    final columns = _columnNames(
      await db.rawQuery('PRAGMA table_info(${panel.tableName})'),
    );
    if (!columns.containsAll({'sessionId', ...panel.hierarchyColumnNames})) {
      continue;
    }
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

Future<void> _ensureColumns(
  DatabaseExecutor db,
  String table,
  List<String> definitions,
) async {
  final existing = _columnNames(await db.rawQuery('PRAGMA table_info($table)'));
  for (final definition in definitions) {
    final name = _columnNameFromDefinition(definition);
    if (existing.contains(name)) continue;
    await db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }
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
  final identityColumns = panel.identityColumnDefinitions.isEmpty
      ? ''
      : ',\n    ${panel.identityColumnDefinitions.join(',\n    ')}';
  final qualityColumns = panel.qualityColumnDefinitions.isEmpty
      ? ''
      : ',\n    ${panel.qualityColumnDefinitions.join(',\n    ')}';
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
    ${_panelContextColumnDefinitions.join(',\n    ')}$identityColumns$qualityColumns,
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
  await _createPanelQueryIndexesIfSupported(db, panel);

  final columns = _columnNames(
    await db.rawQuery('PRAGMA table_info($tableName)'),
  );
  final uniqueIndexColumns = {'sessionId', ...panel.hierarchyColumnNames};
  if (!PanelSampleSchema.idKeyedPanelTables.contains(tableName) &&
      columns.containsAll(uniqueIndexColumns)) {
    await db.execute(_panelUniqueRowIndexSql(panel));
  }
}

Future<void> _createPanelQueryIndexesIfSupported(
  DatabaseExecutor db,
  PanelSampleDefinition panel,
) async {
  final tableName = panel.tableName;
  final columns = _columnNames(
    await db.rawQuery('PRAGMA table_info($tableName)'),
  );
  if (columns.contains('sessionId')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_session ON $tableName (sessionId)',
    );
  }
  if (columns.containsAll({'customerId', 'flockId', 'date'})) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_dashboard ON $tableName (customerId, flockId, date)',
    );
  }
  if (columns.contains('syncStatus')) {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_sync ON $tableName (syncStatus)',
    );
  }
  if (columns.containsAll({'customerId', 'sampleKey'})) {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tableName}_sample_key '
      'ON $tableName (customerId, sampleKey) WHERE sampleKey IS NOT NULL',
    );
  }
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

Future<void> _createDashboardActionTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS dashboard_actions (
    id TEXT PRIMARY KEY,
    findingKey TEXT NOT NULL,
    customerId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    flockId TEXT,
    sessionId TEXT,
    panelName TEXT,
    panelRowId TEXT,
    fieldKey TEXT,
    metricKey TEXT,
    title TEXT NOT NULL,
    description TEXT,
    priority TEXT NOT NULL DEFAULT 'watch',
    status TEXT NOT NULL DEFAULT 'open',
    ownerId TEXT,
    ownerName TEXT,
    dueAt TEXT,
    firstObservedAt TEXT,
    lastObservedAt TEXT,
    resolvedAt TEXT,
    resolutionNotes TEXT,
    resolutionPhotoId TEXT,
    recurrenceOfId TEXT,
    createdBy TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE SET NULL,
    FOREIGN KEY (sessionId) REFERENCES audit_sessions(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_dashboard_actions_scope ON dashboard_actions (customerId, hatcheryId, flockId, status, updatedAt DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_dashboard_actions_finding ON dashboard_actions (findingKey, updatedAt DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_dashboard_actions_sync ON dashboard_actions (syncStatus, dirtyAt)',
  );
}

Future<void> createEggGradingTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_defect_types (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    isReject INTEGER NOT NULL DEFAULT 1,
    description TEXT,
    imageAsset TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    isActive INTEGER NOT NULL DEFAULT 1,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS egg_quality_defect_counts (
    id TEXT PRIMARY KEY,
    eggQualityId TEXT NOT NULL,
    sessionId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT,
    hatcheryId TEXT,
    date TEXT NOT NULL,
    scopeType TEXT,
    houseKey TEXT,
    sampleLabel TEXT,
    defectCode TEXT NOT NULL,
    defectCategory TEXT,
    isReject INTEGER,
    count INTEGER NOT NULL DEFAULT 0,
    pctOfSample REAL,
    notes TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (eggQualityId) REFERENCES egg_quality(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_eqdc_unique_defect '
    'ON egg_quality_defect_counts (eggQualityId, defectCode)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_eqdc_parent '
    'ON egg_quality_defect_counts (eggQualityId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_eqdc_dashboard '
    'ON egg_quality_defect_counts (customerId, flockId, date, defectCode)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_eqdc_sync '
    'ON egg_quality_defect_counts (syncStatus, dirtyAt)',
  );
}

Future<void> _createLabAnalysisTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS lab_analysis_reports (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    reportDate TEXT NOT NULL,
    receivedDate TEXT,
    labName TEXT NOT NULL DEFAULT '',
    sampleType TEXT NOT NULL DEFAULT '',
    flockAgeWeeks INTEGER,
    title TEXT,
    notes TEXT,
    reportFileName TEXT,
    reportFilePath TEXT,
    reportFileRemotePath TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_reports_scope ON lab_analysis_reports (customerId, flockId, reportDate DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_reports_sync ON lab_analysis_reports (syncStatus, dirtyAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS lab_analysis_groups (
    id TEXT PRIMARY KEY,
    reportId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    reportDate TEXT NOT NULL,
    testType TEXT NOT NULL,
    groupLabel TEXT NOT NULL DEFAULT '',
    sampleScope TEXT NOT NULL DEFAULT '',
    analyte TEXT NOT NULL DEFAULT '',
    method TEXT NOT NULL DEFAULT '',
    kitName TEXT NOT NULL DEFAULT '',
    productCode TEXT NOT NULL DEFAULT '',
    antigen TEXT NOT NULL DEFAULT '',
    sampleCount INTEGER,
    meanTiter REAL,
    minTiter REAL,
    maxTiter REAL,
    gmtTiter REAL,
    cvPct REAL,
    positiveCount INTEGER,
    negativeCount INTEGER,
    positivePct REAL,
    cutoffValue REAL,
    cutoffTiter REAL,
    gmLog2 REAL,
    protectiveThresholdLog2 REAL,
    protectiveCount INTEGER,
    protectivePct REAL,
    interpretation TEXT NOT NULL DEFAULT '',
    severity TEXT NOT NULL DEFAULT 'normal',
    notes TEXT,
    sortOrder INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (reportId) REFERENCES lab_analysis_reports(id) ON DELETE CASCADE,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_groups_report ON lab_analysis_groups (reportId, sortOrder)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_groups_dashboard ON lab_analysis_groups (customerId, flockId, reportDate DESC, testType)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_groups_sync ON lab_analysis_groups (syncStatus, dirtyAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS lab_analysis_rows (
    id TEXT PRIMARY KEY,
    groupId TEXT NOT NULL,
    reportId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    reportDate TEXT NOT NULL,
    testType TEXT NOT NULL,
    rowLabel TEXT NOT NULL DEFAULT '',
    analyte TEXT NOT NULL DEFAULT '',
    result TEXT NOT NULL DEFAULT '',
    resultCategory TEXT NOT NULL DEFAULT '',
    numericValue REAL,
    unit TEXT NOT NULL DEFAULT '',
    ctValue REAL,
    odValue REAL,
    spRatio REAL,
    titer REAL,
    titerGroup INTEGER,
    hiLog2 INTEGER,
    count INTEGER,
    antibiotic TEXT NOT NULL DEFAULT '',
    sensitivityCategory TEXT NOT NULL DEFAULT '',
    interpretation TEXT NOT NULL DEFAULT '',
    severity TEXT NOT NULL DEFAULT 'normal',
    sortOrder INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (groupId) REFERENCES lab_analysis_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (reportId) REFERENCES lab_analysis_reports(id) ON DELETE CASCADE,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_rows_group ON lab_analysis_rows (groupId, sortOrder)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_rows_dashboard ON lab_analysis_rows (customerId, flockId, reportDate DESC, testType)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_lab_rows_sync ON lab_analysis_rows (syncStatus, dirtyAt)',
  );
}

Future<void> _createPerformanceMonitoringTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS customer_sectors (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    sectorKey TEXT NOT NULL CHECK (sectorKey IN ('breeder', 'broiler', 'layer')),
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_sectors_unique '
    'ON customer_sectors (customerId, sectorKey)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS farms (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    sectorKey TEXT NOT NULL CHECK (sectorKey IN ('breeder', 'broiler', 'layer')),
    name TEXT NOT NULL,
    location TEXT,
    notes TEXT,
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_farms_customer_sector '
    'ON farms (customerId, sectorKey, isActive, name)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS houses (
    id TEXT PRIMARY KEY,
    farmId TEXT NOT NULL,
    name TEXT NOT NULL,
    code TEXT,
    capacity INTEGER,
    notes TEXT,
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (farmId) REFERENCES farms(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_houses_farm_name '
    'ON houses (farmId, name)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_houses_farm_code '
    'ON houses (farmId, code) WHERE code IS NOT NULL AND code <> \'\'',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS flock_placements (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    houseId TEXT NOT NULL,
    placedBirds INTEGER NOT NULL CHECK (placedBirds > 0),
    placedAt TEXT NOT NULL,
    endedAt TEXT,
    status TEXT NOT NULL DEFAULT 'active'
      CHECK (status IN ('active', 'ended', 'transferred')),
    notes TEXT,
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_flock_placements_flock '
    'ON flock_placements (flockId, status, placedAt)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_active_placement_per_house '
    'ON flock_placements (houseId) '
    "WHERE status = 'active' AND endedAt IS NULL",
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS broiler_daily_records (
    id TEXT PRIMARY KEY,
    placementId TEXT NOT NULL,
    recordDate TEXT NOT NULL,
    currentRevisionId TEXT,
    verificationStatus TEXT NOT NULL DEFAULT 'pending_entry'
      CHECK (verificationStatus IN (
        'pending_entry', 'entered', 'reviewed', 'verified',
        'requires_clarification', 'corrected'
      )),
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (placementId) REFERENCES flock_placements(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    'idx_broiler_daily_records_placement_date '
    'ON broiler_daily_records (placementId, recordDate)',
  );

  await db.execute(
    '''CREATE TABLE IF NOT EXISTS broiler_daily_record_revisions (
    id TEXT PRIMARY KEY,
    recordId TEXT NOT NULL,
    revisionNumber INTEGER NOT NULL CHECK (revisionNumber > 0),
    verificationStatus TEXT NOT NULL
      CHECK (verificationStatus IN (
        'pending_entry', 'entered', 'reviewed', 'verified',
        'requires_clarification', 'corrected'
      )),
    dataSourceType TEXT NOT NULL DEFAULT 'manual',
    sourceDescription TEXT,
    reportedBy TEXT,
    enteredBy TEXT NOT NULL,
    enteredAt TEXT NOT NULL,
    reviewedBy TEXT,
    reviewedAt TEXT,
    verifiedBy TEXT,
    verifiedAt TEXT,
    correctionReason TEXT,
    openingBirdCount INTEGER,
    dailyMortality INTEGER,
    dailyCulls INTEGER,
    transfersIn INTEGER,
    transfersOut INTEGER,
    partialDepletion INTEGER,
    otherPopulationAdjustment INTEGER,
    mortalityCausesJson TEXT,
    closingLiveBirdCount INTEGER,
    dailyFeedConsumedKg REAL,
    feedType TEXT,
    feedPhase TEXT,
    feedChange TEXT,
    feedInterruptionMinutes INTEGER,
    feedShortage INTEGER CHECK (feedShortage IN (0, 1)),
    waterConsumedLiters REAL,
    flushingWaterLiters REAL,
    waterInterruptionMinutes INTEGER,
    waterMedication TEXT,
    waterVaccination TEXT,
    averageBodyWeightG REAL,
    birdsWeighed INTEGER,
    uniformityPct REAL,
    cvPct REAL,
    individualWeightsJson TEXT,
    minTemperatureC REAL,
    maxTemperatureC REAL,
    averageTemperatureC REAL,
    relativeHumidityPct REAL,
    co2Ppm REAL,
    ammoniaPpm REAL,
    environmentIncident TEXT,
    clinicalSigns TEXT,
    treatmentStarted TEXT,
    treatmentStopped TEXT,
    vaccination TEXT,
    powerFailure INTEGER CHECK (powerFailure IN (0, 1)),
    equipmentFailure TEXT,
    veterinaryObservation TEXT,
    notes TEXT,
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (recordId, revisionNumber),
    FOREIGN KEY (recordId) REFERENCES broiler_daily_records(id) ON DELETE CASCADE
  )''',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_broiler_daily_revisions_record '
    'ON broiler_daily_record_revisions (recordId, revisionNumber DESC)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS daily_record_sources (
    id TEXT PRIMARY KEY,
    revisionId TEXT NOT NULL,
    sourceKind TEXT NOT NULL,
    localPath TEXT,
    remoteStoragePath TEXT,
    originalFilename TEXT,
    checksum TEXT,
    uploadState TEXT NOT NULL DEFAULT 'local',
    uploadError TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (revisionId)
      REFERENCES broiler_daily_record_revisions(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_daily_record_sources_revision '
    'ON daily_record_sources (revisionId, createdAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS broiler_daily_events (
    id TEXT PRIMARY KEY,
    revisionId TEXT NOT NULL,
    eventType TEXT NOT NULL,
    eventAt TEXT,
    isAllDay INTEGER NOT NULL DEFAULT 1 CHECK (isAllDay IN (0, 1)),
    eventState TEXT,
    description TEXT,
    treatment TEXT,
    vaccination TEXT,
    feedPhase TEXT,
    equipment TEXT,
    createdAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (revisionId)
      REFERENCES broiler_daily_record_revisions(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_broiler_daily_events_revision '
    'ON broiler_daily_events (revisionId, eventAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS broiler_target_profiles (
    id TEXT PRIMARY KEY,
    brand TEXT NOT NULL,
    breed TEXT NOT NULL,
    featheringVariant TEXT,
    sexProfile TEXT NOT NULL
      CHECK (sexProfile IN ('as_hatched', 'male', 'female')),
    publicationVersion TEXT NOT NULL,
    publicationDate TEXT,
    sourceTitle TEXT NOT NULL,
    sourceUrl TEXT NOT NULL,
    sourceFilePath TEXT,
    region TEXT,
    languageCode TEXT NOT NULL DEFAULT 'en',
    activeFrom TEXT,
    activeTo TEXT,
    isOfficial INTEGER NOT NULL DEFAULT 0 CHECK (isOfficial IN (0, 1)),
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    supersedesProfileId TEXT,
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (supersedesProfileId)
      REFERENCES broiler_target_profiles(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_broiler_target_profiles_lookup '
    'ON broiler_target_profiles '
    '(brand, breed, sexProfile, isActive, publicationVersion)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS broiler_target_rows (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    ageDay INTEGER NOT NULL CHECK (ageDay >= 0),
    bodyWeightG REAL,
    dailyGainG REAL,
    averageDailyGainG REAL,
    dailyFeedIntakeGPerLivingBird REAL,
    cumulativeFeedIntakeGPerLivingBird REAL,
    fcr REAL,
    waterMlPerLivingBird REAL,
    metricMethodNotes TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (profileId)
      REFERENCES broiler_target_profiles(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_broiler_target_rows_profile_age '
    'ON broiler_target_rows (profileId, ageDay)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS performance_alert_rules (
    id TEXT PRIMARY KEY,
    metricKey TEXT NOT NULL,
    scopeLevel TEXT NOT NULL CHECK (scopeLevel IN ('global', 'customer')),
    customerId TEXT,
    watchThreshold REAL,
    criticalThreshold REAL,
    lowerThreshold REAL,
    upperThreshold REAL,
    direction TEXT NOT NULL
      CHECK (direction IN ('above', 'below', 'outside_range', 'rate_of_change')),
    persistenceWindow INTEGER NOT NULL DEFAULT 1,
    minimumValidObservations INTEGER NOT NULL DEFAULT 1,
    source TEXT NOT NULL,
    rationale TEXT,
    isEnabled INTEGER NOT NULL DEFAULT 1 CHECK (isEnabled IN (0, 1)),
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_performance_alert_rules_scope '
    'ON performance_alert_rules (metricKey, scopeLevel, customerId)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS performance_concerns (
    id TEXT PRIMARY KEY,
    ruleId TEXT,
    customerId TEXT NOT NULL,
    farmId TEXT,
    flockId TEXT,
    placementId TEXT,
    houseId TEXT,
    metricKey TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('watch', 'critical')),
    firstObservedAt TEXT NOT NULL,
    lastObservedAt TEXT NOT NULL,
    evidenceWindowStart TEXT,
    evidenceWindowEnd TEXT,
    baselineValue REAL,
    targetValue REAL,
    actualValue REAL,
    evidenceJson TEXT,
    status TEXT NOT NULL DEFAULT 'open'
      CHECK (status IN (
        'open', 'monitoring', 'assigned_to_visit', 'resolved', 'dismissed'
      )),
    resolvedAt TEXT,
    resolvedBy TEXT,
    resolutionNotes TEXT,
    dismissedAt TEXT,
    dismissedBy TEXT,
    dismissalReason TEXT,
    recurrenceOfId TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (ruleId) REFERENCES performance_alert_rules(id) ON DELETE SET NULL,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (farmId) REFERENCES farms(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (placementId) REFERENCES flock_placements(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id) ON DELETE CASCADE,
    FOREIGN KEY (recurrenceOfId)
      REFERENCES performance_concerns(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_performance_concerns_scope '
    'ON performance_concerns '
    '(customerId, farmId, flockId, placementId, metricKey, status, updatedAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS farm_visit_sessions (
    id TEXT PRIMARY KEY,
    customerId TEXT NOT NULL,
    farmId TEXT NOT NULL,
    flockId TEXT,
    visitDate TEXT NOT NULL,
    briefingSnapshotJson TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'planned'
      CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
    assignedAuditorId TEXT,
    startedAt TEXT,
    completedAt TEXT,
    notes TEXT,
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (farmId) REFERENCES farms(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_farm_visit_sessions_scope '
    'ON farm_visit_sessions (customerId, farmId, flockId, visitDate DESC)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS farm_visit_houses (
    id TEXT PRIMARY KEY,
    visitId TEXT NOT NULL,
    houseId TEXT NOT NULL,
    createdAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (visitId, houseId),
    FOREIGN KEY (visitId) REFERENCES farm_visit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS visit_investigations (
    id TEXT PRIMARY KEY,
    visitId TEXT NOT NULL,
    sourceConcernId TEXT,
    houseId TEXT,
    location TEXT,
    origin TEXT NOT NULL DEFAULT 'suggested',
    investigationType TEXT NOT NULL,
    instruction TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending', 'in_progress', 'completed', 'not_applicable')),
    resultSummary TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (visitId) REFERENCES farm_visit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (sourceConcernId)
      REFERENCES performance_concerns(id) ON DELETE SET NULL,
    FOREIGN KEY (houseId) REFERENCES houses(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_visit_investigations_visit '
    'ON visit_investigations (visitId, status)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS visit_findings (
    id TEXT PRIMARY KEY,
    visitId TEXT NOT NULL,
    investigationId TEXT,
    findingType TEXT NOT NULL,
    severity TEXT,
    measuredValue REAL,
    unit TEXT,
    observationJson TEXT,
    houseId TEXT,
    location TEXT,
    staffExplanation TEXT,
    attachmentRefsJson TEXT,
    authoredBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (visitId) REFERENCES farm_visit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (investigationId)
      REFERENCES visit_investigations(id) ON DELETE SET NULL,
    FOREIGN KEY (houseId) REFERENCES houses(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_visit_findings_visit '
    'ON visit_findings (visitId, investigationId, createdAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS cause_assessments (
    id TEXT PRIMARY KEY,
    visitId TEXT NOT NULL,
    concernId TEXT NOT NULL,
    probableCause TEXT NOT NULL,
    alternativeCausesJson TEXT,
    supportingEvidenceJson TEXT,
    conflictingEvidenceJson TEXT,
    status TEXT NOT NULL DEFAULT 'suspected'
      CHECK (status IN ('suspected', 'probable', 'confirmed', 'ruled_out')),
    authoredBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (visitId) REFERENCES farm_visit_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (concernId)
      REFERENCES performance_concerns(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_cause_assessments_visit_concern '
    'ON cause_assessments (visitId, concernId, status)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS corrective_actions (
    id TEXT PRIMARY KEY,
    concernId TEXT NOT NULL,
    visitId TEXT,
    causeAssessmentId TEXT,
    instruction TEXT NOT NULL,
    ownerId TEXT,
    ownerName TEXT,
    dueAt TEXT,
    implementedAt TEXT,
    implementationConfirmedBy TEXT,
    status TEXT NOT NULL DEFAULT 'open'
      CHECK (status IN (
        'open', 'in_progress', 'implemented', 'completed', 'cancelled'
      )),
    completionNotes TEXT,
    evidenceRefsJson TEXT,
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (concernId)
      REFERENCES performance_concerns(id) ON DELETE CASCADE,
    FOREIGN KEY (visitId) REFERENCES farm_visit_sessions(id) ON DELETE SET NULL,
    FOREIGN KEY (causeAssessmentId)
      REFERENCES cause_assessments(id) ON DELETE SET NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_corrective_actions_concern_status '
    'ON corrective_actions (concernId, status, dueAt)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS action_kpi_evaluations (
    id TEXT PRIMARY KEY,
    actionId TEXT NOT NULL,
    kpiKey TEXT NOT NULL,
    scopeJson TEXT NOT NULL DEFAULT '{}',
    baselineWindowStart TEXT,
    baselineWindowEnd TEXT,
    baselineValue REAL,
    targetRule TEXT,
    targetValue REAL,
    evaluationStart TEXT NOT NULL,
    evaluationEnd TEXT NOT NULL,
    observedValue REAL,
    effectiveness TEXT NOT NULL DEFAULT 'not_evaluated'
      CHECK (effectiveness IN (
        'effective', 'partially_effective', 'ineffective', 'not_evaluated'
      )),
    evaluationReason TEXT,
    evaluatedBy TEXT,
    evaluatedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (actionId) REFERENCES corrective_actions(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_action_kpi_evaluations_action '
    'ON action_kpi_evaluations (actionId, kpiKey, evaluationEnd)',
  );
}

/// A staff link identifies one person on one channel. Telegram links carry a
/// `telegramUserId`; in-app links carry an `appUserId` and no Telegram
/// identity at all, so neither column can be NOT NULL. Uniqueness is enforced
/// per channel by partial indexes instead of column constraints — a column
/// UNIQUE would collide across every app link once a second one exists.
Future<void> _createTelegramStaffLinksTable(
  DatabaseExecutor db, {
  String tableName = 'telegram_staff_links',
}) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    telegramUserId TEXT,
    telegramChatId TEXT,
    displayName TEXT,
    username TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    accessRole TEXT NOT NULL DEFAULT 'customer'
      CHECK (accessRole IN ('customer', 'admin')),
    customerId TEXT,
    invitedBy TEXT,
    channel TEXT NOT NULL DEFAULT 'telegram',
    appUserId TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK (
      status <> 'allowed'
      OR (accessRole = 'customer' AND customerId IS NOT NULL)
      OR (accessRole = 'admin' AND customerId IS NULL)
    ),
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE RESTRICT
  )''');
}

/// Legacy databases reach `onOpen` before their `channel`/`appUserId` columns
/// exist (surgical repair adds them in the same pass), so index creation is
/// skipped until the columns are present rather than throwing.
Future<void> _ensureTelegramStaffLinkIndexes(DatabaseExecutor db) async {
  if (!await _tableExists(db, 'telegram_staff_links')) return;
  final columns = _columnNames(
    await db.rawQuery('PRAGMA table_info(telegram_staff_links)'),
  );
  if (!columns.containsAll({'telegramUserId', 'appUserId'})) return;
  await _createTelegramStaffLinkIndexes(db);
}

Future<void> _createTelegramStaffLinkIndexes(DatabaseExecutor db) async {
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    'idx_telegram_staff_links_telegram_user '
    'ON telegram_staff_links (telegramUserId) '
    'WHERE telegramUserId IS NOT NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_telegram_staff_links_app_user '
    'ON telegram_staff_links (appUserId) WHERE appUserId IS NOT NULL',
  );
}

Future<void> _createHatcheryAgentTables(DatabaseExecutor db) async {
  await _createTelegramStaffLinksTable(db);

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    telegramEnabled INTEGER NOT NULL DEFAULT 1,
    hatchabilityWarningThresholdPoints REAL NOT NULL DEFAULT 3.0,
    minimumReadyConfidencePct REAL NOT NULL DEFAULT 85.0,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_submissions (
    id TEXT PRIMARY KEY,
    telegramUpdateId TEXT UNIQUE,
    telegramMessageId TEXT,
    telegramChatId TEXT,
    telegramUserId TEXT,
    staffLinkId TEXT,
    sourceKind TEXT NOT NULL,
    sourceText TEXT,
    sourceFileName TEXT,
    sourceMimeType TEXT,
    sourceRemotePath TEXT,
    status TEXT NOT NULL,
    errorMessage TEXT,
    submittedAt TEXT NOT NULL,
    processedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (staffLinkId) REFERENCES telegram_staff_links(id) ON DELETE SET NULL
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_questions (
    id TEXT PRIMARY KEY,
    submissionId TEXT NOT NULL,
    rowOrdinal INTEGER,
    fieldKey TEXT NOT NULL,
    questionTextEn TEXT NOT NULL,
    questionTextAr TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    answerText TEXT,
    answeredAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (submissionId) REFERENCES agent_submissions(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_draft_batches (
    id TEXT PRIMARY KEY,
    submissionId TEXT NOT NULL,
    status TEXT NOT NULL,
    sourceSummary TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (submissionId) REFERENCES agent_submissions(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_draft_rows (
    id TEXT PRIMARY KEY,
    batchId TEXT NOT NULL,
    rowOrdinal INTEGER NOT NULL,
    status TEXT NOT NULL,
    customerId TEXT,
    customerName TEXT,
    flockId TEXT,
    flockName TEXT,
    hatcheryId TEXT,
    stationName TEXT,
    breed TEXT,
    eggsPlaced INTEGER,
    productionDate TEXT,
    placementDate TEXT,
    eggWeightG REAL,
    fertilityPct REAL,
    transferWeightG REAL,
    setterNumber TEXT,
    hatcherNumber TEXT,
    hatchDate TEXT,
    healthyChicks INTEGER,
    secondGradeChicks INTEGER,
    condemnedChicks INTEGER,
    totalProduction INTEGER,
    hatchabilityPct REAL,
    confidencePct REAL,
    extractionJson TEXT,
    warningsJson TEXT,
    proposedFlockAgeWeeks INTEGER,
    approvedRecordId TEXT,
    reviewedBy TEXT,
    reviewedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (batchId) REFERENCES hatchery_draft_batches(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_agent_audit_events (
    id TEXT PRIMARY KEY,
    submissionId TEXT NOT NULL,
    rowId TEXT,
    actorType TEXT NOT NULL,
    actorId TEXT,
    eventType TEXT NOT NULL,
    detailsJson TEXT,
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (submissionId) REFERENCES agent_submissions(id) ON DELETE CASCADE,
    FOREIGN KEY (rowId) REFERENCES hatchery_draft_rows(id) ON DELETE SET NULL
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS hatchery_daily_records (
    id TEXT PRIMARY KEY,
    sourceDraftRowId TEXT,
    customerId TEXT NOT NULL,
    flockId TEXT NOT NULL,
    hatcheryId TEXT,
    stationName TEXT NOT NULL,
    breed TEXT NOT NULL,
    eggsPlaced INTEGER NOT NULL,
    productionDate TEXT,
    placementDate TEXT,
    eggWeightG REAL,
    fertilityPct REAL,
    transferWeightG REAL,
    setterNumber TEXT,
    hatcherNumber TEXT,
    hatchDate TEXT NOT NULL,
    healthyChicks INTEGER,
    secondGradeChicks INTEGER,
    condemnedChicks INTEGER,
    totalProduction INTEGER NOT NULL,
    hatchabilityPct REAL NOT NULL,
    approvedBy TEXT,
    approvedAt TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (sourceDraftRowId) REFERENCES hatchery_draft_rows(id) ON DELETE SET NULL,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE SET NULL
  )''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_submissions_status '
    'ON agent_submissions (status, submittedAt DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_questions_submission '
    'ON agent_questions (submissionId, status)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_hatchery_draft_rows_batch '
    'ON hatchery_draft_rows (batchId, rowOrdinal)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_hatchery_daily_records_comparable '
    'ON hatchery_daily_records '
    '(customerId, flockId, stationName, breed, hatchDate DESC)',
  );
}

Future<void> _createAgentIntakeTables(DatabaseExecutor db) async {
  await _createAgentIntakeSessionsTable(db, 'agent_intake_sessions');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_intake_turns (
    id TEXT PRIMARY KEY,
    intakeSessionId TEXT NOT NULL,
    direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    telegramUpdateId TEXT UNIQUE,
    telegramMessageId TEXT,
    text TEXT NOT NULL,
    language TEXT NOT NULL CHECK (language IN ('en', 'ar', 'mixed')),
    intent TEXT,
    deliveryStatus TEXT,
    attachmentKind TEXT,
    attachmentFileName TEXT,
    attachmentMimeType TEXT,
    attachmentRemotePath TEXT,
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (intakeSessionId)
      REFERENCES agent_intake_sessions(id) ON DELETE CASCADE
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_intake_values (
    id TEXT PRIMARY KEY,
    intakeSessionId TEXT NOT NULL,
    fieldKey TEXT NOT NULL,
    valueJson TEXT NOT NULL,
    sourcePhrase TEXT NOT NULL,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    clarificationReason TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (intakeSessionId, fieldKey),
    FOREIGN KEY (intakeSessionId)
      REFERENCES agent_intake_sessions(id) ON DELETE CASCADE
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_intake_sessions_active '
    'ON agent_intake_sessions (staffLinkId, telegramChatId) '
    "WHERE state IN ('collecting', 'awaiting_clarification', 'paused', "
    "'ready_for_summary', 'awaiting_user_confirmation')",
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_intake_sessions_review '
    'ON agent_intake_sessions (state, updatedAt DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_intake_turns_session '
    'ON agent_intake_turns (intakeSessionId, createdAt, id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_intake_values_session '
    'ON agent_intake_values (intakeSessionId, fieldKey)',
  );
}

Future<void> _createAgentIntakeSessionsTable(
  DatabaseExecutor db,
  String tableName,
) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    staffLinkId TEXT NOT NULL,
    telegramChatId TEXT NOT NULL,
    schemaKey TEXT NOT NULL,
    schemaVersion INTEGER NOT NULL,
    state TEXT NOT NULL CHECK (state IN (
      'collecting',
      'awaiting_clarification',
      'paused',
      'ready_for_summary',
      'awaiting_user_confirmation',
      'awaiting_admin_review',
      'approved',
      'rejected',
      'cancelled'
    )),
    language TEXT NOT NULL CHECK (language IN ('en', 'ar', 'mixed')),
    customerId TEXT,
    customerName TEXT,
    flockId TEXT,
    flockName TEXT,
    hatcheryId TEXT,
    hatcheryName TEXT,
    auditDate TEXT NOT NULL,
    scope TEXT CHECK (scope IS NULL OR scope IN (
      'pool',
      'house',
      'setter',
      'hatcher',
      'setter_hatcher',
      'trolley',
      'tray'
    )),
    setterIdentity TEXT,
    hatcherIdentity TEXT,
    workingValuesJson TEXT NOT NULL DEFAULT '{}',
    pendingClarificationJson TEXT,
    summaryVersion INTEGER NOT NULL DEFAULT 0,
    summarySnapshotJson TEXT,
    userConfirmedAt TEXT,
    visitId TEXT,
    rowVersion INTEGER NOT NULL DEFAULT 1 CHECK (rowVersion >= 1),
    lastToolEventId TEXT,
    approvedSessionId TEXT,
    approvedPanelRowId TEXT,
    reviewedBy TEXT,
    reviewedAt TEXT,
    rejectionReason TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (staffLinkId)
      REFERENCES telegram_staff_links(id) ON DELETE CASCADE,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE SET NULL,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE SET NULL,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE SET NULL,
    FOREIGN KEY (visitId)
      REFERENCES agent_intake_visits(id) ON DELETE SET NULL,
    FOREIGN KEY (lastToolEventId)
      REFERENCES agent_tool_events(id) ON DELETE SET NULL,
    FOREIGN KEY (approvedSessionId)
      REFERENCES audit_sessions(id) ON DELETE SET NULL
  )''');
}

Future<void> _createUnifiedAgentHarnessTables(
  DatabaseExecutor db, {
  bool createGuards = true,
}) async {
  await _createAgentConversationsTable(db);
  await _createAgentConversationTurnsTable(db);
  await _createAgentToolEventsTable(db);

  await db.execute('''CREATE TABLE IF NOT EXISTS agent_intake_visits (
    id TEXT PRIMARY KEY,
    conversationId TEXT NOT NULL,
    customerId TEXT,
    flockId TEXT,
    hatcheryId TEXT,
    auditDate TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN (
      'selecting_station',
      'collecting',
      'awaiting_admin_review',
      'completed',
      'cancelled'
    )),
    approvedSessionId TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (conversationId)
      REFERENCES agent_conversations(id) ON DELETE CASCADE,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE RESTRICT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE RESTRICT,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id) ON DELETE RESTRICT,
    FOREIGN KEY (approvedSessionId)
      REFERENCES audit_sessions(id) ON DELETE SET NULL
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_conversations_staff_chat '
    'ON agent_conversations (staffLinkId, telegramChatId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_conversation_turns_conversation '
    'ON agent_conversation_turns (conversationId, createdAt, id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_conversation_turns_order '
    'ON agent_conversation_turns '
    '(conversationId, contextEpoch, direction, turnIndex) '
    'WHERE turnIndex IS NOT NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_tool_events_turn '
    'ON agent_tool_events (conversationTurnId, createdAt, id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tool_events_sequence '
    'ON agent_tool_events (conversationTurnId, toolSequence) '
    'WHERE toolSequence IS NOT NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_intake_visits_conversation '
    'ON agent_intake_visits (conversationId, createdAt, id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_intake_visits_customer '
    'ON agent_intake_visits (customerId, auditDate) '
    'WHERE customerId IS NOT NULL',
  );
  await db.execute('DROP INDEX IF EXISTS idx_agent_intake_sessions_active');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    'idx_agent_intake_sessions_active_conversation '
    'ON agent_intake_sessions (visitId) '
    'WHERE visitId IS NOT NULL AND state IN ('
    "'collecting', 'awaiting_clarification', 'paused', "
    "'ready_for_summary', 'awaiting_user_confirmation')",
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_intake_sessions_visit '
    'ON agent_intake_sessions (visitId, createdAt, id) '
    'WHERE visitId IS NOT NULL',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_telegram_staff_links_customer '
    'ON telegram_staff_links (customerId) WHERE customerId IS NOT NULL',
  );
  // Guarded: legacy databases reach this point before the v59 rebuild gives
  // them the columns these indexes cover.
  await _ensureTelegramStaffLinkIndexes(db);

  if (createGuards) await _createUnifiedAgentHarnessGuards(db);
}

Future<void> _createAgentConversationsTable(
  DatabaseExecutor db, {
  String tableName = 'agent_conversations',
}) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    staffLinkId TEXT NOT NULL,
    telegramChatId TEXT NOT NULL,
    stateVersion INTEGER NOT NULL DEFAULT 1 CHECK (stateVersion >= 1),
    contextEpoch INTEGER NOT NULL DEFAULT 1 CHECK (contextEpoch >= 1),
    selectedCustomerId TEXT,
    selectedFlockId TEXT,
    selectedAuditId TEXT,
    contextUpdatedAt TEXT,
    pendingActionJson TEXT,
    activeVisitId TEXT,
    title TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (staffLinkId, telegramChatId),
    FOREIGN KEY (staffLinkId)
      REFERENCES telegram_staff_links(id) ON DELETE CASCADE,
    FOREIGN KEY (selectedCustomerId)
      REFERENCES customers(id) ON DELETE SET NULL,
    FOREIGN KEY (selectedFlockId)
      REFERENCES flocks(id) ON DELETE SET NULL,
    FOREIGN KEY (selectedAuditId)
      REFERENCES audit_sessions(id) ON DELETE SET NULL,
    FOREIGN KEY (activeVisitId)
      REFERENCES agent_intake_visits(id) ON DELETE SET NULL
  )''');
}

Future<void> _createAgentConversationTurnsTable(
  DatabaseExecutor db, {
  String tableName = 'agent_conversation_turns',
  String conversationsTable = 'agent_conversations',
}) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    conversationId TEXT NOT NULL,
    direction TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    telegramUpdateId TEXT UNIQUE,
    telegramMessageId TEXT,
    turnIndex INTEGER CHECK (turnIndex IS NULL OR turnIndex >= 1),
    contextEpoch INTEGER NOT NULL DEFAULT 1 CHECK (contextEpoch >= 1),
    text TEXT NOT NULL,
    language TEXT NOT NULL CHECK (language IN ('en', 'ar', 'mixed')),
    provider TEXT,
    model TEXT,
    providerResponseId TEXT,
    replyToTurnId TEXT,
    attachmentJson TEXT,
    deliveryStatus TEXT,
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (conversationId)
      REFERENCES $conversationsTable(id) ON DELETE CASCADE,
    FOREIGN KEY (replyToTurnId)
      REFERENCES $tableName(id) ON DELETE SET NULL
  )''');
}

Future<void> _createAgentToolEventsTable(
  DatabaseExecutor db, {
  String tableName = 'agent_tool_events',
  String turnsTable = 'agent_conversation_turns',
}) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS $tableName (
    id TEXT PRIMARY KEY,
    conversationTurnId TEXT NOT NULL,
    toolCallId TEXT NOT NULL,
    toolName TEXT NOT NULL,
    toolSequence INTEGER CHECK (toolSequence IS NULL OR toolSequence >= 1),
    argumentsJson TEXT NOT NULL DEFAULT '{}',
    resultJson TEXT,
    status TEXT NOT NULL CHECK (status IN (
      'requested', 'succeeded', 'rejected', 'failed'
    )),
    durationMs INTEGER CHECK (durationMs IS NULL OR durationMs >= 0),
    stateVersionBefore INTEGER
      CHECK (stateVersionBefore IS NULL OR stateVersionBefore >= 1),
    stateVersionAfter INTEGER
      CHECK (stateVersionAfter IS NULL OR stateVersionAfter >= 1),
    createdAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'synced',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    UNIQUE (conversationTurnId, toolCallId),
    FOREIGN KEY (conversationTurnId)
      REFERENCES $turnsTable(id) ON DELETE CASCADE
  )''');
}

Future<void> _createTelegramStaffLinkGuards(DatabaseExecutor db) async {
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_telegram_staff_links_scope_insert
    BEFORE INSERT ON telegram_staff_links
    WHEN NEW.status = 'allowed' AND NOT (
      (NEW.accessRole = 'customer' AND NEW.customerId IS NOT NULL)
      OR (NEW.accessRole = 'admin' AND NEW.customerId IS NULL)
    )
    BEGIN
      SELECT RAISE(ABORT, 'Allowed Telegram link has invalid access scope');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_telegram_staff_links_scope_update
    BEFORE UPDATE OF status, accessRole, customerId ON telegram_staff_links
    WHEN NEW.status = 'allowed' AND NOT (
      (NEW.accessRole = 'customer' AND NEW.customerId IS NOT NULL)
      OR (NEW.accessRole = 'admin' AND NEW.customerId IS NULL)
    )
    BEGIN
      SELECT RAISE(ABORT, 'Allowed Telegram link has invalid access scope');
    END
  ''');
}

Future<void> _createUnifiedAgentHarnessGuards(DatabaseExecutor db) async {
  await _createTelegramStaffLinkGuards(db);
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_agent_intake_visit_scope_insert
    BEFORE INSERT ON agent_intake_visits
    WHEN NEW.customerId IS NULL
      OR (
        NEW.flockId IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM flocks
          WHERE id = NEW.flockId AND customerId = NEW.customerId
        )
      )
      OR (
        NEW.hatcheryId IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM hatcheries
          WHERE id = NEW.hatcheryId AND customerId = NEW.customerId
        )
      )
    BEGIN
      SELECT RAISE(ABORT, 'Agent intake visit has invalid customer scope');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_agent_intake_visit_scope_update
    BEFORE UPDATE OF customerId, flockId, hatcheryId ON agent_intake_visits
    WHEN NEW.customerId IS NULL
      OR (
        NEW.flockId IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM flocks
          WHERE id = NEW.flockId AND customerId = NEW.customerId
        )
      )
      OR (
        NEW.hatcheryId IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM hatcheries
          WHERE id = NEW.hatcheryId AND customerId = NEW.customerId
        )
      )
    BEGIN
      SELECT RAISE(ABORT, 'Agent intake visit has invalid customer scope');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_agent_intake_summary_immutable
    BEFORE UPDATE ON agent_intake_sessions
    WHEN OLD.userConfirmedAt IS NOT NULL AND (
      NEW.schemaKey IS NOT OLD.schemaKey
      OR NEW.schemaVersion IS NOT OLD.schemaVersion
      OR NEW.summaryVersion IS NOT OLD.summaryVersion
      OR NEW.summarySnapshotJson IS NOT OLD.summarySnapshotJson
      OR NEW.userConfirmedAt IS NOT OLD.userConfirmedAt
    )
    BEGIN
      SELECT RAISE(ABORT, 'Confirmed intake summary evidence is immutable');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_agent_tool_events_immutable
    BEFORE UPDATE ON agent_tool_events
    BEGIN
      SELECT RAISE(ABORT, 'Tool-call evidence is immutable');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_agent_tool_events_delete_immutable
    BEFORE DELETE ON agent_tool_events
    BEGIN
      SELECT RAISE(ABORT, 'Tool-call evidence is immutable');
    END
  ''');
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
