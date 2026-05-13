part of 'database_helper.dart';

const String _stationSamplesRebuildTable = 'station_samples__v20_rebuild';
const String _auditsRebuildTable = 'audits__v27_rebuild';
const Set<String> _obsoleteGoveeAuditColumns = {
  'chaGoveeConnected',
  'soGoveeConnected',
  'soGoveeTemp',
  'soGoveeHumidity',
  'hoGoveeConnected',
  'hoGoveeTemp',
  'hoGoveeHumidity',
  'esGoveeConnected',
  'esGoveeTemp',
  'esGoveeHumidity',
};
Future<void> _applyV15Upgrade(Database db) async {
  await _createAuditSessionTables(db);
  await _addColumnIfMissing(db, 'audits', 'sessionId', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_sampleSize', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_collectionPoint', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_omphalitisCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_omphalitisSeverity', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_gaseousCecaCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_gaseousCecaSeverity', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_unabsorbedYolkCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_unabsorbedYolkSeverity', 'TEXT');
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
  await _addColumnIfMissing(db, 'audits', 'pm_ectopicVisceraCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_extraLegsCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_crossedBeakCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_absentEyeBothCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_absentEyeOneCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_smallEyeCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_hydrocephalyCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_starGazerCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_curledToesCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_shortLegsCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_spinalDeformityCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_cardiacAnomalyCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_conjoinedCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_otherDeformityCount', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'pm_otherDeformityText', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_suspectedCauseAuto', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_suspectedCauseManual', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'pm_photosJson', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'es_estReadingsJson', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'es_estAvg', 'REAL');
  await _addColumnIfMissing(db, 'audits', 'es_estCv', 'REAL');
  await _addColumnIfMissing(db, 'audits', 'es_uvSampleSize', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'es_uvCuticleDamageCount', 'INTEGER');
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
  await _addColumnIfMissing(db, 'audits', 'haContaminatedExploders', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'haBenchmarkStatusesJson', 'TEXT');
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

Future<void> _applyV19Upgrade(Database db) async {
  await _createStationSamplesTable(db);
}

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
    await _createLegacyStationSamplesIndexes(db);
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

Future<void> _applyV21Upgrade(Database db) async {
  await _addColumnIfMissing(db, 'audits', 'cvtReadingsJson', 'TEXT');
  await _addColumnIfMissing(db, 'audits', 'cvtPhotosJson', 'TEXT');
}

Future<void> _applyV22Upgrade(Database db) async {
  await _createGoveeCaptureTables(db);
  if (!await _tableExists(db, 'temperature_sessions')) return;
  if (await _tableExists(db, 'temperature_readings')) {
    await db.execute('''
DELETE FROM temperature_readings WHERE sessionId IN (
SELECT id FROM temperature_sessions
WHERE auditSessionId IS NOT NULL
)
''');
  }
  await db.execute(
    'DELETE FROM temperature_sessions WHERE auditSessionId IS NOT NULL',
  );
}

Future<void> _applyV23Upgrade(Database db) async {
  await _renameStationIdentityValues(db);
}

Future<void> _applyV24Upgrade(Database db) async {
  await _normalizeGoveePlaceValues(db);
}

Future<void> _applyV25Upgrade(Database db) async {
  if (!await _tableExists(db, 'govee_daily_captures')) {
    await _createGoveeCaptureTables(db);
    return;
  }
  final dailyRows = await db.query('govee_daily_captures');
  await _dropObsoleteGoveeTables(db);
  await db.execute('DROP TABLE IF EXISTS govee_daily_captures');
  await _createGoveeCaptureTables(db);
  for (final row in dailyRows) {
    await db.insert('govee_daily_captures', _migrateGoveeDailyRow(row));
  }
}

Future<void> _applyV26Upgrade(Database db) async {
  await _applyV25Upgrade(db);
}

Future<void> _applyV27Upgrade(Database db) async {
  await _dropObsoleteGoveeTables(db);
  await _rebuildAuditsTableWithoutObsoleteGoveeColumns(db);
}

Future<void> _applyV28Upgrade(Database db) async {
  await _dropLegacyTemperatureRhTables(db);
}

Future<void> _applyV29Upgrade(Database db) async {
  await db.execute('DROP TABLE IF EXISTS bmk_egg_breakout');
  await _createCleanBmkEggBreakoutTable(db);
  for (final seed in kBmkEggBreakoutSeeds) {
    await db.insert(
      'bmk_egg_breakout',
      _cleanBmkEggBreakoutSeed(seed),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

Future<void> _applyV30Upgrade(Database db) async {
  if (!await _tableExists(db, 'audits')) return;
  await _addColumnIfMissing(db, 'audits', 'soIncubationHours', 'INTEGER');
  await _addColumnIfMissing(db, 'audits', 'hoIncubationHours', 'INTEGER');
}

Future<void> _applyV31Upgrade(Database db) async {
  final hasLegacySamples = await _tableExists(db, 'station_samples');
  await _createStationSamplesTable(db);
  if (!hasLegacySamples) return;
  final legacyRows = await db.query('station_samples');
  await db.transaction<void>((txn) async {
    await _copyLegacyStationSamples(txn);
  });
  await _verifyLegacyStationSamplesCopied(db, legacyRows);
  await db.execute('DROP TABLE IF EXISTS station_samples');
}

Future<void> _applyV32Upgrade(Database db) async {
  await _createPanelSampleSchemaTables(db);
}

Future<void> _applyV33Upgrade(Database db) async {
  await _createSyncTombstoneTable(db);
}

Future<void> _applyV34Upgrade(Database db) async {
  await _nullDanglingReference(
    db,
    table: 'flocks',
    column: 'customerId',
    parentTable: 'customers',
  );
  await _deleteDanglingReference(
    db,
    table: 'hatcheries',
    column: 'customerId',
    parentTable: 'customers',
  );
  await _deleteDanglingReference(
    db,
    table: 'audit_sessions',
    column: 'customerId',
    parentTable: 'customers',
  );
  await _deleteDanglingReference(
    db,
    table: 'audit_sessions',
    column: 'flockId',
    parentTable: 'flocks',
  );
  await _deleteDanglingReference(
    db,
    table: 'audit_sessions',
    column: 'hatcheryId',
    parentTable: 'hatcheries',
  );
  await _nullDanglingReference(
    db,
    table: 'audits',
    column: 'customerId',
    parentTable: 'customers',
  );
  await _nullDanglingReference(
    db,
    table: 'audits',
    column: 'flockId',
    parentTable: 'flocks',
  );
  await _nullDanglingReference(
    db,
    table: 'audits',
    column: 'sessionId',
    parentTable: 'audit_sessions',
  );
  await _nullDanglingReference(
    db,
    table: 'photos',
    column: 'auditId',
    parentTable: 'audits',
  );
  await _deleteDanglingReference(
    db,
    table: 'sample_records',
    column: 'auditSessionId',
    parentTable: 'audit_sessions',
  );
  await _nullDanglingReference(
    db,
    table: 'sample_records',
    column: 'legacyAuditId',
    parentTable: 'audits',
  );
  for (final table in const [
    'sample_house_details',
    'sample_machine_details',
    'sample_batch_details',
    'sample_timing_details',
  ]) {
    await _deleteDanglingReference(
      db,
      table: table,
      column: 'sampleRecordId',
      parentTable: 'sample_records',
    );
  }
  await _deleteDanglingReference(
    db,
    table: 'govee_daily_captures',
    column: 'customerId',
    parentTable: 'customers',
  );
  await _deleteDanglingReference(
    db,
    table: 'govee_daily_captures',
    column: 'hatcheryId',
    parentTable: 'hatcheries',
  );
  for (final panel in PanelSampleSchema.panels) {
    await _deleteDanglingReference(
      db,
      table: panel.tableName,
      column: 'sessionId',
      parentTable: 'audit_sessions',
    );
    await _deleteDanglingReference(
      db,
      table: panel.tableName,
      column: 'customerId',
      parentTable: 'customers',
    );
    await _nullDanglingReference(
      db,
      table: panel.tableName,
      column: 'auditId',
      parentTable: 'audits',
    );
    await _nullDanglingReference(
      db,
      table: panel.tableName,
      column: 'flockId',
      parentTable: 'flocks',
    );
    await _nullDanglingReference(
      db,
      table: panel.tableName,
      column: 'hatcheryId',
      parentTable: 'hatcheries',
    );
    await _deleteDanglingReference(
      db,
      table: panel.sampleTableName,
      column: 'panelId',
      parentTable: panel.tableName,
    );
  }
  final foreignKeyRows = await db.rawQuery('PRAGMA foreign_keys');
  final foreignKeysEnabled =
      foreignKeyRows.isNotEmpty &&
      _pragmaInt(foreignKeyRows.first['foreign_keys']) == 1;
  if (foreignKeysEnabled) {
    await db.execute('PRAGMA foreign_keys = OFF');
  }
  try {
    await db.transaction((txn) async {
      await _rebuildTableWithForeignKeys(txn, 'flocks', const [
        'FOREIGN KEY ("customerId") REFERENCES customers(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'hatcheries', const [
        'FOREIGN KEY ("customerId") REFERENCES customers(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'audit_sessions', const [
        'FOREIGN KEY ("customerId") REFERENCES customers(id) ON DELETE CASCADE',
        'FOREIGN KEY ("flockId") REFERENCES flocks(id) ON DELETE CASCADE',
        'FOREIGN KEY ("hatcheryId") REFERENCES hatcheries(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'audits', const [
        'FOREIGN KEY ("customerId") REFERENCES customers(id) ON DELETE CASCADE',
        'FOREIGN KEY ("flockId") REFERENCES flocks(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'photos', const [
        'FOREIGN KEY ("auditId") REFERENCES audits(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'sample_records', const [
        'FOREIGN KEY ("auditSessionId") REFERENCES audit_sessions(id) ON DELETE CASCADE',
        'FOREIGN KEY ("legacyAuditId") REFERENCES audits(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'sample_house_details', const [
        'FOREIGN KEY ("sampleRecordId") REFERENCES sample_records(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'sample_machine_details', const [
        'FOREIGN KEY ("sampleRecordId") REFERENCES sample_records(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'sample_batch_details', const [
        'FOREIGN KEY ("sampleRecordId") REFERENCES sample_records(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'sample_timing_details', const [
        'FOREIGN KEY ("sampleRecordId") REFERENCES sample_records(id) ON DELETE CASCADE',
      ]);
      await _rebuildTableWithForeignKeys(txn, 'govee_daily_captures', const [
        'UNIQUE(customerId, hatcheryId, place, machineId, captureDate)',
        'FOREIGN KEY ("customerId") REFERENCES customers(id) ON DELETE CASCADE',
        'FOREIGN KEY ("hatcheryId") REFERENCES hatcheries(id) ON DELETE CASCADE',
      ]);
      for (final panel in PanelSampleSchema.panels) {
        await _rebuildTableWithForeignKeys(txn, panel.tableName, const [
          'FOREIGN KEY ("sessionId") REFERENCES audit_sessions(id) ON DELETE CASCADE',
          'FOREIGN KEY ("auditId") REFERENCES audits(id) ON DELETE SET NULL',
          'FOREIGN KEY ("customerId") REFERENCES customers(id) ON DELETE CASCADE',
          'FOREIGN KEY ("flockId") REFERENCES flocks(id) ON DELETE CASCADE',
          'FOREIGN KEY ("hatcheryId") REFERENCES hatcheries(id) ON DELETE CASCADE',
        ]);
        await _rebuildTableWithForeignKeys(txn, panel.sampleTableName, [
          'FOREIGN KEY ("panelId") REFERENCES ${panel.tableName}(id) ON DELETE CASCADE',
        ]);
      }
    });
  } finally {
    if (foreignKeysEnabled) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
  await _createHatcheryTables(db);
  await _createAuditSessionTables(db);
  await _createOperationalIndexes(db);
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_audits_unique ON audits (customerId, flockId, date, auditType, hatchNumber, setterId, hatcherId)',
  );
  await _createActivityLogIndexes(db);
  await _createStationSamplesIndexes(db);
  await _createGoveeCaptureTables(db);
  await _createPanelSampleSchemaTables(db);
  final violations = await db.rawQuery('PRAGMA foreign_key_check');
  if (violations.isNotEmpty) {
    throw StateError('Database integrity migration left FK violations');
  }
}

Future<void> _dropObsoleteGoveeTables(DatabaseExecutor db) async {
  await db.execute('DROP TABLE IF EXISTS govee_place_readings');
  await db.execute('DROP TABLE IF EXISTS govee_spot_readings');
  await db.execute('DROP TABLE IF EXISTS govee_spot_captures');
}

Future<void> _dropLegacyTemperatureRhTables(DatabaseExecutor db) async {
  await db.execute('DROP TABLE IF EXISTS temperature_readings');
  await db.execute('DROP TABLE IF EXISTS temperature_sessions');
}

Future<void> _nullDanglingReference(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String parentTable,
  String parentColumn = 'id',
}) async {
  if (!await _tableExists(db, table) || !await _tableExists(db, parentTable)) {
    return;
  }
  final columns = _columnNames(await db.rawQuery('PRAGMA table_info($table)'));
  if (!columns.contains(column)) return;
  final quotedTable = _quoteSqlIdentifier(table);
  final quotedColumn = _quoteSqlIdentifier(column);
  final quotedParentTable = _quoteSqlIdentifier(parentTable);
  final quotedParentColumn = _quoteSqlIdentifier(parentColumn);
  await db.execute('''
UPDATE $quotedTable
SET $quotedColumn = NULL
WHERE $quotedColumn IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM $quotedParentTable
    WHERE $quotedParentTable.$quotedParentColumn = $quotedTable.$quotedColumn
  )
''');
}

Future<void> _deleteDanglingReference(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String parentTable,
  String parentColumn = 'id',
}) async {
  if (!await _tableExists(db, table) || !await _tableExists(db, parentTable)) {
    return;
  }
  final columns = _columnNames(await db.rawQuery('PRAGMA table_info($table)'));
  if (!columns.contains(column)) return;
  final quotedTable = _quoteSqlIdentifier(table);
  final quotedColumn = _quoteSqlIdentifier(column);
  final quotedParentTable = _quoteSqlIdentifier(parentTable);
  final quotedParentColumn = _quoteSqlIdentifier(parentColumn);
  await db.execute('''
DELETE FROM $quotedTable
WHERE $quotedColumn IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM $quotedParentTable
    WHERE $quotedParentTable.$quotedParentColumn = $quotedTable.$quotedColumn
  )
''');
}

Future<void> _rebuildTableWithForeignKeys(
  DatabaseExecutor db,
  String table,
  List<String> foreignKeyConstraints,
) async {
  if (!await _tableExists(db, table)) return;
  final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
  if (tableInfo.isEmpty) return;
  final rebuildTable = '${table}__v34_rebuild';
  final columnDefinitions = <String>[];
  final insertColumns = <String>[];
  final selectExpressions = <String>[];
  for (final column in tableInfo) {
    final name = column['name']?.toString();
    if (name == null || name.isEmpty) continue;
    final quotedName = _quoteSqlIdentifier(name);
    columnDefinitions.add(_columnDefinitionForRebuild(column));
    insertColumns.add(quotedName);
    selectExpressions.add(quotedName);
  }
  await db.execute('DROP TABLE IF EXISTS ${_quoteSqlIdentifier(rebuildTable)}');
  await db.execute('''
CREATE TABLE ${_quoteSqlIdentifier(rebuildTable)} (
  ${[...columnDefinitions, ...foreignKeyConstraints].join(',\n  ')}
)''');
  await db.execute(
    'INSERT INTO ${_quoteSqlIdentifier(rebuildTable)} '
    '(${insertColumns.join(', ')}) '
    'SELECT ${selectExpressions.join(', ')} FROM ${_quoteSqlIdentifier(table)}',
  );
  await db.execute('DROP TABLE ${_quoteSqlIdentifier(table)}');
  await db.execute(
    'ALTER TABLE ${_quoteSqlIdentifier(rebuildTable)} '
    'RENAME TO ${_quoteSqlIdentifier(table)}',
  );
}

Future<void> _copyLegacyStationSamples(DatabaseExecutor db) async {
  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('station_samples')"),
  );
  String expr(String column, String fallback) {
    return columns.contains(column) ? _quoteSqlIdentifier(column) : fallback;
  }

  final stationTypeExpr = expr('stationType', "''");
  final comparisonTypeExpr = expr('comparisonType', 'NULL');
  await db.execute('''
INSERT OR REPLACE INTO sample_records (
  id,
  auditSessionId,
  legacyAuditId,
  stationType,
  sectorType,
  sampleKind,
  sampleMode,
  comparisonType,
  sampleIndex,
  sampleLabel,
  sampleType,
  breakoutType,
  groupKey,
  groupLabel,
  calculatedBmkAgeDays,
  benchmarkBreed,
  benchmarkAgeDays,
  benchmarkSource,
  benchmarkSnapshotJson,
  resultSummaryJson,
  notes,
  createdAt,
  updatedAt
)
SELECT
  ${expr('id', "lower(hex(randomblob(16)))")},
  ${expr('auditSessionId', "''")},
  ${expr('legacyAuditId', 'NULL')},
  $stationTypeExpr,
  ${expr('sectorType', _legacyStationSampleSectorSql(stationTypeExpr))},
  ${expr('sampleKind', _legacyStationSampleKindSql(comparisonTypeExpr, columns))},
  ${expr('sampleMode', "'pooled'")},
  $comparisonTypeExpr,
  ${expr('sampleIndex', '1')},
  ${expr('sampleLabel', 'NULL')},
  ${expr('sampleType', 'NULL')},
  ${expr('breakoutType', 'NULL')},
  ${expr('groupKey', 'NULL')},
  ${expr('groupLabel', 'NULL')},
  ${expr('calculatedBmkAgeDays', 'NULL')},
  ${expr('benchmarkBreed', 'NULL')},
  ${expr('benchmarkAgeDays', 'NULL')},
  ${expr('benchmarkSource', 'NULL')},
  ${expr('benchmarkSnapshotJson', 'NULL')},
  ${expr('resultSummaryJson', 'NULL')},
  ${expr('notes', 'NULL')},
  ${expr('createdAt', "datetime('now')")},
  ${expr('updatedAt', "datetime('now')")}
FROM station_samples
''');
  await _copyLegacyStationSampleDetail(
    db,
    targetTable: 'sample_house_details',
    targetColumns: const ['houseNo', 'houseLabel'],
    sourceColumns: const ['houseNo', 'houseLabel'],
    legacyColumns: columns,
  );
  await _copyLegacyStationSampleDetail(
    db,
    targetTable: 'sample_machine_details',
    targetColumns: const ['setterNo', 'hatcherNo'],
    sourceColumns: const ['setterNo', 'hatcherNo'],
    legacyColumns: columns,
  );
  await _copyLegacyStationSampleDetail(
    db,
    targetTable: 'sample_batch_details',
    targetColumns: const ['batchNo', 'hatchNo', 'storageDays', 'incubationDay'],
    sourceColumns: const ['batchNo', 'hatchNo', 'storageDays', 'incubationDay'],
    legacyColumns: columns,
  );
  await _copyLegacyStationSampleDetail(
    db,
    targetTable: 'sample_timing_details',
    targetColumns: const ['eggProductionDate', 'settingDate', 'hatchDate'],
    sourceColumns: const ['eggProductionDate', 'settingDate', 'hatchDate'],
    legacyColumns: columns,
  );
}

Future<void> _copyLegacyStationSampleDetail(
  DatabaseExecutor db, {
  required String targetTable,
  required List<String> targetColumns,
  required List<String> sourceColumns,
  required Set<String> legacyColumns,
}) async {
  final availableSourceColumns = sourceColumns
      .where(legacyColumns.contains)
      .toList(growable: false);
  if (availableSourceColumns.isEmpty) return;
  final targetColumnList = [
    'sampleRecordId',
    ...targetColumns,
  ].map(_quoteSqlIdentifier).join(', ');
  final selectExpressions = [
    _quoteSqlIdentifier('id'),
    for (final column in sourceColumns)
      legacyColumns.contains(column) ? _quoteSqlIdentifier(column) : 'NULL',
  ].join(', ');
  final detailPresentWhere = availableSourceColumns
      .map((column) => '${_quoteSqlIdentifier(column)} IS NOT NULL')
      .join(' OR ');
  await db.execute('''
INSERT OR REPLACE INTO $targetTable ($targetColumnList)
SELECT $selectExpressions
FROM station_samples
WHERE $detailPresentWhere
''');
}

Future<void> _verifyLegacyStationSamplesCopied(
  DatabaseExecutor db,
  List<Map<String, Object?>> legacyRows,
) async {
  for (final row in legacyRows) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError(
        'Cannot drop station_samples: found a row without an id.',
      );
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sample_records WHERE id = ?', [
        id,
      ]),
    );
    if (count != 1) {
      throw StateError(
        'Cannot drop station_samples: sample $id was not copied safely.',
      );
    }
    await _verifyLegacyStationSampleDetailCopied(
      db,
      id: id,
      legacyRow: row,
      targetTable: 'sample_house_details',
      sourceColumns: const ['houseNo', 'houseLabel'],
    );
    await _verifyLegacyStationSampleDetailCopied(
      db,
      id: id,
      legacyRow: row,
      targetTable: 'sample_machine_details',
      sourceColumns: const ['setterNo', 'hatcherNo'],
    );
    await _verifyLegacyStationSampleDetailCopied(
      db,
      id: id,
      legacyRow: row,
      targetTable: 'sample_batch_details',
      sourceColumns: const [
        'batchNo',
        'hatchNo',
        'storageDays',
        'incubationDay',
      ],
    );
    await _verifyLegacyStationSampleDetailCopied(
      db,
      id: id,
      legacyRow: row,
      targetTable: 'sample_timing_details',
      sourceColumns: const ['eggProductionDate', 'settingDate', 'hatchDate'],
    );
  }
}

