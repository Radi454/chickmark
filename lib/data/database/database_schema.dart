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
    observationId TEXT,
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

Future<void> _createChickQualityObservationTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS chick_quality_observation (
    id TEXT PRIMARY KEY,
    sampleId TEXT NOT NULL,
    customerId TEXT NOT NULL,
    sessionId TEXT NOT NULL,
    domain TEXT NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('series', 'tally', 'ordinal')),
    observationKey TEXT NOT NULL CHECK(length(trim(observationKey)) > 0),
    ordinal INTEGER CHECK(ordinal IS NULL OR ordinal >= 0),
    numericValue REAL,
    textValue TEXT,
    unit TEXT NOT NULL,
    qualityFlags TEXT NOT NULL DEFAULT '[]',
    source TEXT,
    observedAt TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK((numericValue IS NOT NULL) <> (textValue IS NOT NULL))
  )''');
  await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
    idx_chick_quality_observation_logical
    ON chick_quality_observation (
      sampleId, domain, kind, observationKey, COALESCE(ordinal, -1)
    )
  ''');
  await db.execute('''CREATE INDEX IF NOT EXISTS
    idx_chick_quality_observation_sample
    ON chick_quality_observation (sampleId, domain, kind, observationKey, ordinal)
  ''');
  await db.execute('''CREATE INDEX IF NOT EXISTS
    idx_chick_quality_observation_session
    ON chick_quality_observation (sessionId, customerId, domain)
  ''');
  await db.execute('''CREATE INDEX IF NOT EXISTS
    idx_chick_quality_observation_sync
    ON chick_quality_observation (syncStatus, dirtyAt)
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_chick_quality_observation_owner_insert
    BEFORE INSERT ON chick_quality_observation
    WHEN NOT EXISTS (
      SELECT 1 FROM chick_weights
      WHERE id = NEW.sampleId
        AND NEW.domain = 'chicks.weights'
        AND domain = NEW.domain
        AND customerId = NEW.customerId
        AND sessionId = NEW.sessionId
      UNION ALL
      SELECT 1 FROM chick_quality
      WHERE id = NEW.sampleId
        AND NEW.domain <> 'chicks.weights'
        AND domain = NEW.domain
        AND customerId = NEW.customerId
        AND sessionId = NEW.sessionId
    )
    BEGIN
      SELECT RAISE(ABORT, 'Chick observation owner mismatch');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_chick_quality_observation_owner_update
    BEFORE UPDATE OF sampleId, customerId, sessionId, domain
    ON chick_quality_observation
    WHEN NOT EXISTS (
      SELECT 1 FROM chick_weights
      WHERE id = NEW.sampleId
        AND NEW.domain = 'chicks.weights'
        AND domain = NEW.domain
        AND customerId = NEW.customerId
        AND sessionId = NEW.sessionId
      UNION ALL
      SELECT 1 FROM chick_quality
      WHERE id = NEW.sampleId
        AND NEW.domain <> 'chicks.weights'
        AND domain = NEW.domain
        AND customerId = NEW.customerId
        AND sessionId = NEW.sessionId
    )
    BEGIN
      SELECT RAISE(ABORT, 'Chick observation owner mismatch');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_chick_quality_observation_identity_update
    BEFORE UPDATE OF id, sampleId, domain, kind, observationKey, ordinal
    ON chick_quality_observation
    WHEN OLD.id IS NOT NEW.id
      OR OLD.sampleId IS NOT NEW.sampleId
      OR OLD.domain IS NOT NEW.domain
      OR OLD.kind IS NOT NEW.kind
      OR OLD.observationKey IS NOT NEW.observationKey
      OR OLD.ordinal IS NOT NEW.ordinal
    BEGIN
      SELECT RAISE(ABORT, 'Chick observation identity is immutable');
    END
  ''');
  if (await _tableExists(db, 'chick_quality')) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_chick_quality_observation_parent_quality_delete
      BEFORE DELETE ON chick_quality
      BEGIN
        DELETE FROM chick_quality_observation
        WHERE sampleId = OLD.id AND domain = OLD.domain;
      END
    ''');
  }
  if (await _tableExists(db, 'chick_weights')) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_chick_quality_observation_parent_weights_delete
      BEFORE DELETE ON chick_weights
      BEGIN
        DELETE FROM chick_quality_observation
        WHERE sampleId = OLD.id AND domain = 'chicks.weights';
      END
    ''');
  }
  if (await _tableExists(db, 'photos')) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_photo_observation_owner_insert
      BEFORE INSERT ON photos
      WHEN NEW.observationId IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM chick_quality_observation o
        WHERE o.id = NEW.observationId
          AND o.sampleId = NEW.panelRowId
          AND o.sessionId = NEW.sessionId
          AND o.domain != 'chicks.weights'
          AND NEW.panelName = 'chick_quality'
      )
      BEGIN
        SELECT RAISE(ABORT, 'Photo observation owner mismatch');
      END
    ''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_photo_observation_owner_update
      BEFORE UPDATE OF observationId, panelRowId, sessionId, panelName ON photos
      WHEN NEW.observationId IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM chick_quality_observation o
        WHERE o.id = NEW.observationId
          AND o.sampleId = NEW.panelRowId
          AND o.sessionId = NEW.sessionId
          AND o.domain != 'chicks.weights'
          AND NEW.panelName = 'chick_quality'
      )
      BEGIN
        SELECT RAISE(ABORT, 'Photo observation owner mismatch');
      END
    ''');
    await db.execute('''CREATE TRIGGER IF NOT EXISTS
      trg_chick_quality_observation_photo_unlink
      AFTER DELETE ON chick_quality_observation
      BEGIN
        UPDATE photos SET observationId = NULL WHERE observationId = OLD.id;
      END
    ''');
  }
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

/// `localDataJson`/`remoteDataJson` (ticket 15) hold the full serialized
/// aggregate (header + child rows) on each side of a rejected daily-report
/// push, so a production manager can compare or merge them (design section
/// 13.1: "Preserved conflicting versions are stored in the existing
/// `sync_conflicts` table rather than in a new feature-specific conflict
/// store") — every other conflict this table already records (last-write
/// -wins on a single row, e.g. audit sessions) leaves them null.
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
    reviewedBy TEXT,
    localDataJson TEXT,
    remoteDataJson TEXT
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

  // A house belongs to exactly one flock: `flocks.entryDate` is the single
  // placement date for every house in the flock, and openingFemales /
  // openingMales carry the opening balance that used to live on a separate
  // flock_placements row. A farm and a flock are the same thing in this
  // business (see docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
  // section 2.1), so there is no farm table and no farm identifier anywhere
  // in this schema.
  await db.execute('''CREATE TABLE IF NOT EXISTS houses (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    name TEXT NOT NULL,
    code TEXT,
    capacity INTEGER,
    openingFemales INTEGER NOT NULL DEFAULT 0 CHECK (openingFemales >= 0),
    openingMales INTEGER NOT NULL DEFAULT 0 CHECK (openingMales >= 0),
    notes TEXT,
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    createdBy TEXT,
    createdAt TEXT,
    updatedAt TEXT,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
  )''');
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_houses_flock_name '
    'ON houses (flockId, name)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_houses_flock_code '
    'ON houses (flockId, code) WHERE code IS NOT NULL AND code <> \'\'',
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

/// Official breeder benchmark foundation (breeder-flock-performance ticket
/// 03): stable metric definitions, versioned benchmark profiles (one per
/// breed-company guide version), and the per-age target values belonging to
/// each profile. Benchmarks are versioned reference data loaded from checked
/// -in asset files by `importBreederBenchmarks` (see
/// lib/data/database/seeds/breeder_benchmark_seeds.dart) — clients never
/// write or edit them.
///
/// A profile's `state` starts as `draft` while its values are being
/// inserted by the importer, then is flipped to `active` in one final
/// UPDATE. From that point the triggers below make the profile row and all
/// of its value rows immutable: no UPDATE, INSERT, or DELETE can touch a
/// non-draft profile or its values. This is enforced by the database, not
/// just documented, so a bug elsewhere in the app cannot silently rewrite a
/// published guide.
Future<void> createBreederBenchmarkTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_metric_definitions (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL,
    unit TEXT NOT NULL,
    sexScope TEXT NOT NULL CHECK (sexScope IN ('female', 'male', 'both')),
    periodType TEXT NOT NULL CHECK (periodType IN ('daily', 'weekly', 'cumulative')),
    aggregationMethod TEXT NOT NULL CHECK (aggregationMethod IN ('average', 'sum', 'cumulative')),
    displayPrecision INTEGER NOT NULL DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_benchmark_profiles (
    id TEXT PRIMARY KEY,
    profileKey TEXT NOT NULL UNIQUE,
    company TEXT NOT NULL,
    breed TEXT NOT NULL,
    product TEXT NOT NULL,
    guideVersion TEXT NOT NULL,
    publicationDate TEXT,
    sourceUrl TEXT NOT NULL,
    effectiveAgeStartDays INTEGER NOT NULL DEFAULT 0,
    effectiveAgeEndDays INTEGER,
    lifecycleCoverage TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'draft' CHECK (state IN ('draft', 'active', 'archived')),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_benchmark_values (
    id TEXT PRIMARY KEY,
    profileId TEXT NOT NULL,
    metricId TEXT NOT NULL,
    sex TEXT NOT NULL CHECK (sex IN ('female', 'male', 'both')),
    ageDays INTEGER NOT NULL,
    ageWeek INTEGER NOT NULL,
    productionWeek INTEGER,
    periodType TEXT NOT NULL CHECK (periodType IN ('daily', 'weekly', 'cumulative')),
    targetValue REAL,
    lowerBound REAL,
    upperBound REAL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (profileId) REFERENCES breeder_benchmark_profiles(id) ON DELETE CASCADE,
    FOREIGN KEY (metricId) REFERENCES breeder_metric_definitions(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_benchmark_values_unique '
    'ON breeder_benchmark_values (profileId, metricId, sex, ageDays)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_benchmark_values_profile '
    'ON breeder_benchmark_values (profileId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_benchmark_values_metric '
    'ON breeder_benchmark_values (metricId)',
  );

  // Published (non-draft) profiles are immutable: block UPDATE and DELETE
  // once a profile has left the `draft` state. The importer's own
  // draft -> active transition is allowed because it fires while
  // OLD.state is still 'draft'.
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_benchmark_profiles_immutable_update
    BEFORE UPDATE ON breeder_benchmark_profiles
    WHEN OLD.state != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'Published benchmark profile is immutable');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_benchmark_profiles_immutable_delete
    BEFORE DELETE ON breeder_benchmark_profiles
    WHEN OLD.state != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'Published benchmark profile is immutable');
    END
  ''');

  // The values of a published profile are immutable too: block INSERT,
  // UPDATE, and DELETE against any value row whose profile is not `draft`.
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_benchmark_values_immutable_insert
    BEFORE INSERT ON breeder_benchmark_values
    WHEN (SELECT state FROM breeder_benchmark_profiles WHERE id = NEW.profileId) != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'Cannot add values to a published benchmark profile');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_benchmark_values_immutable_update
    BEFORE UPDATE ON breeder_benchmark_values
    WHEN (SELECT state FROM breeder_benchmark_profiles WHERE id = OLD.profileId) != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'Benchmark values of a published profile are immutable');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_benchmark_values_immutable_delete
    BEFORE DELETE ON breeder_benchmark_values
    WHEN (SELECT state FROM breeder_benchmark_profiles WHERE id = OLD.profileId) != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'Benchmark values of a published profile are immutable');
    END
  ''');
}

/// Operational milestone events for a breeder flock (breeder-flock
/// -performance ticket 06): grading, physical transfer, light stimulation,
/// first egg, 5%/50%/peak production, and partial/start-of/final depletion.
/// `eventType` is a constrained set (see `BreederFlockMilestoneType`), not
/// free text. One row per (flockId, eventType) — recording the same event
/// again corrects its date rather than appending a duplicate, which is what
/// lets `BreederFlockLifecycleService` treat "the recorded 5%-production
/// milestone" as unambiguous when computing the milestone-aligned comparison
/// axis.
Future<void> createBreederFlockMilestonesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_flock_milestones (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    eventType TEXT NOT NULL CHECK (eventType IN (
      'grading',
      'physical_transfer',
      'light_stimulation',
      'first_egg',
      'five_percent_production',
      'fifty_percent_production',
      'peak_production',
      'partial_depletion',
      'start_of_depletion',
      'final_depletion'
    )),
    eventDate TEXT NOT NULL,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_flock_milestones_unique '
    'ON breeder_flock_milestones (flockId, eventType)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_flock_milestones_flock '
    'ON breeder_flock_milestones (flockId)',
  );
}

/// Named isolation areas for a breeder flock (breeder-flock-performance
/// ticket 08, design doc section 6). A flock can have several isolation
/// areas; each belongs to exactly one flock (`FOREIGN KEY (flockId)`) and
/// its name must be unique within that flock, case-insensitively (the
/// unique index below), so entry and review can list houses and isolation
/// areas together without ambiguity. Movements against an isolation area
/// live in `breeder_bird_movements.isolationAreaId` — see that table's own
/// doc comment for how "exactly one location" and "location belongs to the
/// report's flock" are enforced.
Future<void> createBreederIsolationAreasTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_isolation_areas (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    name TEXT NOT NULL,
    notes TEXT,
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    createdBy TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_isolation_areas_unique_name '
    'ON breeder_isolation_areas (flockId, name COLLATE NOCASE)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_isolation_areas_flock '
    'ON breeder_isolation_areas (flockId)',
  );
}

/// Daily report header plus bird-movement ledger for a breeder flock
/// (breeder-flock-performance ticket 07, design doc section 5 and 6; header
/// `lightHours` and `breeder_feed_entries` added by ticket 09). This was
/// originally the first vertical slice of the daily report — header fields
/// plus bird movements only — with eggs and inventory left for later
/// tickets (10, 11), which still have no placeholder columns or tables
/// here.
///
/// `breeder_daily_reports` is one header row per flock and calendar date
/// (`UNIQUE (flockId, reportDate)`), covering all of that flock's houses.
/// Age, production week, and breed are never stored here — they are always
/// derived for display via `BreederFlockLifecycleService` and
/// `flocks.breed`. `revision` exists for ticket 15's optimistic
/// concurrency; this ticket only ever sets it to 1 on create and bumps it
/// on each state transition. `lightHours` (ticket 09, design section 5.1/
/// 5.2) is a plain hour count with no per-sector unit convention to label.
/// `eggProductionDenominatorFemales`, `benchmarkProfileVersionAtApproval`,
/// and `comparisonAxisAtApproval` (ticket 10, design section 7.1: "The
/// denominator actually used is retained in the approved report snapshot
/// for auditability, together with the benchmark profile version and
/// comparison axis") are written once, at approval, by
/// `BreederBirdLedgerService.approve` — they stay null for a report that
/// never reaches Approved, or that approves before the flock has entered
/// egg production.
///
/// `sync_conflict` (ticket 15, design section 5.3 and 13.1) is reachable
/// from any of the other three states when the report's aggregate push is
/// rejected by a stale concurrency token. `previousState` records which of
/// those three states the report held immediately before the conflict, so
/// resolving the conflict can restore it exactly — it is otherwise always
/// null. `lastSyncedRevision` is local-only optimistic-concurrency
/// bookkeeping (like `syncStatus`/`dirtyAt`/`lastSyncedAt`/`syncError`,
/// stripped from every cloud payload): despite its name, it does NOT track
/// [revision] above — it tracks the cloud's own `sync_token` column (added
/// by the cloud `breeder_daily_reports` table, see
/// `supabase/migrations_unapplied/0012_breeder_flock_sync_registration.sql`),
/// sent as the aggregate push's `base_revision` argument. The two counters
/// are kept strictly separate: `revision` is ticket 12's user-facing audit
/// counter and only ever moves on a state transition or a post-approval
/// correction; `sync_token` is an opaque counter the cloud RPC advances on
/// every successful aggregate push, transition or not, precisely so two
/// devices sitting at the same `revision` (neither having transitioned or
/// corrected the report) cannot both "match" and silently overwrite one
/// another's child rows — see
/// `supabase/migrations_unapplied/0013_breeder_daily_report_aggregate_push.sql`'s
/// header comment for the full mechanics, and
/// `lib/data/repositories/breeder_report_aggregate_repository.dart` and
/// `lib/services/breeder/breeder_report_sync_service.dart` for the client
/// side.
///

/// `breeder_bird_movements` is a child ledger row per report, location, and
/// sex. `opening`/`closing` are derived and persisted by
/// `BreederBirdLedgerService`, never typed directly by a user — the
/// `closing = opening - removals + transfers` arithmetic is additionally
/// enforced as a CHECK constraint so a row can never be stored
/// inconsistent with its own inputs. `kitchenRemoval` only applies to
/// female rows and `euthanasia` only to male rows (design section 5.2); a
/// CHECK constraint keeps the inapplicable column at zero rather than
/// leaving it as an unenforced convention.
///
/// A movement's location is either a house (`houseId`) or a named isolation
/// area (`isolationAreaId`, breeder-flock-performance ticket 08) — exactly
/// one, never both, never neither, enforced by the CHECK constraint below.
/// A trigger enforces that whichever location a movement names belongs to
/// the same flock as its report, because nothing else in the schema can
/// express that cross-table invariant. Moving birds between a house and an
/// isolation area (either direction) is recorded as two ordinary movement
/// rows — a transferOut on one location and the matching transferIn on the
/// other — and validated by `BreederBirdLedgerService.validateTransferBalance`
/// exactly like a house-to-house transfer; mortality, culls, sale, kitchen
/// removal, and euthanasia reduce the flock total wherever they are
/// recorded, houses and isolation alike.
Future<void> createBreederDailyReportTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_daily_reports (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    reportDate TEXT NOT NULL,
    insideTemperature REAL,
    outsideTemperature REAL,
    lightHours REAL,
    notes TEXT,
    state TEXT NOT NULL DEFAULT 'draft' CHECK (state IN ('draft', 'submitted', 'approved', 'sync_conflict')),
    previousState TEXT CHECK (previousState IS NULL OR previousState IN ('draft', 'submitted', 'approved')),
    revision INTEGER NOT NULL DEFAULT 1 CHECK (revision >= 1),
    lastSyncedRevision INTEGER NOT NULL DEFAULT 0,
    createdBy TEXT,
    submittedBy TEXT,
    submittedAt TEXT,
    approvedBy TEXT,
    approvedAt TEXT,
    eggProductionDenominatorFemales INTEGER,
    benchmarkProfileVersionAtApproval TEXT,
    comparisonAxisAtApproval TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_daily_reports_unique '
    'ON breeder_daily_reports (flockId, reportDate)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_daily_reports_flock '
    'ON breeder_daily_reports (flockId)',
  );

  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_bird_movements (
    id TEXT PRIMARY KEY,
    reportId TEXT NOT NULL,
    houseId TEXT,
    isolationAreaId TEXT,
    sex TEXT NOT NULL CHECK (sex IN ('female', 'male')),
    opening INTEGER NOT NULL DEFAULT 0 CHECK (opening >= 0),
    mortality INTEGER NOT NULL DEFAULT 0 CHECK (mortality >= 0),
    culls INTEGER NOT NULL DEFAULT 0 CHECK (culls >= 0),
    sale INTEGER NOT NULL DEFAULT 0 CHECK (sale >= 0),
    kitchenRemoval INTEGER NOT NULL DEFAULT 0 CHECK (kitchenRemoval >= 0),
    euthanasia INTEGER NOT NULL DEFAULT 0 CHECK (euthanasia >= 0),
    transferIn INTEGER NOT NULL DEFAULT 0 CHECK (transferIn >= 0),
    transferOut INTEGER NOT NULL DEFAULT 0 CHECK (transferOut >= 0),
    closing INTEGER NOT NULL DEFAULT 0 CHECK (closing >= 0),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK (closing = opening - mortality - culls - sale - kitchenRemoval - euthanasia + transferIn - transferOut),
    CHECK ((sex = 'female' AND euthanasia = 0) OR (sex = 'male' AND kitchenRemoval = 0)),
    CHECK ((houseId IS NOT NULL AND isolationAreaId IS NULL) OR (houseId IS NULL AND isolationAreaId IS NOT NULL)),
    FOREIGN KEY (reportId) REFERENCES breeder_daily_reports(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id),
    FOREIGN KEY (isolationAreaId) REFERENCES breeder_isolation_areas(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_bird_movements_unique '
    'ON breeder_bird_movements (reportId, houseId, sex)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_bird_movements_isolation_unique '
    'ON breeder_bird_movements (reportId, isolationAreaId, sex)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_bird_movements_report '
    'ON breeder_bird_movements (reportId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_bird_movements_house '
    'ON breeder_bird_movements (houseId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_bird_movements_isolation '
    'ON breeder_bird_movements (isolationAreaId)',
  );

  // A movement belongs to exactly one valid flock location: whichever of
  // houseId/isolationAreaId it names must belong to the same flock as the
  // report it is filed under. Expressed as a trigger because SQLite has no
  // cross-table CHECK. (The CHECK above already guarantees exactly one of
  // the two columns is set, so only the set one needs checking here.)
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_bird_movements_location_scope_insert
    BEFORE INSERT ON breeder_bird_movements
    WHEN
      (NEW.houseId IS NOT NULL AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
      OR
      (NEW.isolationAreaId IS NOT NULL AND (SELECT flockId FROM breeder_isolation_areas WHERE id = NEW.isolationAreaId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
    BEGIN
      SELECT RAISE(ABORT, 'Movement location does not belong to the report flock');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_bird_movements_location_scope_update
    BEFORE UPDATE ON breeder_bird_movements
    WHEN
      (NEW.houseId IS NOT NULL AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
      OR
      (NEW.isolationAreaId IS NOT NULL AND (SELECT flockId FROM breeder_isolation_areas WHERE id = NEW.isolationAreaId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
    BEGIN
      SELECT RAISE(ABORT, 'Movement location does not belong to the report flock');
    END
  ''');

  await createBreederFeedEntriesTable(db);
}