Future<void> _verifyLegacyStationSampleDetailCopied(
  DatabaseExecutor db, {
  required String id,
  required Map<String, Object?> legacyRow,
  required String targetTable,
  required List<String> sourceColumns,
}) async {
  final detailWasPresent = sourceColumns.any(
    (column) => legacyRow.containsKey(column) && legacyRow[column] != null,
  );
  if (!detailWasPresent) return;
  final count = Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM $targetTable WHERE sampleRecordId = ?',
      [id],
    ),
  );
  if (count != 1) {
    throw StateError(
      'Cannot drop station_samples: $targetTable for sample $id was not copied safely.',
    );
  }
}

String _legacyStationSampleSectorSql(String stationTypeExpr) {
  return """
CASE $stationTypeExpr
WHEN 'egg' THEN '${StationSampleModel.sectorEggQuality}'
WHEN 'chicks' THEN '${StationSampleModel.sectorChickQuality}'
WHEN 'hatch_analysis_egg_breakouts' THEN '${StationSampleModel.sectorHatchBreakout}'
WHEN 'setters' THEN '${StationSampleModel.sectorSetterOptimizing}'
WHEN 'hatchers' THEN '${StationSampleModel.sectorHatcherOptimizing}'
ELSE '${StationSampleModel.sectorDefault}'
END
""";
}

String _legacyStationSampleKindSql(
  String comparisonTypeExpr,
  Set<String> columns,
) {
  final housePresent = _legacyAnyPresentSql(columns, ['houseNo', 'houseLabel']);
  final machinePresent = _legacyAnyPresentSql(columns, [
    'setterNo',
    'hatcherNo',
  ]);
  final batchPresent = _legacyAnyPresentSql(columns, [
    'batchNo',
    'hatchNo',
    'storageDays',
    'incubationDay',
  ]);
  return """
CASE
WHEN $comparisonTypeExpr = '${StationSampleModel.comparisonTypeHouse}' THEN '${StationSampleModel.sampleKindHouse}'
WHEN $comparisonTypeExpr = '${StationSampleModel.comparisonTypeMachine}' THEN '${StationSampleModel.sampleKindMachine}'
WHEN $comparisonTypeExpr = '${StationSampleModel.comparisonTypeTray}' THEN '${StationSampleModel.sampleKindTray}'
WHEN $comparisonTypeExpr IN (
  '${StationSampleModel.comparisonTypeBatch}',
  '${StationSampleModel.comparisonTypeProductionDate}'
) THEN '${StationSampleModel.sampleKindBatch}'
WHEN $machinePresent THEN '${StationSampleModel.sampleKindMachine}'
WHEN $housePresent THEN '${StationSampleModel.sampleKindHouse}'
WHEN $batchPresent THEN '${StationSampleModel.sampleKindBatch}'
ELSE '${StationSampleModel.sampleKindPooled}'
END
""";
}