/// One location's feed record for one sex on one daily report
/// (breeder-flock-performance ticket 09, design doc section 5.2 and 7.1).
/// `feedKg` is the only stored input — grams-per-bird is always derived by
/// `BreederBirdLedgerService.feedGramsPerBird`, never stored here and never
/// independently editable (design doc section 7: "feed grams per bird =
/// feed kilograms * 1000 / applicable live birds").
///
/// A feed entry's location is either a house (`houseId`) or a named
/// isolation area (`isolationAreaId`) — exactly one, never both, never
/// neither, enforced by the CHECK constraint below, mirroring
/// `breeder_bird_movements`. The same location-scope trigger pattern proves
/// whichever location a row names belongs to the same flock as its report.
/// Isolation feed is its own row against isolation bird counts and is never
/// folded into a house figure (design doc section 7.1).
Future<void> createBreederFeedEntriesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_feed_entries (
    id TEXT PRIMARY KEY,
    reportId TEXT NOT NULL,
    houseId TEXT,
    isolationAreaId TEXT,
    sex TEXT NOT NULL CHECK (sex IN ('female', 'male')),
    feedKg REAL NOT NULL DEFAULT 0 CHECK (feedKg >= 0),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK ((houseId IS NOT NULL AND isolationAreaId IS NULL) OR (houseId IS NULL AND isolationAreaId IS NOT NULL)),
    FOREIGN KEY (reportId) REFERENCES breeder_daily_reports(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id),
    FOREIGN KEY (isolationAreaId) REFERENCES breeder_isolation_areas(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_feed_entries_unique '
    'ON breeder_feed_entries (reportId, houseId, sex)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_feed_entries_isolation_unique '
    'ON breeder_feed_entries (reportId, isolationAreaId, sex)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_feed_entries_report '
    'ON breeder_feed_entries (reportId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_feed_entries_house '
    'ON breeder_feed_entries (houseId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_feed_entries_isolation '
    'ON breeder_feed_entries (isolationAreaId)',
  );

  // Same cross-table scope invariant as
  // `trg_breeder_bird_movements_location_scope_*`: whichever location this
  // row names must belong to the same flock as its report.
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_feed_entries_location_scope_insert
    BEFORE INSERT ON breeder_feed_entries
    WHEN
      (NEW.houseId IS NOT NULL AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
      OR
      (NEW.isolationAreaId IS NOT NULL AND (SELECT flockId FROM breeder_isolation_areas WHERE id = NEW.isolationAreaId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
    BEGIN
      SELECT RAISE(ABORT, 'Feed entry location does not belong to the report flock');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_feed_entries_location_scope_update
    BEFORE UPDATE ON breeder_feed_entries
    WHEN
      (NEW.houseId IS NOT NULL AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
      OR
      (NEW.isolationAreaId IS NOT NULL AND (SELECT flockId FROM breeder_isolation_areas WHERE id = NEW.isolationAreaId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
    BEGIN
      SELECT RAISE(ABORT, 'Feed entry location does not belong to the report flock');
    END
  ''');
}

/// System-defined egg grades and the per-report, per-location, per-grade
/// egg count (breeder-flock-performance ticket 10, design doc section 5.2,
/// 7, and 12). See `BreederEggGradeDefinition` and
/// `BreederEggProductionEntry` for the field-level rationale, and
/// `BreederEggProductionService` for the priority-resolution and
/// total/percentage arithmetic.
///
/// `breeder_egg_grade_definitions` is reference data — system-defined, not
/// user-editable UI strings — seeded by
/// `seedBreederEggGradeDefinitions` and re-seeded (idempotently) on every
/// database open, the same pattern `importBreederBenchmarks` and
/// `seedEggDefectTypes` already use. `priority` must be unique within the
/// active grade set (design section 12 invariant): enforced by the partial
/// unique index below, scoped to `isActive = 1` so a retired grade's old
/// priority can be reused.
///
/// `breeder_egg_production_entries` mirrors `breeder_feed_entries`'s
/// location-XOR shape and location-scope trigger pattern, with `gradeId`
/// taking the place of `sex`: one row per (report, location, grade).
/// `count` is the only per-grade typed input — `BreederEggProductionService`
/// derives total eggs, egg-grade percent, and daily production percent from
/// it, never storing them. `eggWeightGrams` is a location-level value
/// duplicated across every grade row for that (report, location) — see the
/// model's doc comment for why it lives here rather than a separate table.
Future<void> createBreederEggGradeDefinitionsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_egg_grade_definitions (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    priority INTEGER NOT NULL CHECK (priority > 0),
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_egg_grade_definitions_active_priority '
    'ON breeder_egg_grade_definitions (priority) WHERE isActive = 1',
  );
}

Future<void> createBreederEggProductionEntriesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_egg_production_entries (
    id TEXT PRIMARY KEY,
    reportId TEXT NOT NULL,
    houseId TEXT,
    isolationAreaId TEXT,
    gradeId TEXT NOT NULL,
    count INTEGER NOT NULL DEFAULT 0 CHECK (count >= 0),
    eggWeightGrams REAL CHECK (eggWeightGrams IS NULL OR eggWeightGrams > 0),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK ((houseId IS NOT NULL AND isolationAreaId IS NULL) OR (houseId IS NULL AND isolationAreaId IS NOT NULL)),
    FOREIGN KEY (reportId) REFERENCES breeder_daily_reports(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id),
    FOREIGN KEY (isolationAreaId) REFERENCES breeder_isolation_areas(id),
    FOREIGN KEY (gradeId) REFERENCES breeder_egg_grade_definitions(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_egg_production_entries_unique '
    'ON breeder_egg_production_entries (reportId, houseId, gradeId)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_egg_production_entries_isolation_unique '
    'ON breeder_egg_production_entries (reportId, isolationAreaId, gradeId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_production_entries_report '
    'ON breeder_egg_production_entries (reportId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_production_entries_house '
    'ON breeder_egg_production_entries (houseId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_production_entries_isolation '
    'ON breeder_egg_production_entries (isolationAreaId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_production_entries_grade '
    'ON breeder_egg_production_entries (gradeId)',
  );

  // Same cross-table scope invariant as
  // `trg_breeder_bird_movements_location_scope_*` /
  // `trg_breeder_feed_entries_location_scope_*`: whichever location this
  // row names must belong to the same flock as its report.
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_egg_production_entries_location_scope_insert
    BEFORE INSERT ON breeder_egg_production_entries
    WHEN
      (NEW.houseId IS NOT NULL AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
      OR
      (NEW.isolationAreaId IS NOT NULL AND (SELECT flockId FROM breeder_isolation_areas WHERE id = NEW.isolationAreaId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
    BEGIN
      SELECT RAISE(ABORT, 'Egg production entry location does not belong to the report flock');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_egg_production_entries_location_scope_update
    BEFORE UPDATE ON breeder_egg_production_entries
    WHEN
      (NEW.houseId IS NOT NULL AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
      OR
      (NEW.isolationAreaId IS NOT NULL AND (SELECT flockId FROM breeder_isolation_areas WHERE id = NEW.isolationAreaId) IS NOT
        (SELECT flockId FROM breeder_daily_reports WHERE id = NEW.reportId))
    BEGIN
      SELECT RAISE(ABORT, 'Egg production entry location does not belong to the report flock');
    END
  ''');
}

/// The egg-inventory ledger, by grade, for one daily report
/// (breeder-flock-performance ticket 11, design doc section 7, 8, 12, and
/// 14). See `BreederEggInventoryMovement` for the field-level rationale and
/// `BreederEggInventoryService` for the balance arithmetic and
/// approval-gate validation.
///
/// Unlike `breeder_bird_movements`/`breeder_feed_entries`/
/// `breeder_egg_production_entries`, a row here names no house or isolation
/// area — inventory is tracked at the whole-flock level (design section
/// 5.2 has no per-location column for it) — so this table never needs the
/// `houses`-referencing location-scope trigger those tables carry, and is
/// therefore not part of the v68 houses-rebuild trigger-drop list in
/// database_migrations.dart.
///
/// `kind` is one of the five persisted movement kinds in
/// `BreederEggInventoryMovementKind` — "production in" is deliberately not
/// one of them; today's production is always derived live from
/// `breeder_egg_production_entries` rather than duplicated into a ledger
/// row (see the model's doc comment). `adjustmentDirection` is required
/// exactly when `kind = 'adjustment'`, never otherwise. `reason`,
/// `actorUserId`, and `occurredAt` are required for an adjustment or a
/// reversal (`reversedMovementId IS NOT NULL`) — design section 14:
/// "Adjustments require a reason, an actor, and a time" — and optional for
/// a plain dispatch/sale/kitchen/gift row.
///
/// The partial unique index below allows exactly one non-adjustment,
/// non-reversal, reason-less row per (report, grade, kind) — the
/// upsert-while-Draft slot `BreederEggInventoryService.recordMovement`
/// edits, which never sets a reason on a plain kind's row. Adjustments and
/// reversals are excluded from it (`kind <> 'adjustment' AND
/// reversedMovementId IS NULL`) since both are always appended as new rows,
/// never overwritten — the append-only ledger design section 8 describes.
///
/// The `AND reason IS NULL` clause (breeder-flock-performance ticket 12,
/// design doc section 8 and 12) is what lets a post-approval correction
/// coexist with its own original row without ever mutating it:
/// `BreederEggInventoryService.correctMovement` appends a reversal (already
/// excluded via `reversedMovementId IS NULL`) plus a brand-new row carrying
/// the same kind and the correction's own (required, non-empty) `reason` —
/// without this clause that new row would collide with the still-present,
/// never-touched original in this unique index, since both would otherwise
/// be "the" non-adjustment, non-reversal row for that (report, grade,
/// kind). A row only ever carries a non-null `reason` as the direct result
/// of a correction, so this clause changes nothing for an ordinary
/// Draft-time entry.
Future<void> createBreederEggInventoryMovementsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_egg_inventory_movements (
    id TEXT PRIMARY KEY,
    reportId TEXT NOT NULL,
    gradeId TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('hatchery_dispatch', 'sale', 'kitchen', 'gift', 'adjustment')),
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    adjustmentDirection TEXT CHECK (adjustmentDirection IS NULL OR adjustmentDirection IN ('increase', 'decrease')),
    reason TEXT,
    actorUserId TEXT,
    occurredAt TEXT,
    reversedMovementId TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK ((kind = 'adjustment' AND adjustmentDirection IS NOT NULL) OR (kind <> 'adjustment' AND adjustmentDirection IS NULL)),
    CHECK (kind <> 'adjustment' OR (reason IS NOT NULL AND reason <> '' AND actorUserId IS NOT NULL AND actorUserId <> '' AND occurredAt IS NOT NULL)),
    CHECK (reversedMovementId IS NULL OR (reason IS NOT NULL AND reason <> '' AND actorUserId IS NOT NULL AND actorUserId <> '')),
    FOREIGN KEY (reportId) REFERENCES breeder_daily_reports(id) ON DELETE CASCADE,
    FOREIGN KEY (gradeId) REFERENCES breeder_egg_grade_definitions(id),
    FOREIGN KEY (reversedMovementId) REFERENCES breeder_egg_inventory_movements(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_egg_inventory_movements_unique '
    'ON breeder_egg_inventory_movements (reportId, gradeId, kind) '
    "WHERE kind <> 'adjustment' AND reversedMovementId IS NULL AND reason IS NULL",
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_inventory_movements_report '
    'ON breeder_egg_inventory_movements (reportId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_inventory_movements_grade '
    'ON breeder_egg_inventory_movements (gradeId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_egg_inventory_movements_reversed '
    'ON breeder_egg_inventory_movements (reversedMovementId)',
  );
}

/// Permanent audit trail for a correction made to an already-APPROVED daily
/// report (breeder-flock-performance ticket 12, design doc section 5.3,
/// 12, and 13.1): "Any correction after approval requires a reason and
/// creates permanent revision history containing actor, time, old value,
/// and new value." A Draft report edits normally through the report's own
/// tables with no row appended here at all (design section 5: "Draft
/// reports edit normally with no revision history — history begins at
/// approval").
///
/// One row is written per changed field, not per correction action, so a
/// single "correct this report" save that touches three fields writes
/// three rows, each independently showing its own field/table/row identity
/// and its own old/new value. [tableName]/[rowId]/[fieldName] identify what
/// changed: [rowId] is the corrected row's own id for a child table
/// (`breeder_bird_movements`, `breeder_feed_entries`, etc.) or the report's
/// own id when [tableName] is `breeder_daily_reports` itself (the header
/// has no separate child row). [oldValue]/[newValue] are stored as plain
/// text — every corrected field in this feature (temperatures, counts,
/// notes) round-trips through `toString()`/`num.tryParse` cleanly, so a
/// second typed column per value type would only add complexity no reader
/// needs.
///
/// [revisionAfter] is the daily report's own `revision` counter value
/// *after* this correction was applied — ticket 07's optimistic-concurrency
/// counter doubles as the "which correction pass" grouping key, so every
/// row written by the same correction save shares one [revisionAfter].
///
/// Unlike `breeder_benchmark_profiles`/`breeder_benchmark_values` (ticket
/// 03), whose immutability only starts once a profile leaves `draft`, a
/// revision row is immutable from the instant it is written — there is no
/// draft state for a revision entry to begin in, since it only ever gets
/// created as the direct result of an approved-report correction. The
/// triggers below therefore block UPDATE and DELETE unconditionally, not
/// behind a `WHEN` guard.
///
/// This table names no house or isolation area, and its own triggers only
/// ever reference `breeder_report_revisions` and `breeder_daily_reports` —
/// never `houses` — so, like ticket 11's `breeder_egg_inventory_movements`,
/// it needs no entry in the v68 houses-rebuild trigger-drop list.
Future<void> createBreederReportRevisionsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_report_revisions (
    id TEXT PRIMARY KEY,
    reportId TEXT NOT NULL,
    tableName TEXT NOT NULL,
    rowId TEXT NOT NULL,
    fieldName TEXT NOT NULL,
    oldValue TEXT,
    newValue TEXT,
    reason TEXT NOT NULL CHECK (reason <> ''),
    actorUserId TEXT NOT NULL CHECK (actorUserId <> ''),
    revisionAfter INTEGER NOT NULL CHECK (revisionAfter >= 1),
    changedAt TEXT NOT NULL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (reportId) REFERENCES breeder_daily_reports(id) ON DELETE CASCADE
  )''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_report_revisions_report '
    'ON breeder_report_revisions (reportId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_report_revisions_report_revision '
    'ON breeder_report_revisions (reportId, revisionAfter)',
  );

  // A revision entry is immutable the instant it exists — no UPDATE, no
  // DELETE, unconditionally (see class doc comment above for why this has
  // no `WHEN OLD.state != 'draft'` guard the way the benchmark tables do).
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_report_revisions_immutable_update
    BEFORE UPDATE ON breeder_report_revisions
    BEGIN
      SELECT RAISE(ABORT, 'Revision entries are immutable');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_report_revisions_immutable_delete
    BEFORE DELETE ON breeder_report_revisions
    BEGIN
      SELECT RAISE(ABORT, 'Revision entries are immutable');
    END
  ''');
}

/// Periodic weighing sessions and their individual bird samples
/// (breeder-flock-performance ticket 13, design doc section 5.1 and 9).
/// Weighing is a workflow separate from the daily report — a session names
/// its own flock/house/sex/date rather than hanging off
/// `breeder_daily_reports` (design section 5.1: "Periodic weight and
/// uniformity entry is a separate workflow linked to flock, house, sex, and
/// date").
///
/// `breeder_weighing_sessions` records what was weighed and how:
/// [flockId]/[houseId]/[sex]/[sessionDate]/[method]/[sampleSize]. Exactly
/// one house is named (never isolation) and it must belong to [flockId] —
/// enforced below by the same cross-table trigger pattern
/// `breeder_bird_movements`/`breeder_feed_entries`/
/// `breeder_egg_production_entries` use, simplified to a single required
/// `houseId` column since a weighing session names no isolation-area
/// alternative. Because that trigger references `houses`, this table's
/// trigger names are added to the v68 houses-rebuild trigger-drop list in
/// database_migrations.dart, alongside those three tables'.
///
/// `method` is a short free-text label rather than a fixed enum: the design
/// doc does not publish a closed set of weighing methods (unlike `sex`,
/// which the whole feature already treats as closed), so a CHECK against an
/// invented list would risk rejecting a legitimate real-world method. Entry
/// UI still offers a documented list of common values for consistency; nothing
/// prevents free text if a farm's actual method is not on it.
///
/// The comparison result — official target, exact benchmark profile
/// version, and comparison axis used — is preserved on the session row at
/// the time it is computed (`BreederWeighingService.computeAndSaveDerived`),
/// per design section 9 and 3.1: "every stored comparison ... records which
/// axis produced it alongside the benchmark profile version." Re-running
/// the comparison later (e.g. after a benchmark re-import) overwrites these
/// columns with the newer result; there is no separate revision history for
/// weighing comparisons the way approved daily reports have one.
///
/// Derived figures (`derivedMeanWeightG`, `derivedUniformityPct`,
/// `derivedCvPct`) are caches written by `BreederWeighingService`, never
/// independently editable — the authoritative inputs are the individual
/// `breeder_weighing_samples` rows (or, for a summary-only session, none at
/// all, in which case the derived columns stay null).
///
/// `breeder_weighing_samples` holds the optional individual bird weights
/// for a session (design section 9: "optionally records individual bird
/// weights"). `weightGrams` must be non-negative. A session with no sample
/// rows is a valid "summary only" session; `BreederWeighingService` never
/// invents samples to back-fill it.
Future<void> createBreederWeighingSessionsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_weighing_sessions (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    houseId TEXT NOT NULL,
    sessionDate TEXT NOT NULL,
    sex TEXT NOT NULL CHECK (sex IN ('female', 'male')),
    method TEXT NOT NULL CHECK (method <> ''),
    sampleSize INTEGER NOT NULL CHECK (sampleSize > 0),
    notes TEXT,
    derivedMeanWeightG REAL,
    derivedUniformityPct REAL,
    derivedCvPct REAL,
    comparisonProfileId TEXT,
    comparisonProfileGuideVersion TEXT,
    comparisonAxisKind TEXT CHECK (comparisonAxisKind IS NULL OR comparisonAxisKind IN ('official', 'milestoneAligned')),
    comparisonAxisOffsetWeeks INTEGER,
    comparisonTargetWeightG REAL,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id),
    FOREIGN KEY (comparisonProfileId) REFERENCES breeder_benchmark_profiles(id)
  )''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_weighing_sessions_flock '
    'ON breeder_weighing_sessions (flockId, sessionDate)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_weighing_sessions_house '
    'ON breeder_weighing_sessions (houseId)',
  );

  // A session's house must belong to its flock — the single-house
  // counterpart of `trg_breeder_bird_movements_location_scope_*` /
  // `trg_breeder_feed_entries_location_scope_*` /
  // `trg_breeder_egg_production_entries_location_scope_*`, simplified since
  // there is no isolation-area alternative here to branch on.
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_weighing_sessions_house_scope_insert
    BEFORE INSERT ON breeder_weighing_sessions
    WHEN (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT NEW.flockId
    BEGIN
      SELECT RAISE(ABORT, 'Weighing session house does not belong to the session flock');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_weighing_sessions_house_scope_update
    BEFORE UPDATE ON breeder_weighing_sessions
    WHEN (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT NEW.flockId
    BEGIN
      SELECT RAISE(ABORT, 'Weighing session house does not belong to the session flock');
    END
  ''');

  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_weighing_samples (
    id TEXT PRIMARY KEY,
    sessionId TEXT NOT NULL,
    weightGrams REAL NOT NULL CHECK (weightGrams >= 0),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (sessionId) REFERENCES breeder_weighing_sessions(id) ON DELETE CASCADE
  )''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_weighing_samples_session '
    'ON breeder_weighing_samples (sessionId)',
  );
}