String _legacyAnyPresentSql(Set<String> columns, List<String> candidates) {
  final available = candidates.where(columns.contains).toList(growable: false);
  if (available.isEmpty) return '0';
  return available
      .map((column) => '${_quoteSqlIdentifier(column)} IS NOT NULL')
      .join(' OR ');
}

Future<void> _rebuildAuditsTableWithoutObsoleteGoveeColumns(Database db) async {
  final tableInfo = await db.rawQuery("PRAGMA table_info('audits')");
  final existingNames = _columnNames(tableInfo);
  if (!existingNames.any(_obsoleteGoveeAuditColumns.contains)) return;
  final retainedColumns = tableInfo.where((column) {
    final name = column['name']?.toString();
    return name != null && !_obsoleteGoveeAuditColumns.contains(name);
  }).toList();
  final columnDefinitions = <String>[];
  final insertColumns = <String>[];
  final selectExpressions = <String>[];
  for (final column in retainedColumns) {
    final name = column['name']?.toString();
    if (name == null || name.isEmpty) continue;
    final quotedName = _quoteSqlIdentifier(name);
    columnDefinitions.add(_columnDefinitionForRebuild(column));
    insertColumns.add(quotedName);
    selectExpressions.add(quotedName);
  }
  final foreignKeyRows = await db.rawQuery('PRAGMA foreign_keys');
  final foreignKeysEnabled =
      foreignKeyRows.isNotEmpty &&
      _pragmaInt(foreignKeyRows.first['foreign_keys']) == 1;
  if (foreignKeysEnabled) {
    await db.execute('PRAGMA foreign_keys = OFF');
  }
  try {
    await db.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS "$_auditsRebuildTable"');
      await txn.execute('''
CREATE TABLE "$_auditsRebuildTable" (
${columnDefinitions.join(',\n  ')}
)''');
      await txn.execute(
        'INSERT INTO "$_auditsRebuildTable" '
        '(${insertColumns.join(', ')}) '
        'SELECT ${selectExpressions.join(', ')} FROM audits',
      );
      await txn.execute('DROP TABLE audits');
      await txn.execute('ALTER TABLE "$_auditsRebuildTable" RENAME TO audits');
    });
  } finally {
    if (foreignKeysEnabled) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
  await _createOperationalIndexes(db);
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_audits_unique ON audits (customerId, flockId, date, auditType, hatchNumber, setterId, hatcherId)',
  );
}

Map<String, Object?> _migrateGoveeDailyRow(Map<String, Object?> row) {
  final place = _migratedGoveePlaceName('${row['place'] ?? ''}');
  final stationKey = '${row['stationKey'] ?? ''}'.trim();
  return {
    'id': row['id'],
    'customerId': row['customerId'],
    'hatcheryId': row['hatcheryId'],
    'stationKey': stationKey.isEmpty
        ? _goveeStationKeyForPlaceName(place)
        : stationKey,
    'place': place,
    'machineId': row['machineId'] ?? '',
    'captureDate': row['captureDate'],
    'startedAt': row['startedAt'] ?? row['createdAt'],
    'endedAt': row['endedAt'] ?? row['updatedAt'],
    'deviceId': row['deviceId'],
    'deviceName': row['deviceName'],
    'status': row['status'] ?? 'completed',
    'tempAvg': row['tempAvg'],
    'tempMin': row['tempMin'],
    'tempMax': row['tempMax'],
    'tempSd': row['tempSd'],
    'tempCvPct': row['tempCvPct'],
    'rhAvg': row['rhAvg'],
    'rhMin': row['rhMin'],
    'rhMax': row['rhMax'],
    'rhSd': row['rhSd'],
    'rhCvPct': row['rhCvPct'],
    'readingCount': row['readingCount'] ?? 0,
    'chartPointsJson': row['chartPointsJson'] ?? '[]',
    'createdAt': row['createdAt'],
    'updatedAt': row['updatedAt'],
  };
}