/// A flock's egg production for one collection date, scoped to a single
/// egg grade (breeder-flock-performance ticket 14, design doc section 8
/// and 12). See `lib/data/models/egg_batch_model.dart`'s doc comment for
/// why a batch carries its own `gradeId`. `EggBatchDispatchService` is the
/// single tested home for batch creation and the per-house sum check.
Future<void> createEggBatchesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_batches (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    collectionDate TEXT NOT NULL,
    gradeId TEXT NOT NULL,
    eggCount INTEGER NOT NULL DEFAULT 0 CHECK (eggCount >= 0),
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (gradeId) REFERENCES breeder_egg_grade_definitions(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_egg_batches_flock_date_grade '
    'ON egg_batches (flockId, collectionDate, gradeId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_batches_flock '
    'ON egg_batches (flockId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_batches_grade '
    'ON egg_batches (gradeId)',
  );
}

/// One house's optional contribution to an `egg_batches` row (design
/// section 8: "with optional per-house contributions"). A source's house
/// must belong to its batch's flock, enforced by
/// `trg_egg_batch_house_sources_house_scope_*` — like
/// `breeder_weighing_sessions` (ticket 13), this trigger references
/// `houses` and so is added to the version-68 houses-rebuild trigger-drop
/// list in `database_migrations.dart`.
Future<void> createEggBatchHouseSourcesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_batch_house_sources (
    id TEXT PRIMARY KEY,
    batchId TEXT NOT NULL,
    houseId TEXT NOT NULL,
    eggCount INTEGER NOT NULL DEFAULT 0 CHECK (eggCount >= 0),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (batchId) REFERENCES egg_batches(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_egg_batch_house_sources_unique '
    'ON egg_batch_house_sources (batchId, houseId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_batch_house_sources_house '
    'ON egg_batch_house_sources (houseId)',
  );

  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_egg_batch_house_sources_house_scope_insert
    BEFORE INSERT ON egg_batch_house_sources
    WHEN (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
      (SELECT flockId FROM egg_batches WHERE id = NEW.batchId)
    BEGIN
      SELECT RAISE(ABORT, 'Egg batch house source does not belong to the batch flock');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_egg_batch_house_sources_house_scope_update
    BEFORE UPDATE ON egg_batch_house_sources
    WHEN (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT
      (SELECT flockId FROM egg_batches WHERE id = NEW.batchId)
    BEGIN
      SELECT RAISE(ABORT, 'Egg batch house source does not belong to the batch flock');
    END
  ''');
}

/// A dispatch of one or more `egg_batches` rows to a customer's hatchery
/// (breeder-flock-performance ticket 14, design doc section 8 and 12).
/// `reportId` is `NULL` while `status = 'draft'` and is populated with the
/// flock's `breeder_daily_reports` row for `shipmentDate` at approval time —
/// see `lib/data/models/egg_shipment_model.dart`'s doc comment for why a
/// dispatch's ledger movement requires an existing report.
/// `inventoryMovementId`/`reversalMovementId` link to the single
/// `hatchery_dispatch` movement an approval posts, and the reversing
/// movement a cancellation posts, via `BreederEggInventoryService` (ticket
/// 11) — this table never records a second, parallel ledger.
Future<void> createEggShipmentsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_shipments (
    id TEXT PRIMARY KEY,
    flockId TEXT NOT NULL,
    hatcheryId TEXT NOT NULL,
    gradeId TEXT NOT NULL,
    shipmentDate TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'cancelled')),
    notes TEXT,
    reportId TEXT,
    inventoryMovementId TEXT,
    approvedBy TEXT,
    approvedAt TEXT,
    reversalMovementId TEXT,
    cancelledBy TEXT,
    cancelledAt TEXT,
    cancelReason TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    CHECK (status <> 'approved' OR (reportId IS NOT NULL AND inventoryMovementId IS NOT NULL AND approvedBy IS NOT NULL AND approvedAt IS NOT NULL)),
    CHECK (status <> 'cancelled' OR (reversalMovementId IS NOT NULL AND cancelledBy IS NOT NULL AND cancelledAt IS NOT NULL AND cancelReason IS NOT NULL)),
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (hatcheryId) REFERENCES hatcheries(id),
    FOREIGN KEY (gradeId) REFERENCES breeder_egg_grade_definitions(id),
    FOREIGN KEY (reportId) REFERENCES breeder_daily_reports(id),
    FOREIGN KEY (inventoryMovementId) REFERENCES breeder_egg_inventory_movements(id),
    FOREIGN KEY (reversalMovementId) REFERENCES breeder_egg_inventory_movements(id)
  )''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_shipments_flock '
    'ON egg_shipments (flockId, shipmentDate)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_shipments_hatchery '
    'ON egg_shipments (hatcheryId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_shipments_status '
    'ON egg_shipments (status)',
  );
}

/// Which `egg_batches` rows (and how many eggs from each) make up an
/// `egg_shipments` dispatch (design section 8 and 12). Cross-row invariants
/// (a batch not over-committed across shipments, a line's grade matching
/// its shipment) are enforced by `EggBatchDispatchService`, not a DB
/// constraint — SQLite has no portable way to check an aggregate across
/// sibling rows in a `CHECK`.
Future<void> createEggShipmentBatchesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_shipment_batches (
    id TEXT PRIMARY KEY,
    shipmentId TEXT NOT NULL,
    batchId TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (shipmentId) REFERENCES egg_shipments(id) ON DELETE CASCADE,
    FOREIGN KEY (batchId) REFERENCES egg_batches(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_egg_shipment_batches_unique '
    'ON egg_shipment_batches (shipmentId, batchId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_shipment_batches_shipment '
    'ON egg_shipment_batches (shipmentId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_egg_shipment_batches_batch '
    'ON egg_shipment_batches (batchId)',
  );
}

/// What a hatchery reported receiving for one `egg_shipment_batches` line,
/// and the (signed) variance against what was dispatched (design section 8
/// and 12). `receivedQuantity` is never negative; `variance` is signed and
/// is never used to rewrite the shipment line's dispatched `quantity`
/// (design section 8: a variance is recorded, not silently reconciled).
Future<void> createEggBatchReceiptsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS egg_batch_receipts (
    id TEXT PRIMARY KEY,
    shipmentBatchId TEXT NOT NULL,
    receivedQuantity INTEGER NOT NULL DEFAULT 0 CHECK (receivedQuantity >= 0),
    variance INTEGER NOT NULL DEFAULT 0,
    recordedBy TEXT,
    recordedAt TEXT,
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (shipmentBatchId) REFERENCES egg_shipment_batches(id) ON DELETE CASCADE
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_egg_batch_receipts_unique '
    'ON egg_batch_receipts (shipmentBatchId)',
  );
}

/// `breeder_alert_rules` (breeder-flock-performance ticket 17, design doc
/// section 10 and 12): system-wide Watch/Critical deviation rules. This is
/// reference data seeded by `seedBreederAlertRules` in
/// `breeder_alert_rule_seeds.dart` — client roles never create, edit, or
/// delete these rows (mirrors `breeder_benchmark_profiles`/
/// `breeder_metric_definitions`'s "seeded, sync down only" treatment; see
/// `PerformanceSyncRepository.breederReferencePullOnly`).
///
/// `metricCode` deliberately carries no FOREIGN KEY to
/// `breeder_metric_definitions(code)`: two of the five alertable metrics
/// (`uniformity_pct`, `cv_pct` — see `BreederAlertMetric`) are derived
/// entirely client-side by `BreederWeighingService` and have no row in that
/// officially-sourced table at all (design section 10: "publishes NO
/// uniformity or CV target"), so requiring the FK would make alerting on
/// them impossible.
///
/// One rule may exist per (metricCode, scope, periodType, direction) —
/// the unique index below enforces it — so evaluation never has to choose
/// between two competing rules for the same question.
Future<void> createBreederAlertRulesTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_alert_rules (
    id TEXT PRIMARY KEY,
    metricCode TEXT NOT NULL CHECK (metricCode IN ('body_weight_g', 'hen_week_production_pct', 'liveability_rearing_pct', 'uniformity_pct', 'cv_pct')),
    scope TEXT NOT NULL CHECK (scope IN ('flock', 'house')),
    periodType TEXT NOT NULL CHECK (periodType IN ('daily', 'weekly', 'cumulative')),
    direction TEXT NOT NULL CHECK (direction IN ('below', 'above', 'either')),
    watchDeviationPct REAL NOT NULL CHECK (watchDeviationPct >= 0),
    criticalDeviationPct REAL NOT NULL CHECK (criticalDeviationPct >= 0),
    consecutiveObservationsRequired INTEGER NOT NULL DEFAULT 1 CHECK (consecutiveObservationsRequired >= 1),
    usesOfficialBound INTEGER NOT NULL DEFAULT 0 CHECK (usesOfficialBound IN (0, 1)),
    isActive INTEGER NOT NULL DEFAULT 1 CHECK (isActive IN (0, 1)),
    notes TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_alert_rules_unique '
    'ON breeder_alert_rules (metricCode, scope, periodType, direction)',
  );
}

/// `breeder_performance_alerts` (breeder-flock-performance ticket 17,
/// design doc section 10 and 12): the operational record of one deviation
/// against one customer/flock/(house)/metric/period.
///
/// `houseId` is optional — a flock-scope rule never sets it — but when
/// present it must belong to the alert's own `flockId`, guarded by the
/// same house-scope trigger pattern as `breeder_weighing_sessions` /
/// `breeder_feed_entries` / `breeder_egg_production_entries` /
/// `egg_batch_house_sources`, simplified since `houseId IS NULL` is a valid
/// (flock-scope) case those tables never had to allow for. Because this
/// trigger references `houses`, it is added to the v68 houses-rebuild
/// trigger-drop list (`_rebuildV68HousesTable`'s
/// `hasBreederPerformanceAlertsGuards` check) alongside theirs.
///
/// `evidenceReportDatesJson` is a comma-joined list of ISO date-only
/// strings (see `BreederPerformanceAlert._encodeDates`/`_decodeDates`), not
/// a foreign key to `breeder_daily_reports` — that table's aggregate push
/// travels through its own revision-guarded transaction (see
/// `PerformanceSyncRepository.breederAggregatePullOnly`'s doc comment) and
/// must not gate this table's push order. It is how
/// `BreederAlertEvaluationService.recomputeAffectedByRevision` finds every
/// open alert a given report revision might have invalidated.
///
/// The partial unique index below is the schema-level enforcement of
/// design section 12's "one open performance alert per customer, flock,
/// house, metric, and period": it applies only to non-closed rows, so a
/// closed alert never blocks a fresh one from opening for the same key, and
/// `COALESCE(..., '')` folds a NULL `customerId`/`houseId` (flock-scope) to
/// a stable empty string — two NULLs are otherwise distinct values to a
/// SQLite UNIQUE index and would never collide, silently defeating the
/// dedupe for exactly the flock-scope case this feature relies on most.
Future<void> createBreederPerformanceAlertsTable(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS breeder_performance_alerts (
    id TEXT PRIMARY KEY,
    customerId TEXT,
    flockId TEXT NOT NULL,
    houseId TEXT,
    ruleId TEXT NOT NULL,
    metricCode TEXT NOT NULL CHECK (metricCode IN ('body_weight_g', 'hen_week_production_pct', 'liveability_rearing_pct', 'uniformity_pct', 'cv_pct')),
    scope TEXT NOT NULL CHECK (scope IN ('flock', 'house')),
    periodType TEXT NOT NULL CHECK (periodType IN ('daily', 'weekly', 'cumulative')),
    periodStart TEXT NOT NULL,
    periodEnd TEXT NOT NULL,
    actualValue REAL NOT NULL,
    officialTargetValue REAL,
    officialLowerBound REAL,
    officialUpperBound REAL,
    thresholdIsOfficial INTEGER NOT NULL DEFAULT 0 CHECK (thresholdIsOfficial IN (0, 1)),
    deviationValue REAL NOT NULL,
    deviationPct REAL,
    severity TEXT NOT NULL CHECK (severity IN ('watch', 'critical')),
    consecutiveObservationCount INTEGER NOT NULL DEFAULT 1 CHECK (consecutiveObservationCount >= 1),
    benchmarkProfileId TEXT,
    benchmarkProfileVersion TEXT,
    comparisonAxisKind TEXT CHECK (comparisonAxisKind IS NULL OR comparisonAxisKind IN ('official', 'milestoneAligned')),
    comparisonAxisOffsetWeeks INTEGER,
    evidenceReportDatesJson TEXT NOT NULL DEFAULT '',
    state TEXT NOT NULL DEFAULT 'new' CHECK (state IN ('new', 'seen', 'closed')),
    closedReason TEXT,
    closedAt TEXT,
    acknowledgedAt TEXT,
    acknowledgedBy TEXT,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    syncStatus TEXT NOT NULL DEFAULT 'pending',
    dirtyAt TEXT,
    lastSyncedAt TEXT,
    syncError TEXT,
    FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE CASCADE,
    FOREIGN KEY (flockId) REFERENCES flocks(id) ON DELETE CASCADE,
    FOREIGN KEY (houseId) REFERENCES houses(id),
    FOREIGN KEY (ruleId) REFERENCES breeder_alert_rules(id)
  )''');

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_performance_alerts_open_unique '
    'ON breeder_performance_alerts '
    "(COALESCE(customerId, ''), flockId, COALESCE(houseId, ''), metricCode, periodType, periodStart, periodEnd) "
    "WHERE state <> 'closed'",
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_performance_alerts_flock '
    'ON breeder_performance_alerts (flockId, periodType, periodStart)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_performance_alerts_house '
    'ON breeder_performance_alerts (houseId)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_breeder_performance_alerts_state '
    'ON breeder_performance_alerts (state)',
  );

  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_performance_alerts_house_scope_insert
    BEFORE INSERT ON breeder_performance_alerts
    WHEN NEW.houseId IS NOT NULL
      AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT NEW.flockId
    BEGIN
      SELECT RAISE(ABORT, 'Performance alert house does not belong to the alert flock');
    END
  ''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS
    trg_breeder_performance_alerts_house_scope_update
    BEFORE UPDATE ON breeder_performance_alerts
    WHEN NEW.houseId IS NOT NULL
      AND (SELECT flockId FROM houses WHERE id = NEW.houseId) IS NOT NEW.flockId
    BEGIN
      SELECT RAISE(ABORT, 'Performance alert house does not belong to the alert flock');
    END
  ''');
}