String _migratedGoveePlaceName(String place) {
  return switch (place) {
    'incubatorRoom' => 'setterRoom',
    'insideIncubator' => 'insideSetter',
    _ => place,
  };
}

String _goveeStationKeyForPlaceName(String place) {
  return switch (place) {
    'eggStorageRoom' => 'egg',
    'chickHoldingArea' => 'chicks',
    'setterRoom' || 'insideSetter' => 'setters',
    'hatcherRoom' || 'insideHatcher' => 'hatchers',
    _ => '',
  };
}

Future<void> _normalizeGoveePlaceValues(Database db) async {
  if (await _tableExists(db, 'govee_daily_captures')) {
    final columns = _columnNames(
      await db.rawQuery("PRAGMA table_info('govee_daily_captures')"),
    );
    final assignments = <String>["place = ${_migratedGoveePlaceSql('place')}"];
    if (columns.contains('stationKey')) {
      assignments.add("""
stationKey = COALESCE(
            NULLIF(TRIM(stationKey), ''),
            ${_goveeStationKeySql(_migratedGoveePlaceSql('place'))}
          )""");
    }
    if (columns.contains('machineId')) {
      assignments.add("machineId = COALESCE(machineId, '')");
    }
    await db.execute("""
      UPDATE govee_daily_captures
      SET ${assignments.join(',\n            ')}
    """);
  }
  if (await _tableExists(db, 'temperature_sessions')) {
    await db.execute("""
      UPDATE temperature_sessions
      SET activePlace = ${_migratedGoveePlaceSql('activePlace')}
      WHERE activePlace IN ('incubatorRoom', 'insideIncubator')
    """);
  }
  if (await _tableExists(db, 'temperature_readings')) {
    await db.execute("""
      UPDATE temperature_readings
      SET place = ${_migratedGoveePlaceSql('place')}
      WHERE place IN ('incubatorRoom', 'insideIncubator')
    """);
  }
}

Future<bool> _tableExists(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}

String _migratedGoveePlaceSql(String expression) {
  return """
CASE $expression
WHEN 'incubatorRoom' THEN 'setterRoom'
WHEN 'insideIncubator' THEN 'insideSetter'
ELSE $expression
END
""";
}

String _goveeStationKeySql(String placeExpression) {
  return """
CASE $placeExpression
WHEN 'eggStorageRoom' THEN 'egg'
WHEN 'chickHoldingArea' THEN 'chicks'
WHEN 'setterRoom' THEN 'setters'
WHEN 'insideSetter' THEN 'setters'
WHEN 'hatcherRoom' THEN 'hatchers'
WHEN 'insideHatcher' THEN 'hatchers'
ELSE ''
END
""";
}

Future<void> _renameStationIdentityValues(Database db) async {
  await db.execute("""
    UPDATE OR IGNORE audits
    SET auditType = CASE auditType
      WHEN 'Egg Storage' THEN 'Egg'
      WHEN 'Egg Storage & Handling' THEN 'Egg'
      WHEN 'Chick Quality' THEN 'Chicks'
      WHEN 'Hatch Analysis' THEN 'Hatch Analysis & Egg Breakouts'
      WHEN 'Setter Optimizing' THEN 'Setters'
      WHEN 'Hatcher Optimizing' THEN 'Hatchers'
      ELSE auditType
    END
    WHERE auditType IN (
      'Egg Storage',
      'Egg Storage & Handling',
      'Chick Quality',
      'Hatch Analysis',
      'Setter Optimizing',
      'Hatcher Optimizing'
    )
  """);
  if (await _tableExists(db, 'station_samples')) {
    await db.execute("""
    UPDATE station_samples
    SET stationType = CASE stationType
      WHEN 'Egg Storage' THEN 'Egg'
      WHEN 'Egg Storage & Handling' THEN 'Egg'
      WHEN 'Chick Quality' THEN 'Chicks'
      WHEN 'Hatch Analysis' THEN 'Hatch Analysis & Egg Breakouts'
      WHEN 'Setter Optimizing' THEN 'Setters'
      WHEN 'Hatcher Optimizing' THEN 'Hatchers'
      ELSE stationType
    END
    WHERE stationType IN (
      'Egg Storage',
      'Egg Storage & Handling',
      'Chick Quality',
      'Hatch Analysis',
      'Setter Optimizing',
      'Hatcher Optimizing'
    )
  """);
  }
  if (await _tableExists(db, 'sample_records')) {
    await db.execute("""
    UPDATE sample_records
    SET stationType = CASE stationType
      WHEN 'Egg Storage' THEN 'Egg'
      WHEN 'Egg Storage & Handling' THEN 'Egg'
      WHEN 'Chick Quality' THEN 'Chicks'
      WHEN 'Hatch Analysis' THEN 'Hatch Analysis & Egg Breakouts'
      WHEN 'Setter Optimizing' THEN 'Setters'
      WHEN 'Hatcher Optimizing' THEN 'Hatchers'
      ELSE stationType
    END
    WHERE stationType IN (
      'Egg Storage',
      'Egg Storage & Handling',
      'Chick Quality',
      'Hatch Analysis',
      'Setter Optimizing',
      'Hatcher Optimizing'
    )
  """);
  }
  for (final column in const [
    'selectedStationKeys',
    'stationsCompleted',
    'scorecardJson',
    'findingsJson',
  ]) {
    await _replaceAuditSessionTextColumn(db, column);
  }
}

Future<void> _replaceAuditSessionTextColumn(Database db, String column) async {
  await db.execute("""
    UPDATE audit_sessions
    SET $column = replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(
                      replace($column,
                        '"egg_storage"', '"egg"'
                      ),
                      '"chick_quality"', '"chicks"'
                    ),
                    '"hatch_analysis"', '"hatch_analysis_egg_breakouts"'
                  ),
                  '"setter_optimizing"', '"setters"'
                ),
                '"hatcher_optimizing"', '"hatchers"'
              ),
              '"Egg Storage"', '"Egg"'
            ),
            '"Chick Quality"', '"Chicks"'
          ),
          '"Hatch Analysis"', '"Hatch Analysis & Egg Breakouts"'
        ),
        '"Setter Optimizing"', '"Setters"'
      ),
      '"Hatcher Optimizing"', '"Hatchers"'
    )
    WHERE $column IS NOT NULL
  """);
}

Future<void> _addStationSampleHouseColumns(
  DatabaseExecutor db,
  Set<String> columnNames,
) async {
  if (!columnNames.contains('houseNo')) {
    await db.execute('ALTER TABLE station_samples ADD COLUMN houseNo TEXT');
  }
  if (!columnNames.contains('houseLabel')) {
    await db.execute('ALTER TABLE station_samples ADD COLUMN houseLabel TEXT');
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
  await _createLegacyStationSamplesIndexes(db);
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
    await _upsertSeedById(db, 'customers', seed);
  }
  for (final seed in kDummyFlockSeeds) {
    await _upsertSeedById(db, 'flocks', seed);
  }
  for (final seed in kDummyAuditSeeds) {
    await _upsertSeedById(db, 'audits', seed);
  }
}

Future<void> _upsertSeedById(
  Database db,
  String table,
  Map<String, dynamic> seed,
) async {
  final inserted = await db.insert(
    table,
    seed,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
  if (inserted != 0) return;
  await db.update(table, seed, where: 'id = ?', whereArgs: [seed['id']]);
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
  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('bmk_egg_breakout')"),
  );
  if (!columns.containsAll({
    'earlyDeadPct',
    'midBlackEyePct',
    'internalPipPct',
    'externalPipPct',
    'midDeadPct',
    'blackEyePct',
    'pippedInternalPct',
    'pippedExternalPct',
  })) {
    return;
  }
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
