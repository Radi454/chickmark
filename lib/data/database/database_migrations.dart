part of 'database_helper.dart';

Future<void> _applyV18Upgrade(Database db) async {}

Future<void> _applyV19Upgrade(Database db) async {}

Future<void> _applyV20Upgrade(Database db) async {}

Future<void> _applyV21Upgrade(Database db) async {}

Future<void> _applyV22Upgrade(Database db) async {}

Future<void> _applyV23Upgrade(Database db) async {}

Future<void> _applyV24Upgrade(Database db) async {}

Future<void> _applyV25Upgrade(Database db) async {}

Future<void> _applyV26Upgrade(Database db) async {}

Future<void> _applyV27Upgrade(Database db) async {}

Future<void> _applyV28Upgrade(Database db) async {}

Future<void> _applyV29Upgrade(Database db) async {}

Future<void> _applyV30Upgrade(Database db) async {}

Future<void> _applyV31Upgrade(Database db) async {}

Future<void> _applyV32Upgrade(Database db) async {}

Future<void> _applyV33Upgrade(Database db) async {}

Future<void> _applyV34Upgrade(Database db) async {}

Future<void> _applyV35Upgrade(Database db) async {}

Future<void> _applyV46Upgrade(Database db) async {
  await _createDashboardActionTable(db);
}

Future<void> _applyV47Upgrade(Database db) async {
  await _createLabAnalysisTables(db);
}

Future<void> _applyV48Upgrade(Database db) async {
  await _ensureColumns(db, 'lab_analysis_reports', const [
    'reportFileName TEXT',
    'reportFilePath TEXT',
    'reportFileRemotePath TEXT',
  ]);
}

Future<void> _applyV51Upgrade(Database db) async {
  if (await _tableExists(db, 'flocks')) {
    await _ensureColumns(db, 'flocks', const [
      'farmId TEXT',
      'sectorKey TEXT',
      "sexProfile TEXT NOT NULL DEFAULT 'as_hatched'",
      'targetProfileId TEXT',
      'productionPhase TEXT',
      'updatedAt TEXT',
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'syncError TEXT',
    ]);
  }
  await _createPerformanceMonitoringTables(db);

  // Existing hatchery-audit flocks are safely classifiable as Breeder. Other
  // legacy flocks remain unclassified until a user assigns their sector.
  if (await _tableExists(db, 'flocks') &&
      await _tableExists(db, 'audit_sessions')) {
    await db.execute('''
      UPDATE flocks
      SET sectorKey = 'breeder'
      WHERE sectorKey IS NULL
        AND EXISTS (
          SELECT 1
          FROM audit_sessions
          WHERE audit_sessions.flockId = flocks.id
            AND audit_sessions.hatcheryId IS NOT NULL
        )
    ''');
  }
}

Future<void> _applyV52Upgrade(Database db) async {
  await _createHatcheryAgentTables(db);
}

Future<void> _applyV53Upgrade(Database db) async {
  await _createAgentIntakeTables(db);
}

Future<void> _applyV54Upgrade(Database db) async {
  // A released development line also used schema version 53 for unrelated
  // flock changes. Re-establish the additive v52/v53 agent prerequisites
  // before v54 creates indexes and guards that reference them. Both builders
  // are idempotent, so databases that already followed the agent migration
  // path keep their existing rows unchanged.
  await _createHatcheryAgentTables(db);
  await _createAgentIntakeTables(db);

  if (await _tableExists(db, 'telegram_staff_links')) {
    await _ensureColumns(db, 'telegram_staff_links', const [
      "accessRole TEXT NOT NULL DEFAULT 'customer'",
      'customerId TEXT',
    ]);
    // Approved links before v54 belonged to the administrator who configured
    // the bot. Preserve that access explicitly instead of assigning a random
    // customer or invalidating the link.
    await db.execute('''
      UPDATE telegram_staff_links
      SET accessRole = 'admin', customerId = NULL
      WHERE status = 'allowed' AND customerId IS NULL
    ''');
  }
  if (await _tableExists(db, 'agent_intake_sessions')) {
    await _ensureColumns(db, 'agent_intake_sessions', const [
      'visitId TEXT',
      'rowVersion INTEGER NOT NULL DEFAULT 1',
      'lastToolEventId TEXT',
    ]);
  }

  // Divergent development lines shipped older shapes of the harness tables
  // without columns this upgrade's indexes and backfills reference. CREATE
  // TABLE IF NOT EXISTS keeps the old shape, so add the referenced columns
  // first; the v56 shadow rebuild later normalizes the full definitions.
  if (await _tableExists(db, 'agent_conversations')) {
    await _ensureColumns(db, 'agent_conversations', const [
      'contextEpoch INTEGER NOT NULL DEFAULT 1',
      'selectedCustomerId TEXT',
      'selectedFlockId TEXT',
      'selectedAuditId TEXT',
      'contextUpdatedAt TEXT',
      'pendingActionJson TEXT',
      'activeVisitId TEXT',
    ]);
  }
  if (await _tableExists(db, 'agent_conversation_turns')) {
    await _ensureColumns(db, 'agent_conversation_turns', const [
      'turnIndex INTEGER',
      'contextEpoch INTEGER NOT NULL DEFAULT 1',
    ]);
  }
  if (await _tableExists(db, 'agent_tool_events')) {
    await _ensureColumns(db, 'agent_tool_events', const [
      'toolSequence INTEGER',
    ]);
  }

  // Create the graph before its guards so incomplete legacy rows can be
  // preserved and grouped. Every new write is guarded after the backfill.
  await _createUnifiedAgentHarnessTables(db, createGuards: false);

  if (await _tableExists(db, 'agent_intake_sessions')) {
    await db.execute('''
      INSERT OR IGNORE INTO agent_conversations (
        id,
        staffLinkId,
        telegramChatId,
        stateVersion,
        createdAt,
        updatedAt,
        syncStatus
      )
      SELECT
        'legacy-conversation-' || staffLinkId || '-' || telegramChatId,
        staffLinkId,
        telegramChatId,
        1,
        MIN(createdAt),
        MAX(updatedAt),
        'synced'
      FROM agent_intake_sessions
      GROUP BY staffLinkId, telegramChatId
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO agent_intake_visits (
        id,
        conversationId,
        customerId,
        flockId,
        hatcheryId,
        auditDate,
        state,
        approvedSessionId,
        createdAt,
        updatedAt,
        syncStatus
      )
      SELECT
        'legacy-visit-' || intake.id,
        conversation.id,
        intake.customerId,
        intake.flockId,
        intake.hatcheryId,
        intake.auditDate,
        CASE
          WHEN intake.state = 'approved' THEN 'completed'
          WHEN intake.state IN ('rejected', 'cancelled') THEN 'cancelled'
          WHEN intake.state = 'awaiting_admin_review'
            THEN 'awaiting_admin_review'
          ELSE 'collecting'
        END,
        intake.approvedSessionId,
        intake.createdAt,
        intake.updatedAt,
        'synced'
      FROM agent_intake_sessions intake
      INNER JOIN agent_conversations conversation
        ON conversation.staffLinkId = intake.staffLinkId
       AND conversation.telegramChatId = intake.telegramChatId
    ''');
    await db.execute('''
      UPDATE agent_intake_sessions
      SET visitId = 'legacy-visit-' || id, rowVersion = 1
      WHERE visitId IS NULL
    ''');
    await db.execute('''
      UPDATE agent_conversations
      SET activeVisitId = (
        SELECT visit.id
        FROM agent_intake_visits visit
        WHERE visit.conversationId = agent_conversations.id
          AND visit.state IN (
            'selecting_station',
            'collecting',
            'awaiting_admin_review'
          )
        ORDER BY visit.updatedAt DESC, visit.id DESC
        LIMIT 1
      )
    ''');
  }

  await _createUnifiedAgentHarnessGuards(db);
}

Future<void> _applyV55Upgrade(Database db) async {
  if (!await _tableExists(db, 'agent_intake_sessions')) {
    await _createAgentIntakeTables(db);
    return;
  }

  for (final trigger in const [
    'trg_telegram_staff_links_scope_insert',
    'trg_telegram_staff_links_scope_update',
    'trg_agent_intake_visit_scope_insert',
    'trg_agent_intake_visit_scope_update',
    'trg_agent_intake_summary_immutable',
    'trg_agent_tool_events_immutable',
    'trg_agent_tool_events_delete_immutable',
  ]) {
    await db.execute('DROP TRIGGER IF EXISTS $trigger');
  }
  await db.execute('DROP TABLE IF EXISTS agent_intake_sessions_v55');
  await _createAgentIntakeSessionsTable(db, 'agent_intake_sessions_v55');
  const columns = '''
    id,
    staffLinkId,
    telegramChatId,
    schemaKey,
    schemaVersion,
    state,
    language,
    customerId,
    customerName,
    flockId,
    flockName,
    hatcheryId,
    hatcheryName,
    auditDate,
    scope,
    setterIdentity,
    hatcherIdentity,
    workingValuesJson,
    pendingClarificationJson,
    summaryVersion,
    summarySnapshotJson,
    userConfirmedAt,
    visitId,
    rowVersion,
    lastToolEventId,
    approvedSessionId,
    approvedPanelRowId,
    reviewedBy,
    reviewedAt,
    rejectionReason,
    createdAt,
    updatedAt,
    syncStatus,
    dirtyAt,
    lastSyncedAt,
    syncError
  ''';
  await db.execute('''
    INSERT INTO agent_intake_sessions_v55 ($columns)
    SELECT $columns FROM agent_intake_sessions
  ''');
  await db.execute('DROP TABLE agent_intake_sessions');
  await db.execute(
    'ALTER TABLE agent_intake_sessions_v55 RENAME TO agent_intake_sessions',
  );
  await _createAgentIntakeTables(db);
  await _createUnifiedAgentHarnessTables(db);
}

Future<void> _applyV56Upgrade(Database db) async {
  if (await _tableExists(db, 'agent_conversations')) {
    await _ensureColumns(db, 'agent_conversations', const [
      'contextEpoch INTEGER NOT NULL DEFAULT 1',
      'selectedCustomerId TEXT',
      'selectedFlockId TEXT',
      'selectedAuditId TEXT',
      'contextUpdatedAt TEXT',
    ]);
  }
  if (await _tableExists(db, 'agent_conversation_turns')) {
    await _ensureColumns(db, 'agent_conversation_turns', const [
      'turnIndex INTEGER',
      'contextEpoch INTEGER NOT NULL DEFAULT 1',
      'provider TEXT',
      'providerResponseId TEXT',
      'replyToTurnId TEXT',
    ]);
    await db.execute('''
      WITH ranked AS (
        SELECT
          id,
          ROW_NUMBER() OVER (
            PARTITION BY conversationId, direction
            ORDER BY createdAt, id
          ) AS sequence
        FROM agent_conversation_turns
      )
      UPDATE agent_conversation_turns
      SET turnIndex = (
        SELECT ranked.sequence
        FROM ranked
        WHERE ranked.id = agent_conversation_turns.id
      )
      WHERE turnIndex IS NULL
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_conversation_turns_order '
      'ON agent_conversation_turns '
      '(conversationId, contextEpoch, direction, turnIndex) '
      'WHERE turnIndex IS NOT NULL',
    );
  }
  if (await _tableExists(db, 'agent_tool_events')) {
    await _ensureColumns(db, 'agent_tool_events', const [
      'toolSequence INTEGER',
    ]);
    // Tool evidence is immutable during ordinary app use. The schema upgrade
    // temporarily lifts only those guards while it adds deterministic ordering
    // metadata, then restores them in the same database transaction.
    await db.execute('DROP TRIGGER IF EXISTS trg_agent_tool_events_immutable');
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_agent_tool_events_delete_immutable',
    );
    await db.execute('''
      WITH ranked AS (
        SELECT
          id,
          ROW_NUMBER() OVER (
            PARTITION BY conversationTurnId
            ORDER BY createdAt, id
          ) AS sequence
        FROM agent_tool_events
      )
      UPDATE agent_tool_events
      SET toolSequence = (
        SELECT ranked.sequence
        FROM ranked
        WHERE ranked.id = agent_tool_events.id
      )
      WHERE toolSequence IS NULL
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tool_events_sequence '
      'ON agent_tool_events (conversationTurnId, toolSequence) '
      'WHERE toolSequence IS NOT NULL',
    );
  }

  await _rebuildV56AgentIntegrityTables(db);
  await _createUnifiedAgentHarnessGuards(db);

  if (!await _tableExists(db, 'flocks')) return;
  if (await _tableExists(db, 'farms')) {
    await db.execute('''
      UPDATE flocks
      SET sectorKey = (
        SELECT farms.sectorKey
        FROM farms
        WHERE farms.id = flocks.farmId
          AND farms.customerId = flocks.customerId
      )
      WHERE sectorKey IS NULL
        AND farmId IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM farms
          WHERE farms.id = flocks.farmId
            AND farms.customerId = flocks.customerId
            AND farms.sectorKey IS NOT NULL
        )
    ''');
  }
  if (await _tableExists(db, 'audit_sessions')) {
    await db.execute('''
      UPDATE flocks
      SET sectorKey = 'breeder'
      WHERE sectorKey IS NULL
        AND EXISTS (
          SELECT 1
          FROM audit_sessions
          WHERE audit_sessions.flockId = flocks.id
            AND audit_sessions.customerId = flocks.customerId
            AND audit_sessions.hatcheryId IS NOT NULL
        )
    ''');
  }
  if (await _tableExists(db, 'customer_sectors')) {
    await db.execute('''
      UPDATE flocks
      SET sectorKey = (
        SELECT MIN(customer_sectors.sectorKey)
        FROM customer_sectors
        WHERE customer_sectors.customerId = flocks.customerId
          AND customer_sectors.isActive = 1
      )
      WHERE sectorKey IS NULL
        AND (
          SELECT COUNT(DISTINCT customer_sectors.sectorKey)
          FROM customer_sectors
          WHERE customer_sectors.customerId = flocks.customerId
            AND customer_sectors.isActive = 1
        ) = 1
    ''');
  }
}

Future<void> _applyV57Upgrade(Database db) async {
  if (await _tableExists(db, 'customers')) {
    await _ensureColumns(db, 'customers', const [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ]);
  }
  if (await _tableExists(db, 'hatcheries')) {
    await _ensureColumns(db, 'hatcheries', const [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ]);
  }
  if (await _tableExists(db, 'flocks')) {
    await _ensureColumns(db, 'flocks', const ['lastSyncedAt TEXT']);
  }
}

Future<void> _applyV58Upgrade(Database db) async {
  if (await _tableExists(db, 'bmk_operational_standards')) {
    await _ensureColumns(db, 'bmk_operational_standards', const [
      "syncStatus TEXT NOT NULL DEFAULT 'pending'",
      'dirtyAt TEXT',
      'lastSyncedAt TEXT',
      'syncError TEXT',
    ]);
    // Seeded reference rows must not look dirty (they already exist in the
    // cloud), so start from a clean slate...
    await db.update('bmk_operational_standards', {'syncStatus': 'synced'});
    // ...then re-dirty anything a user actually touched before this table
    // joined the sync path. `kBmkOperationalStandardSeeds` carries no
    // `updatedAt` and `_backfillOperationalBmkSeedSources` never writes one,
    // so a non-null `updatedAt` means the row went through
    // `BmkRepository.upsertOperationalStandard` — i.e. a user edit. Any
    // hatchery-scoped row is user-created by definition (every seed is
    // global). Without this, pre-existing edits would sit permanently
    // `synced` and never push.
    final columns = _columnNames(
      await db.rawQuery("PRAGMA table_info('bmk_operational_standards')"),
    );
    final userEditedWhere = columns.contains('updatedAt')
        ? 'updatedAt IS NOT NULL OR hatcheryId IS NOT NULL'
        : 'hatcheryId IS NOT NULL';
    await db.update('bmk_operational_standards', {
      'syncStatus': 'pending',
      'dirtyAt': DateTime.now().toIso8601String(),
    }, where: userEditedWhere);
  }
}

Future<void> _applyV59Upgrade(Database db) async {
  await _rebuildV59TelegramStaffLinksTable(db);
}

/// `telegram_staff_links` was created when Telegram was the only channel, so
/// `telegramUserId` was `NOT NULL UNIQUE`. The agent now also serves in-app
/// staff (`channel = 'app'`), whose cloud rows carry no Telegram identity at
/// all. Those rows failed the NOT NULL constraint on pull — and because the
/// pull upsert uses `INSERT OR IGNORE`, which SQLite applies to NOT NULL
/// violations, they were dropped without an error. Every `agent_conversations`
/// row referencing an app link then failed its foreign key (`OR IGNORE` does
/// not suppress FK errors), which aborted the whole conversation/turn/tool
/// event pull.
///
/// SQLite cannot relax NOT NULL or drop a column-level UNIQUE in place, so the
/// table is rebuilt.
Future<void> _rebuildV59TelegramStaffLinksTable(Database db) async {
  if (!await _tableExists(db, 'telegram_staff_links')) return;

  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('telegram_staff_links')"),
  );
  // Columns carried over from the old table. `channel` and `appUserId` may
  // already exist on databases that took the surgical-repair path first.
  const carriedColumns = [
    'id',
    'telegramUserId',
    'telegramChatId',
    'displayName',
    'username',
    'status',
    'accessRole',
    'customerId',
    'invitedBy',
    'createdAt',
    'updatedAt',
    'syncStatus',
    'dirtyAt',
    'lastSyncedAt',
    'syncError',
  ];
  final copied = carriedColumns.where(columns.contains).toList();
  for (final optional in const ['channel', 'appUserId']) {
    if (columns.contains(optional)) copied.add(optional);
  }
  if (!copied.contains('id')) return;
  final copiedList = copied.join(', ');

  final foreignKeysRow = await db.rawQuery('PRAGMA foreign_keys');
  final restoreForeignKeys = foreignKeysRow.single.values.first == 1;
  if (restoreForeignKeys) {
    // The application upgrade path already disabled foreign keys in
    // onConfigure; this keeps the test hook safe when called directly.
    await db.execute('PRAGMA foreign_keys = OFF');
  }
  // Modern ALTER TABLE semantics so RENAME rewrites references rather than
  // leaving them pointing at the dropped shadow name. See the v56 rebuild for
  // why Apple's system SQLite needs this made explicit.
  await db.execute('PRAGMA legacy_alter_table = OFF');

  try {
    const shadow = 'telegram_staff_links_v59';
    // SQLite reparses *every* trigger during ALTER TABLE, not just the ones
    // bound to the renamed table. Sparse legacy databases can be missing a
    // table some other guard references (`flocks`, say), which makes the
    // RENAME fail on an unrelated trigger. Drop the whole unified-agent guard
    // set for the duration; onOpen's surgical repair recreates the rest once
    // the table graph is whole again.
    for (final trigger in const [
      'trg_telegram_staff_links_scope_insert',
      'trg_telegram_staff_links_scope_update',
      'trg_agent_intake_visit_scope_insert',
      'trg_agent_intake_visit_scope_update',
      'trg_agent_intake_summary_immutable',
      'trg_agent_tool_events_immutable',
      'trg_agent_tool_events_delete_immutable',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    await db.execute('DROP TABLE IF EXISTS $shadow');
    await _createTelegramStaffLinksTable(db, tableName: shadow);

    await db.execute('''
      INSERT INTO $shadow ($copiedList)
      SELECT $copiedList FROM telegram_staff_links
    ''');
    // Rows that predate the column default their channel from the identity
    // they actually carry rather than blanket 'telegram'.
    if (copied.contains('appUserId')) {
      await db.execute('''
        UPDATE $shadow SET channel = 'app'
        WHERE appUserId IS NOT NULL AND telegramUserId IS NULL
      ''');
    }

    final sourceCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM telegram_staff_links'),
    );
    final shadowCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $shadow'),
    );
    if (sourceCount != shadowCount) {
      throw StateError('v59 telegram_staff_links rebuild row-count mismatch');
    }

    await db.execute('DROP TABLE telegram_staff_links');
    await db.execute('ALTER TABLE $shadow RENAME TO telegram_staff_links');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_telegram_staff_links_customer '
      'ON telegram_staff_links (customerId) WHERE customerId IS NOT NULL',
    );
    await _createTelegramStaffLinkIndexes(db);
    await _createTelegramStaffLinkGuards(db);

    final violations = await db.rawQuery(
      'PRAGMA foreign_key_check(telegram_staff_links)',
    );
    if (violations.isNotEmpty) {
      throw StateError(
        'v59 telegram_staff_links rebuild found foreign-key violations',
      );
    }
  } finally {
    if (restoreForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

/// Mirrors `supabase/migrations/20260818090000_pip_conversation_titles.sql`:
/// `agent_conversations.title` backs the app door's multi-conversation list
/// (app-hatchery-agent/index.ts), holding a short title derived from the
/// caller's first message in a conversation. NULL means "not yet titled",
/// including every conversation that predates this column.
Future<void> _applyV60Upgrade(Database db) async {
  if (!await _tableExists(db, 'agent_conversations')) return;
  await _ensureColumns(db, 'agent_conversations', const ['title TEXT']);
}

/// v61 adds the panel sample-metadata and domain columns. They are nullable
/// and land through the same reconciliation pass that runs on every open, so
/// this hop only has to make sure the pass runs before the app reads them.
Future<void> _applyV61Upgrade(Database db) async {
  await ensurePanelSampleSchemaColumns(db);
}

/// v62 adds visual egg grading: summary columns on the egg_quality panel
/// (handled by the panel reconciliation pass), plus the defect catalogue and
/// the per-sample defect-count child table.
Future<void> _applyV62Upgrade(Database db) async {
  await createEggGradingTables(db);
  await seedEggDefectTypes(db);
  await ensurePanelSampleSchemaColumns(db);
}

/// v63 repairs the two Phase 1 canonical-data defects without guessing:
/// explicitly Celsius-tagged chick CVT payloads become canonical Fahrenheit,
/// and panel dates that disagree with their parent session inherit that
/// session's already-correct local calendar date.
Future<void> _applyV63Upgrade(Database db) async {
  await _canonicalizeTaggedCelsiusChickCvtRows(db);
  await _repairPanelDatesFromSessions(db);
  await _repairLegacyPanelPhotoReferences(db);
}

/// v64 gives the two Chick sample tables stable V2 logical identity without
/// changing their existing row ids or measurement payloads. Legacy duplicates
/// are retained as deterministic replicates instead of being merged.
Future<void> _applyV64Upgrade(Database db) async {
  await ensurePanelSampleSchemaColumns(db);
  for (final table in const ['chick_quality', 'chick_weights']) {
    if (!await _tableExists(db, table)) continue;
    await db.execute('DROP INDEX IF EXISTS idx_${table}_unique_row');
    await _backfillChickV2Identity(db, table);
    final missing = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $table WHERE sampleKey IS NULL OR sampleKey = ?',
        [''],
      ),
    );
    if ((missing ?? 0) != 0) {
      throw StateError('$table V2 identity backfill left $missing rows blank');
    }
    final duplicates = await db.rawQuery('''
      SELECT customerId, sampleKey, COUNT(*) AS rowCount
      FROM $table
      GROUP BY customerId, sampleKey
      HAVING COUNT(*) > 1
      LIMIT 1
    ''');
    if (duplicates.isNotEmpty) {
      throw StateError('$table V2 identity backfill produced duplicate keys');
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_sample_key '
      'ON $table (customerId, sampleKey) WHERE sampleKey IS NOT NULL',
    );
  }
}

/// v65 persists deterministic registry-owned quality classification for every
/// existing Chick parent row. Only the two additive quality columns change;
/// measurements, identity, provenance, and sync bookkeeping are preserved.
Future<void> _applyV65Upgrade(Database db) async {
  await ensurePanelSampleSchemaColumns(db);
  for (final table in const ['chick_quality', 'chick_weights']) {
    if (!await _tableExists(db, table)) continue;
    final rows = await db.query(table, orderBy: 'id');
    for (final row in rows) {
      final quality = ChickQualityClassifier.classifyRow(table, row);
      await db.update(
        table,
        {
          'qualityStatus': quality.status,
          'qualityFlags': quality.canonicalJson,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}

/// v66 adds normalized Chick observations without bulk-splitting combined
/// quality rows. Exact weight parents can be backfilled losslessly from their
/// raw list; malformed or absent JSON stays only in its preserved parent cache.
Future<void> _applyV66Upgrade(Database db) async {
  if (await _tableExists(db, 'photos')) {
    await _ensureColumns(db, 'photos', const ['observationId TEXT']);
  }
  await _repairDivergentV66ObservationTable(db);
  await _createChickQualityObservationTable(db);
  if (!await _tableExists(db, 'chick_weights')) return;
  final schema = AgentStationRegistry.require('chicks.weights', 1);
  final rows = await db.query(
    'chick_weights',
    where: 'domain = ?',
    whereArgs: ['chicks.weights'],
    orderBy: 'id',
  );
  for (final row in rows) {
    final sampleId = _v64Text(row['id']);
    final customerId = _v64Text(row['customerId']);
    final sessionId = _v64Text(row['sessionId']);
    if (sampleId == null || customerId == null || sessionId == null) continue;
    final values = AgentStationAdapter.fieldValuesFromLocalRow(schema, row);
    if (values['weightsJson'] is! List) continue;
    final observedAt = DateTime.tryParse(
      row['observedAt']?.toString() ?? row['createdAt']?.toString() ?? '',
    );
    if (observedAt == null) continue;
    final observations = ChickObservationCodec.extract(
      schema: schema,
      sampleId: sampleId,
      customerId: customerId,
      sessionId: sessionId,
      values: values,
      observedAt: observedAt,
      source: _v64Text(row['source']),
      // The cloud migration deliberately does not infer/backfill biological
      // evidence. Even a synced legacy parent needs these lossless children
      // pushed once.
      syncStatus: 'pending',
    );
    for (final observation in observations) {
      final map = observation.toMap();
      map['dirtyAt'] = DateTime.now().toUtc().toIso8601String();
      await db.insert(
        'chick_quality_observation',
        map,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}

Future<void> _repairDivergentV66ObservationTable(Database db) async {
  if (!await _tableExists(db, 'chick_quality_observation')) return;
  final columns = (await db.rawQuery(
    'PRAGMA table_info(chick_quality_observation)',
  )).map((row) => row['name']?.toString()).whereType<String>().toSet();
  const required = {
    'id',
    'sampleId',
    'customerId',
    'sessionId',
    'domain',
    'kind',
    'observationKey',
    'ordinal',
    'numericValue',
    'textValue',
    'unit',
    'qualityFlags',
    'source',
    'observedAt',
    'createdAt',
    'updatedAt',
    'syncStatus',
    'dirtyAt',
    'lastSyncedAt',
    'syncError',
  };
  final definition = await db.rawQuery(
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
    ['chick_quality_observation'],
  );
  final sql = definition.firstOrNull?['sql']?.toString() ?? '';
  final structurallyComplete =
      columns.containsAll(required) &&
      sql.contains("kind IN ('series', 'tally', 'ordinal')") &&
      sql.contains('(numericValue IS NOT NULL) <> (textValue IS NOT NULL)');
  if (structurallyComplete) return;

  const quarantine = 'chick_quality_observation_v66_quarantine';
  if (await _tableExists(db, quarantine)) {
    throw StateError(
      'Cannot repair divergent Chick observations: quarantine already exists',
    );
  }
  final legacyRows = await db.query('chick_quality_observation');
  for (final trigger in const [
    'trg_chick_quality_observation_owner_insert',
    'trg_chick_quality_observation_owner_update',
    'trg_chick_quality_observation_identity_update',
    'trg_chick_quality_observation_parent_quality_delete',
    'trg_chick_quality_observation_parent_weights_delete',
    'trg_chick_quality_observation_photo_unlink',
    'trg_photo_observation_owner_insert',
    'trg_photo_observation_owner_update',
  ]) {
    await db.execute('DROP TRIGGER IF EXISTS $trigger');
  }
  for (final index in const [
    'idx_chick_quality_observation_logical',
    'idx_chick_quality_observation_sample',
    'idx_chick_quality_observation_session',
    'idx_chick_quality_observation_sync',
  ]) {
    await db.execute('DROP INDEX IF EXISTS $index');
  }
  await db.execute(
    'ALTER TABLE chick_quality_observation RENAME TO $quarantine',
  );
  await _createChickQualityObservationTable(db);
  for (final legacy in legacyRows) {
    if (!required.every(legacy.containsKey)) continue;
    try {
      await db.insert('chick_quality_observation', {
        for (final key in required) key: legacy[key],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } on DatabaseException {
      // The original row remains byte-for-byte in the quarantine table.
    }
  }
}

Future<void> _backfillChickV2Identity(Database db, String table) async {
  final rows = await db.query(
    table,
    orderBy: 'customerId, sessionId, createdAt, id',
  );
  final prepared = <_V64ChickIdentityRow>[];
  for (final row in rows) {
    final scopeType = _v64ScopeType(table, row);
    final scopeKey =
        _v64Text(row['scopeKey']) ??
        ChickSampleIdentity.buildLegacyScopeKey(
          scopeType: scopeType,
          house: _v64Text(row['house']),
          setter: _v64Text(row['setter']),
          hatcher: _v64Text(row['hatcher']),
          trolley: _v64Text(row['trolley']),
          tray: _v64Text(row['tray']),
          position: _v64Text(row['position']),
        );
    final domain =
        _v64Text(row['domain']) ??
        (table == 'chick_weights'
            ? 'chicks.weights'
            : 'chicks.legacy_combined');
    final schemaVersion =
        row['schemaVersion'] is int && (row['schemaVersion'] as int) > 0
        ? row['schemaVersion']! as int
        : 1;
    prepared.add(
      _V64ChickIdentityRow(
        row: row,
        customerId: row['customerId']! as String,
        sessionId: row['sessionId']! as String,
        domain: domain,
        schemaVersion: schemaVersion,
        scopeType: scopeType,
        scopeKey: scopeKey,
      ),
    );
  }

  final usedReplicates = <String, Set<int>>{};
  final usedSampleKeys = <String, Set<String>>{};
  for (final item in prepared) {
    final replicate = item.row['replicate'];
    final sampleKey = _v64Text(item.row['sampleKey']);
    if (replicate is! int || replicate < 1 || sampleKey == null) continue;
    final expected = ChickSampleIdentity.buildSampleKey(
      domain: item.domain,
      sessionId: item.sessionId,
      scopeType: item.scopeType,
      scopeKey: item.scopeKey,
      replicate: replicate,
    );
    final group = item.groupKey;
    final customerKeys = usedSampleKeys.putIfAbsent(
      item.customerId,
      () => <String>{},
    );
    final groupReplicates = usedReplicates.putIfAbsent(group, () => <int>{});
    if (sampleKey != expected ||
        groupReplicates.contains(replicate) ||
        customerKeys.contains(sampleKey)) {
      continue;
    }
    groupReplicates.add(replicate);
    customerKeys.add(sampleKey);
    item.replicate = replicate;
    item.sampleKey = sampleKey;
  }

  final dirtyAt = DateTime.now().toUtc().toIso8601String();
  for (final item in prepared) {
    final groupReplicates = usedReplicates.putIfAbsent(
      item.groupKey,
      () => <int>{},
    );
    if (item.replicate == null) {
      final replicate = groupReplicates.isEmpty
          ? 1
          : groupReplicates.reduce((a, b) => a > b ? a : b) + 1;
      item.replicate = replicate;
      item.sampleKey = ChickSampleIdentity.buildSampleKey(
        domain: item.domain,
        sessionId: item.sessionId,
        scopeType: item.scopeType,
        scopeKey: item.scopeKey,
        replicate: replicate,
      );
      groupReplicates.add(replicate);
      usedSampleKeys
          .putIfAbsent(item.customerId, () => <String>{})
          .add(item.sampleKey!);
    }

    final updates = <String, Object?>{
      'domain': item.domain,
      'schemaVersion': item.schemaVersion,
      'scopeType': item.scopeType.dbValue,
      'scopeKey': item.scopeKey,
      'replicate': item.replicate,
      'sampleKey': item.sampleKey,
      'source': _v64Text(item.row['source']) ?? 'legacy',
      'captureMethod': _v64Text(item.row['captureMethod']) ?? 'unknown',
      'createdBy': item.row['createdBy'],
      'deviceId': item.row['deviceId'],
      'sourceRefId': item.row['sourceRefId'],
      'observedAt':
          item.row['observedAt'] ??
          item.row['createdAt'] ??
          item.row['updatedAt'],
    };
    final changed = updates.entries.any(
      (entry) => item.row[entry.key] != entry.value,
    );
    if (!changed) continue;
    updates.addAll({
      'syncStatus': 'pending',
      'dirtyAt': dirtyAt,
      'syncError': null,
    });
    await db.update(
      table,
      updates,
      where: 'id = ?',
      whereArgs: [item.row['id']],
    );
  }
}

SamplingLayer _v64ScopeType(String table, Map<String, Object?> row) {
  final stored = _v64Text(row['scopeType']);
  if (stored != null) {
    try {
      final parsed = SamplingLayer.fromDbValue(stored);
      if (PanelSampleSchema.byTable(table).allowedLayers.contains(parsed)) {
        return parsed;
      }
    } on ArgumentError {
      // Divergent/unknown legacy metadata is inferred only from explicit
      // hierarchy columns below; no identifier value is invented.
    }
  }
  if (table == 'chick_weights') {
    return _v64Text(row['house']) == null
        ? SamplingLayer.pool
        : SamplingLayer.house;
  }
  return _v64Text(row['setter']) == null && _v64Text(row['hatcher']) == null
      ? SamplingLayer.pool
      : SamplingLayer.setterHatcher;
}

String? _v64Text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _V64ChickIdentityRow {
  _V64ChickIdentityRow({
    required this.row,
    required this.customerId,
    required this.sessionId,
    required this.domain,
    required this.schemaVersion,
    required this.scopeType,
    required this.scopeKey,
  });

  final Map<String, Object?> row;
  final String customerId;
  final String sessionId;
  final String domain;
  final int schemaVersion;
  final SamplingLayer scopeType;
  final String scopeKey;
  int? replicate;
  String? sampleKey;

  String get groupKey =>
      jsonEncode([customerId, domain, sessionId, scopeType.dbValue, scopeKey]);
}

Future<void> _canonicalizeTaggedCelsiusChickCvtRows(Database db) async {
  if (!await _tableExists(db, 'chick_quality')) return;
  final rows = await db.query(
    'chick_quality',
    columns: [
      'id',
      'cvtReadingsJson',
      'cvtTopTemp',
      'cvtMiddleTemp',
      'cvtBottomTemp',
      'cvtAvgTemp',
    ],
  );
  final dirtyAt = DateTime.now().toUtc().toIso8601String();
  for (final row in rows) {
    final source = row['cvtReadingsJson'] as String?;
    if (source == null || source.trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    final unit = decoded['unit']?.toString().trim().toLowerCase();
    if (unit != 'c' && unit != '°c' && unit != 'celsius') continue;
    final rawReadings = decoded['readings'];
    if (rawReadings is! Map && rawReadings is! List) continue;

    final converted = _convertCelsiusJsonValues(rawReadings);
    final payload = Map<String, Object?>.from(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    )..['readings'] = converted;
    final updates = <String, Object?>{
      'cvtReadingsJson': jsonEncode(payload),
      'syncStatus': 'pending',
      'dirtyAt': dirtyAt,
      'syncError': null,
    };
    for (final column in const [
      'cvtTopTemp',
      'cvtMiddleTemp',
      'cvtBottomTemp',
      'cvtAvgTemp',
    ]) {
      final value = row[column];
      if (value is num) {
        updates[column] = _celsiusToFahrenheit(value.toDouble());
      }
    }
    await db.update(
      'chick_quality',
      updates,
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }
}

Object? _convertCelsiusJsonValues(Object? source) {
  if (source is Map) {
    return {
      for (final entry in source.entries)
        entry.key.toString(): _convertCelsiusJsonValues(entry.value),
    };
  }
  if (source is List) {
    return source.map(_convertCelsiusJsonValues).toList();
  }
  if (source is num) return _celsiusToFahrenheit(source.toDouble());
  if (source is String) {
    final parsed = double.tryParse(source);
    return parsed == null ? source : _celsiusToFahrenheit(parsed);
  }
  return source;
}

double _celsiusToFahrenheit(double value) => (value * 9 / 5) + 32;

Future<void> _repairPanelDatesFromSessions(Database db) async {
  if (!await _tableExists(db, 'audit_sessions')) return;
  final dirtyAt = DateTime.now().toUtc().toIso8601String();
  for (final panel in PanelSampleSchema.panels) {
    if (!await _tableExists(db, panel.tableName)) continue;
    await db.rawUpdate(
      '''
      UPDATE ${panel.tableName}
      SET date = (
            SELECT substr(audit_sessions.date, 1, 10)
            FROM audit_sessions
            WHERE audit_sessions.id = ${panel.tableName}.sessionId
          ),
          syncStatus = 'pending',
          dirtyAt = ?,
          syncError = NULL
      WHERE EXISTS (
        SELECT 1
        FROM audit_sessions
        WHERE audit_sessions.id = ${panel.tableName}.sessionId
          AND ${panel.tableName}.date <> substr(audit_sessions.date, 1, 10)
      )
    ''',
      [dirtyAt],
    );
  }
}

Future<void> _repairLegacyPanelPhotoReferences(Database db) async {
  if (!await _tableExists(db, 'photos')) return;
  final photos = await db.query(
    'photos',
    columns: ['id', 'sessionId', 'panelName', 'panelRowId'],
  );
  final knownPanels = {
    for (final panel in PanelSampleSchema.panels) panel.tableName,
  };
  for (final photo in photos) {
    final panelName = photo['panelName']?.toString();
    final legacyRowId = photo['panelRowId']?.toString();
    final sessionId = photo['sessionId']?.toString();
    if (panelName == null ||
        legacyRowId == null ||
        sessionId == null ||
        !knownPanels.contains(panelName) ||
        !await _tableExists(db, panelName)) {
      continue;
    }
    final rows = await db.query(
      panelName,
      columns: ['id'],
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
    final rowIds = rows.map((row) => row['id']?.toString()).whereType<String>();
    if (rowIds.contains(legacyRowId)) continue;
    final candidates = rowIds
        .where((rowId) => rowId.startsWith('$legacyRowId:'))
        .toList();
    if (candidates.length == 1) {
      await db.update(
        'photos',
        {'panelRowId': candidates.single, 'uploadStatus': 'local'},
        where: 'id = ?',
        whereArgs: [photo['id']],
      );
    } else {
      debugPrint(
        'ChickMark v63 left photo ${photo['id']} unchanged: '
        '${candidates.length} panel rows match $legacyRowId.',
      );
    }
  }
}

Future<void> _rebuildV56AgentIntegrityTables(Database db) async {
  for (final table in const [
    'agent_conversations',
    'agent_conversation_turns',
    'agent_tool_events',
  ]) {
    if (!await _tableExists(db, table)) return;
  }

  final foreignKeysRow = await db.rawQuery('PRAGMA foreign_keys');
  final restoreForeignKeys = foreignKeysRow.single.values.first == 1;
  if (restoreForeignKeys) {
    // The application upgrade path already has foreign keys disabled by
    // onConfigure. This also keeps the test hook safe when called directly.
    await db.execute('PRAGMA foreign_keys = OFF');
  }
  // Apple's system SQLite (iOS/macOS) enables legacy ALTER TABLE semantics
  // by default, so RENAME would leave the shadow tables' foreign-key clauses
  // pointing at the dropped shadow names and the post-rebuild
  // foreign_key_check would flag every row. Force modern semantics so RENAME
  // rewrites references in the other shadow tables.
  await db.execute('PRAGMA legacy_alter_table = OFF');

  try {
    const conversationsShadow = 'agent_conversations_v56';
    const turnsShadow = 'agent_conversation_turns_v56';
    const toolsShadow = 'agent_tool_events_v56';
    // SQLite reparses every trigger during ALTER TABLE. Sparse but supported
    // legacy databases may not have their referenced scope tables until the
    // surgical repair pass runs onOpen, so remove all unified-agent guards
    // before the shadow rename and recreate them after the graph is stable.
    for (final trigger in const [
      'trg_telegram_staff_links_scope_insert',
      'trg_telegram_staff_links_scope_update',
      'trg_agent_intake_visit_scope_insert',
      'trg_agent_intake_visit_scope_update',
      'trg_agent_intake_summary_immutable',
      'trg_agent_tool_events_immutable',
      'trg_agent_tool_events_delete_immutable',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
    for (final table in const [toolsShadow, turnsShadow, conversationsShadow]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }

    await _createAgentConversationsTable(db, tableName: conversationsShadow);
    await _createAgentConversationTurnsTable(
      db,
      tableName: turnsShadow,
      conversationsTable: conversationsShadow,
    );
    await _createAgentToolEventsTable(
      db,
      tableName: toolsShadow,
      turnsTable: turnsShadow,
    );

    const conversationColumns = '''
      id,
      staffLinkId,
      telegramChatId,
      stateVersion,
      contextEpoch,
      selectedCustomerId,
      selectedFlockId,
      selectedAuditId,
      contextUpdatedAt,
      pendingActionJson,
      activeVisitId,
      createdAt,
      updatedAt,
      syncStatus,
      dirtyAt,
      lastSyncedAt,
      syncError
    ''';
    const turnColumns = '''
      id,
      conversationId,
      direction,
      telegramUpdateId,
      telegramMessageId,
      turnIndex,
      contextEpoch,
      text,
      language,
      provider,
      model,
      providerResponseId,
      replyToTurnId,
      attachmentJson,
      deliveryStatus,
      createdAt,
      syncStatus,
      dirtyAt,
      lastSyncedAt,
      syncError
    ''';
    const toolColumns = '''
      id,
      conversationTurnId,
      toolCallId,
      toolName,
      toolSequence,
      argumentsJson,
      resultJson,
      status,
      durationMs,
      stateVersionBefore,
      stateVersionAfter,
      createdAt,
      syncStatus,
      dirtyAt,
      lastSyncedAt,
      syncError
    ''';

    await db.execute('''
      INSERT INTO $conversationsShadow ($conversationColumns)
      SELECT $conversationColumns FROM agent_conversations
    ''');
    await db.execute('''
      INSERT INTO $turnsShadow ($turnColumns)
      SELECT $turnColumns FROM agent_conversation_turns
    ''');
    await db.execute('''
      INSERT INTO $toolsShadow ($toolColumns)
      SELECT $toolColumns FROM agent_tool_events
    ''');

    for (final pair in const [
      ('agent_conversations', conversationsShadow),
      ('agent_conversation_turns', turnsShadow),
      ('agent_tool_events', toolsShadow),
    ]) {
      final sourceCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${pair.$1}'),
      );
      final shadowCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${pair.$2}'),
      );
      if (sourceCount != shadowCount) {
        throw StateError(
          'v56 agent table rebuild row-count mismatch for ${pair.$1}',
        );
      }
    }

    await db.execute('DROP TABLE agent_tool_events');
    await db.execute('DROP TABLE agent_conversation_turns');
    await db.execute('DROP TABLE agent_conversations');
    await db.execute(
      'ALTER TABLE $conversationsShadow RENAME TO agent_conversations',
    );
    await db.execute(
      'ALTER TABLE $turnsShadow RENAME TO agent_conversation_turns',
    );
    await db.execute('ALTER TABLE $toolsShadow RENAME TO agent_tool_events');

    await _createUnifiedAgentHarnessTables(db, createGuards: false);
    for (final table in const [
      'agent_conversations',
      'agent_conversation_turns',
      'agent_tool_events',
    ]) {
      final violations = await db.rawQuery('PRAGMA foreign_key_check($table)');
      if (violations.isNotEmpty) {
        throw StateError(
          'v56 agent table rebuild found foreign-key violations in $table',
        );
      }
    }
  } finally {
    if (restoreForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

Future<bool> _tableExists(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  return rows.isNotEmpty;
}

Future<void> _ensureDummyTestData(Database db) async {
  if (kReleaseMode) return;
  for (final seed in kDummyCustomerSeeds) {
    await _upsertSeedById(db, 'customers', seed);
  }
  for (final seed in kDummyFlockSeeds) {
    await _upsertSeedById(db, 'flocks', seed);
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

Future<void> _backfillOperationalBmkSeedSources(Database db) async {
  if (!await _tableExists(db, 'bmk_operational_standards')) return;
  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('bmk_operational_standards')"),
  );
  if (!columns.contains('sourceUrl')) return;

  for (final seed in kBmkOperationalStandardSeeds) {
    await db.update(
      'bmk_operational_standards',
      {'source': seed['source'], 'sourceUrl': seed['sourceUrl']},
      where: 'id = ? AND hatcheryId IS NULL',
      whereArgs: [seed['id']],
    );
  }
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

Set<String> _columnNames(List<Map<String, Object?>> tableInfo) {
  return tableInfo
      .map((row) => row['name']?.toString())
      .whereType<String>()
      .toSet();
}

/// v67 removes the Broiler Performance and farm-visit feature outright: the
/// broiler daily-record/target tables, the performance alert/concern tables,
/// and the farm-visit/investigation/cause-assessment/corrective-action tables.
/// A later feature replaces this area; nothing here is recreated by a future
/// migration. Child tables are dropped before the parents they reference so
/// SQLite's deferred FK checks never see a dangling reference mid-migration.
/// `customer_sectors`, `farms`, `houses`, `flock_placements`, and `flocks`
/// are untouched — a later migration reshapes them for the replacement
/// feature.
Future<void> _applyV67Upgrade(Database db) async {
  for (final table in const [
    'action_kpi_evaluations',
    'corrective_actions',
    'cause_assessments',
    'visit_findings',
    'visit_investigations',
    'farm_visit_houses',
    'farm_visit_sessions',
    'performance_concerns',
    'performance_alert_rules',
    'broiler_daily_events',
    'daily_record_sources',
    'broiler_daily_record_revisions',
    'broiler_daily_records',
    'broiler_target_rows',
    'broiler_target_profiles',
  ]) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }
}

/// v68 collapses Farm into Flock: a farm and a flock are the same thing in
/// this business (see docs/superpowers/specs/2026-08-27-breeder-flock-performance-design.md
/// section 2.1). `houses.farmId` becomes `houses.flockId`, each house gains
/// its own opening female/male bird counts (carrying the opening balance
/// that used to live on a `flock_placements` row), `flocks.entryDate` is the
/// single placement date for every house in the flock, `flocks.farmId` is
/// removed, and the `farms` and `flock_placements` tables are dropped
/// outright. `customer_sectors` is untouched.
///
/// Backfill: for each existing house, the flock and opening counts are taken
/// from its *active* flock_placements row (status='active', endedAt IS
/// NULL). The source schema never split placedBirds by sex, so the whole
/// count is assigned to females for an as_hatched or female flock and to
/// males for a male flock — a reasonable default for a breeder operation
/// tracked primarily by female counts, applied only during this one-time
/// backfill. A house with no active placement, or whose placement points at
/// a flock row that no longer exists, cannot be assigned a flock and is
/// deleted rather than assigned an invented one — the project is still in
/// testing and losing that local Performance test data is acceptable. Both
/// row counts are logged via debugPrint so an upgrade can be audited after
/// the fact.
Future<void> _applyV68Upgrade(Database db) async {
  await _rebuildV68HousesTable(db);
  await db.execute('DROP TABLE IF EXISTS flock_placements');
  await db.execute('DROP TABLE IF EXISTS farms');
  await _rebuildV68FlocksTableDroppingFarmId(db);
}

Future<void> _rebuildV68HousesTable(Database db) async {
  if (!await _tableExists(db, 'houses')) return;

  final houseColumns = _columnNames(
    await db.rawQuery("PRAGMA table_info('houses')"),
  );
  if (!houseColumns.contains('farmId')) {
    // Already reshaped (e.g. surgical repair ran after a partial upgrade).
    return;
  }

  final hasPlacements = await _tableExists(db, 'flock_placements');
  final hasFlocks = await _tableExists(db, 'flocks');

  // houseId -> (flockId, openingFemales, openingMales), derived from each
  // house's single active placement.
  final resolved = <String, (String, int, int)>{};
  if (hasPlacements && hasFlocks) {
    final rows = await db.rawQuery('''
      SELECT h.id AS houseId, fp.flockId AS flockId, fp.placedBirds AS placedBirds,
        f.sexProfile AS sexProfile
      FROM houses h
      JOIN flock_placements fp
        ON fp.houseId = h.id AND fp.status = 'active' AND fp.endedAt IS NULL
      JOIN flocks f ON f.id = fp.flockId
    ''');
    final seenHouses = <String>{};
    for (final row in rows) {
      final houseId = row['houseId']?.toString();
      final flockId = row['flockId']?.toString();
      if (houseId == null || flockId == null) continue;
      // A house should have at most one active placement (the pre-v68
      // unique index enforced this); if data drifted, keep the first match
      // and ignore the rest rather than double counting.
      if (!seenHouses.add(houseId)) continue;
      final placedBirds = _integerFrom(row['placedBirds']) ?? 0;
      final sexProfile = row['sexProfile']?.toString();
      final isMaleFlock = sexProfile == 'male';
      resolved[houseId] = (
        flockId,
        isMaleFlock ? 0 : placedBirds,
        isMaleFlock ? placedBirds : 0,
      );
    }
  }

  final allHouseRows = await db.query('houses');
  final orphanCount = allHouseRows.length - resolved.length;
  debugPrint(
    '[DB MIGRATION v68] houses backfilled from flock_placements: '
    '${resolved.length}, orphan houses deleted: $orphanCount',
  );

  final foreignKeysRow = await db.rawQuery('PRAGMA foreign_keys');
  final restoreForeignKeys = foreignKeysRow.single.values.first == 1;
  if (restoreForeignKeys) {
    await db.execute('PRAGMA foreign_keys = OFF');
  }
  await db.execute('PRAGMA legacy_alter_table = OFF');

  // On a database that already carries v71's `breeder_bird_movements`
  // house-scope guards (a fresh install being replayed through this
  // migration for a test, or a future re-run after v71 has landed),
  // SQLite reparses every trigger that references `houses` during the
  // DROP/RENAME dance below, and briefly finds no `houses` table. Drop the
  // guard set for the duration and recreate it once `houses` exists again
  // under its final name — the same trick the v68 flocks rebuild already
  // uses for the unified-agent guard set.
  final hasBreederMovementGuards = await _tableExists(
    db,
    'breeder_bird_movements',
  );
  // The version-74 `breeder_egg_production_entries` guards reference
  // `houses` the same way `breeder_bird_movements`/`breeder_feed_entries`
  // do and hit the identical "no such table: main.houses" trigger-reparse
  // failure during the DROP/RENAME dance below if left in place — checked
  // separately from `hasBreederMovementGuards` since, in principle, this
  // table's existence is not tied to the movements table's.
  final hasBreederEggProductionGuards = await _tableExists(
    db,
    'breeder_egg_production_entries',
  );
  // The version-77 `breeder_weighing_sessions` house-scope guard
  // (`trg_breeder_weighing_sessions_house_scope_*`) references `houses` the
  // same way the movement/feed/egg-production guards above do and hits the
  // identical "no such table: main.houses" trigger-reparse failure during
  // the DROP/RENAME dance below if left in place, so it is dropped and
  // recreated alongside them. Checked separately since, like the egg
  // production guards, this table's existence is not tied to the others'.
  final hasBreederWeighingSessionGuards = await _tableExists(
    db,
    'breeder_weighing_sessions',
  );
  // The version-78 `egg_batch_house_sources` house-scope guard
  // (`trg_egg_batch_house_sources_house_scope_*`) references `houses` the
  // same way the movement/feed/egg-production/weighing-session guards
  // above do and hits the identical "no such table: main.houses"
  // trigger-reparse failure during the DROP/RENAME dance below if left in
  // place, so it is dropped and recreated alongside them. Checked
  // separately since, like the others, this table's existence is not tied
  // to any other table's.
  final hasEggBatchHouseSourceGuards = await _tableExists(
    db,
    'egg_batch_house_sources',
  );
  // The version-80 `breeder_performance_alerts` house-scope guard
  // (`trg_breeder_performance_alerts_house_scope_*`) references `houses`
  // the same way the movement/feed/egg-production/weighing-session/
  // egg-batch-house-source guards above do and hits the identical "no such
  // table: main.houses" trigger-reparse failure during the DROP/RENAME
  // dance below if left in place, so it is dropped and recreated alongside
  // them. Checked separately since, like the others, this table's
  // existence is not tied to any other table's.
  final hasBreederPerformanceAlertsGuards = await _tableExists(
    db,
    'breeder_performance_alerts',
  );
  if (hasBreederMovementGuards) {
    // Both the pre-v72 name (house-scope-only) and the v72+ name
    // (location-scope, covering isolation areas too) are dropped here: a
    // fresh install always creates the current (location-scope) triggers,
    // so replaying this v68 step against a from-scratch schema (as the
    // migration-chain parity test does) only ever has the new name to
    // drop, while a genuinely old on-disk database being upgraded through
    // this step still has the old name. The version-73 `breeder_feed_entries`
    // guards reference `houses` the same way and hit the identical "no such
    // table: main.houses" trigger-reparse failure if left in place, so they
    // are dropped and recreated alongside the movement guards.
    for (final trigger in const [
      'trg_breeder_bird_movements_house_scope_insert',
      'trg_breeder_bird_movements_house_scope_update',
      'trg_breeder_bird_movements_location_scope_insert',
      'trg_breeder_bird_movements_location_scope_update',
      'trg_breeder_feed_entries_location_scope_insert',
      'trg_breeder_feed_entries_location_scope_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
  }
  if (hasBreederEggProductionGuards) {
    for (final trigger in const [
      'trg_breeder_egg_production_entries_location_scope_insert',
      'trg_breeder_egg_production_entries_location_scope_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
  }
  if (hasBreederWeighingSessionGuards) {
    for (final trigger in const [
      'trg_breeder_weighing_sessions_house_scope_insert',
      'trg_breeder_weighing_sessions_house_scope_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
  }
  if (hasEggBatchHouseSourceGuards) {
    for (final trigger in const [
      'trg_egg_batch_house_sources_house_scope_insert',
      'trg_egg_batch_house_sources_house_scope_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
  }
  if (hasBreederPerformanceAlertsGuards) {
    for (final trigger in const [
      'trg_breeder_performance_alerts_house_scope_insert',
      'trg_breeder_performance_alerts_house_scope_update',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }
  }

  try {
    const shadow = 'houses_v68';
    await db.execute('DROP TABLE IF EXISTS $shadow');
    await db.execute('''CREATE TABLE $shadow (
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

    for (final row in allHouseRows) {
      final houseId = row['id']?.toString();
      if (houseId == null) continue;
      final match = resolved[houseId];
      if (match == null) continue; // orphan: dropped, not carried forward.
      final (flockId, openingFemales, openingMales) = match;
      await db.insert(shadow, {
        'id': houseId,
        'flockId': flockId,
        'name': row['name'],
        'code': row['code'],
        'capacity': row['capacity'],
        'openingFemales': openingFemales,
        'openingMales': openingMales,
        'notes': row['notes'],
        'isActive': row['isActive'] ?? 1,
        'createdBy': row['createdBy'],
        'createdAt': row['createdAt'],
        'updatedAt': row['updatedAt'],
        'syncStatus': row['syncStatus'] ?? 'pending',
        'dirtyAt': row['dirtyAt'],
        'lastSyncedAt': row['lastSyncedAt'],
        'syncError': row['syncError'],
      });
    }

    await db.execute('DROP TABLE houses');
    await db.execute('ALTER TABLE $shadow RENAME TO houses');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_houses_flock_name '
      'ON houses (flockId, name)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_houses_flock_code '
      'ON houses (flockId, code) WHERE code IS NOT NULL AND code <> \'\'',
    );

    final violations = await db.rawQuery('PRAGMA foreign_key_check(houses)');
    if (violations.isNotEmpty) {
      throw StateError('v68 houses rebuild found foreign-key violations');
    }

    // Recreate the guard set dropped above, now that `houses` exists again
    // under its final name. `createBreederDailyReportTables` is idempotent
    // (CREATE TABLE/TRIGGER IF NOT EXISTS), so calling it again only
    // restores what was dropped.
    if (hasBreederMovementGuards) {
      await createBreederDailyReportTables(db);
    }
    if (hasBreederEggProductionGuards) {
      await createBreederEggProductionEntriesTable(db);
    }
    if (hasBreederWeighingSessionGuards) {
      await createBreederWeighingSessionsTable(db);
    }
    if (hasEggBatchHouseSourceGuards) {
      await createEggBatchHouseSourcesTable(db);
    }
    if (hasBreederPerformanceAlertsGuards) {
      await createBreederPerformanceAlertsTable(db);
    }
  } finally {
    if (restoreForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

Future<void> _rebuildV68FlocksTableDroppingFarmId(Database db) async {
  if (!await _tableExists(db, 'flocks')) return;
  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('flocks')"),
  );
  if (!columns.contains('farmId')) return;

  const carriedColumns = [
    'id',
    'customerId',
    'flockId',
    'breed',
    'entryDate',
    'sectorKey',
    'sexProfile',
    'targetProfileId',
    'productionPhase',
    'isAgeEstimated',
    'status',
    'depletionAgeWeeks',
    'soldAt',
    'updatedAt',
    'syncStatus',
    'dirtyAt',
    'lastSyncedAt',
    'syncError',
  ];
  final copied = carriedColumns.where(columns.contains).toList();
  if (!copied.contains('id')) return;
  final copiedList = copied.join(', ');

  final foreignKeysRow = await db.rawQuery('PRAGMA foreign_keys');
  final restoreForeignKeys = foreignKeysRow.single.values.first == 1;
  if (restoreForeignKeys) {
    await db.execute('PRAGMA foreign_keys = OFF');
  }
  await db.execute('PRAGMA legacy_alter_table = OFF');

  try {
    // SQLite reparses every trigger during ALTER TABLE, not just the ones
    // bound to the renamed table. `trg_agent_intake_visit_scope_insert`/
    // `_update` reference `flocks` in a subquery, which makes the RENAME
    // fail once the old `flocks` table is dropped mid-rebuild. Drop the
    // whole unified-agent guard set for the duration and recreate it once
    // the table graph is whole again (see the v59 telegram_staff_links
    // rebuild for the same trick).
    for (final trigger in const [
      'trg_telegram_staff_links_scope_insert',
      'trg_telegram_staff_links_scope_update',
      'trg_agent_intake_visit_scope_insert',
      'trg_agent_intake_visit_scope_update',
      'trg_agent_intake_summary_immutable',
      'trg_agent_tool_events_immutable',
      'trg_agent_tool_events_delete_immutable',
    ]) {
      await db.execute('DROP TRIGGER IF EXISTS $trigger');
    }

    const shadow = 'flocks_v68';
    await db.execute('DROP TABLE IF EXISTS $shadow');
    await db.execute('''CREATE TABLE $shadow (
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

    await db.execute('''
      INSERT INTO $shadow ($copiedList)
      SELECT $copiedList FROM flocks
    ''');

    final sourceCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM flocks'),
    );
    final shadowCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $shadow'),
    );
    if (sourceCount != shadowCount) {
      throw StateError('v68 flocks rebuild row-count mismatch');
    }

    await db.execute('DROP TABLE flocks');
    await db.execute('ALTER TABLE $shadow RENAME TO flocks');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_flocks_customer '
      'ON flocks (customerId, status)',
    );

    final violations = await db.rawQuery('PRAGMA foreign_key_check(flocks)');
    if (violations.isNotEmpty) {
      throw StateError('v68 flocks rebuild found foreign-key violations');
    }

    // Recreate the guard set dropped above, now that `flocks` exists again.
    // A minimal pre-v68 fixture (as in a targeted migration test) may not
    // carry the unified-agent tables these triggers guard; skip recreation
    // rather than fail when that's the case — onOpen's surgical repair
    // covers a real upgrade regardless.
    if (await _tableExists(db, 'telegram_staff_links') &&
        await _tableExists(db, 'agent_intake_visits') &&
        await _tableExists(db, 'agent_intake_sessions') &&
        await _tableExists(db, 'agent_tool_events')) {
      await _createUnifiedAgentHarnessGuards(db);
    }
  } finally {
    if (restoreForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

int? _integerFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

/// v69 adds the official breeder benchmark foundation (breeder-flock
/// -performance ticket 03): `breeder_metric_definitions`,
/// `breeder_benchmark_profiles`, and `breeder_benchmark_values`, then imports
/// the checked-in asset profiles (see
/// lib/data/database/seeds/breeder_benchmark_seeds.dart). Import is
/// idempotent and keyed by profile identity, so re-running an upgrade never
/// duplicates or mutates an already-published profile.
Future<void> _applyV69Upgrade(Database db) async {
  await createBreederBenchmarkTables(db);
  await importBreederBenchmarks(db);
}

/// v70 adds `breeder_flock_milestones` (breeder-flock-performance ticket
/// 06): dated operational events per flock (grading, physical transfer,
/// light stimulation, first egg, production milestones, and depletion
/// events). See `createBreederFlockMilestonesTable` in database_schema.dart.
Future<void> _applyV70Upgrade(Database db) async {
  await createBreederFlockMilestonesTable(db);
}

/// v71 adds `breeder_daily_reports` and `breeder_bird_movements`
/// (breeder-flock-performance ticket 07): the daily report header plus its
/// bird-movement ledger, the first vertical slice of the daily report. Feed,
/// eggs, and inventory are later tickets. See
/// `createBreederDailyReportTables` in database_schema.dart.
Future<void> _applyV71Upgrade(Database db) async {
  await createBreederDailyReportTables(db);
}

/// v72 adds `breeder_isolation_areas` (breeder-flock-performance ticket 08)
/// and extends `breeder_bird_movements` so a movement's location is either a
/// house or a named isolation area — exactly one, never both, never
/// neither. See `createBreederIsolationAreasTable` and the updated
/// `createBreederDailyReportTables` in database_schema.dart for the final
/// (fresh-install) shape; [_rebuildBreederBirdMovementsForIsolationAreas]
/// below reshapes an existing v71 `breeder_bird_movements` table into that
/// shape in place, since SQLite cannot relax a NOT NULL column or add a
/// multi-column CHECK via ALTER TABLE.
Future<void> _applyV72Upgrade(Database db) async {
  await createBreederIsolationAreasTable(db);
  await _rebuildBreederBirdMovementsForIsolationAreas(db);
}

Future<void> _rebuildBreederBirdMovementsForIsolationAreas(Database db) async {
  final hasTable = await _tableExists(db, 'breeder_bird_movements');
  if (!hasTable) return; // Fresh install already created the v72 shape.

  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('breeder_bird_movements')"),
  );
  if (columns.contains('isolationAreaId')) {
    return; // Already rebuilt (e.g. surgical repair re-running this).
  }

  final existingRows = await db.query('breeder_bird_movements');

  final foreignKeysRow = await db.rawQuery('PRAGMA foreign_keys');
  final restoreForeignKeys = foreignKeysRow.single.values.first == 1;
  if (restoreForeignKeys) {
    await db.execute('PRAGMA foreign_keys = OFF');
  }

  try {
    // Old (pre-v72) house-scope-only triggers, and any location-scope
    // triggers from a previous partial run of this migration.
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_breeder_bird_movements_house_scope_insert',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_breeder_bird_movements_house_scope_update',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_breeder_bird_movements_location_scope_insert',
    );
    await db.execute(
      'DROP TRIGGER IF EXISTS trg_breeder_bird_movements_location_scope_update',
    );

    const shadow = 'breeder_bird_movements_v72';
    await db.execute('DROP TABLE IF EXISTS $shadow');
    await db.execute('''CREATE TABLE $shadow (
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

    // Every pre-v72 row is a house movement (isolation did not exist yet).
    for (final row in existingRows) {
      await db.insert(shadow, {...row, 'isolationAreaId': null});
    }

    final sourceCount = existingRows.length;
    final shadowCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $shadow'),
        ) ??
        0;
    if (sourceCount != shadowCount) {
      throw StateError(
        'v72 breeder_bird_movements rebuild row-count mismatch',
      );
    }

    await db.execute('DROP TABLE breeder_bird_movements');
    await db.execute('ALTER TABLE $shadow RENAME TO breeder_bird_movements');

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

    final violations = await db.rawQuery(
      'PRAGMA foreign_key_check(breeder_bird_movements)',
    );
    if (violations.isNotEmpty) {
      throw StateError(
        'v72 breeder_bird_movements rebuild found foreign-key violations',
      );
    }
  } finally {
    if (restoreForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

/// v73 adds `breeder_feed_entries` and `breeder_daily_reports.lightHours`
/// (breeder-flock-performance ticket 09, design doc section 5.2 and 7.1):
/// per-house, per-sex feed in kilograms (grams-per-bird is always derived,
/// never stored — see `BreederBirdLedgerService.feedGramsPerBird`), plus a
/// light-hours header field alongside the temperatures and notes ticket 07
/// already added. See `createBreederFeedEntriesTable` in
/// database_schema.dart for the final (fresh-install) shape.
///
/// `lightHours` is a plain nullable column addition — unlike v72's
/// `breeder_bird_movements` reshape, adding it needs no shadow-table
/// rebuild, since SQLite's `ALTER TABLE ADD COLUMN` handles a new nullable
/// column with no CHECK constraint directly.
Future<void> _applyV73Upgrade(Database db) async {
  if (await _tableExists(db, 'breeder_daily_reports')) {
    final columns = _columnNames(
      await db.rawQuery("PRAGMA table_info('breeder_daily_reports')"),
    );
    if (!columns.contains('lightHours')) {
      await db.execute(
        'ALTER TABLE breeder_daily_reports ADD COLUMN lightHours REAL',
      );
    }
  }
  await createBreederFeedEntriesTable(db);
}

/// v74 adds `breeder_egg_grade_definitions`, `breeder_egg_production_entries`,
/// and three approval-snapshot columns on `breeder_daily_reports`
/// (breeder-flock-performance ticket 10, design doc section 5.2, 7, 7.1,
/// and 12). See `createBreederEggGradeDefinitionsTable` and
/// `createBreederEggProductionEntriesTable` in database_schema.dart for the
/// final (fresh-install) shape, and `BreederEggProductionService` for the
/// grade-priority-resolution and total/percentage arithmetic.
///
/// The three new `breeder_daily_reports` columns
/// (`eggProductionDenominatorFemales`, `benchmarkProfileVersionAtApproval`,
/// `comparisonAxisAtApproval`) are plain nullable additions — like v73's
/// `lightHours`, they need no shadow-table rebuild.
Future<void> _applyV74Upgrade(Database db) async {
  if (await _tableExists(db, 'breeder_daily_reports')) {
    final columns = _columnNames(
      await db.rawQuery("PRAGMA table_info('breeder_daily_reports')"),
    );
    if (!columns.contains('eggProductionDenominatorFemales')) {
      await db.execute(
        'ALTER TABLE breeder_daily_reports '
        'ADD COLUMN eggProductionDenominatorFemales INTEGER',
      );
    }
    if (!columns.contains('benchmarkProfileVersionAtApproval')) {
      await db.execute(
        'ALTER TABLE breeder_daily_reports '
        'ADD COLUMN benchmarkProfileVersionAtApproval TEXT',
      );
    }
    if (!columns.contains('comparisonAxisAtApproval')) {
      await db.execute(
        'ALTER TABLE breeder_daily_reports '
        'ADD COLUMN comparisonAxisAtApproval TEXT',
      );
    }
  }
  await createBreederEggGradeDefinitionsTable(db);
  await seedBreederEggGradeDefinitions(db);
  await createBreederEggProductionEntriesTable(db);
}

/// v75 adds `breeder_egg_inventory_movements` (breeder-flock-performance
/// ticket 11, design doc section 7, 8, 12, and 14). See
/// `createBreederEggInventoryMovementsTable` in database_schema.dart for the
/// final (fresh-install) shape and rationale, and
/// `BreederEggInventoryService` for the balance arithmetic and
/// approval-gate validation.
///
/// This table names no house or isolation area — inventory is tracked at
/// the whole-flock level — so, unlike v71/v73/v74's location-scope guard
/// sets, it needs no entry in the v68 houses-rebuild trigger-drop list: it
/// carries no trigger that references `houses` at all.
Future<void> _applyV75Upgrade(Database db) async {
  await createBreederEggInventoryMovementsTable(db);
}

/// v76 adds `breeder_report_revisions` (breeder-flock-performance ticket
/// 12, design doc section 5.3, 12, 13, and 14). See
/// `createBreederReportRevisionsTable` in database_schema.dart for the
/// final (fresh-install) shape, immutability triggers, and rationale, and
/// `BreederReportRevisionService` for how a correction to an approved
/// report is diffed into one row per changed field.
///
/// A brand-new table with no columns added to any existing table — like
/// v75's `breeder_egg_inventory_movements`, this needs no
/// `ALTER TABLE ... ADD COLUMN` step and no shadow-table rebuild.
///
/// This version also widens `idx_breeder_egg_inventory_movements_unique`
/// (v75) with an `AND reason IS NULL` clause — see
/// `createBreederEggInventoryMovementsTable`'s updated doc comment in
/// database_schema.dart for why: ticket 12's egg-inventory correction path
/// (`BreederEggInventoryService.correctMovement`) appends a new row
/// alongside its never-mutated original, and the original v75 index would
/// otherwise reject that second row as a duplicate (report, grade, kind).
/// `CREATE INDEX IF NOT EXISTS` never replaces an already-existing index of
/// the same name, so the stale v75 definition is dropped by name first; a
/// database that never got past v75 has no such index yet and the DROP is
/// simply a no-op.
Future<void> _applyV76Upgrade(Database db) async {
  await db.execute(
    'DROP INDEX IF EXISTS idx_breeder_egg_inventory_movements_unique',
  );
  await createBreederEggInventoryMovementsTable(db);
  await createBreederReportRevisionsTable(db);
}

/// v77 adds `breeder_weighing_sessions` and `breeder_weighing_samples`
/// (breeder-flock-performance ticket 13, design doc section 5.1 and 9). See
/// `createBreederWeighingSessionsTable` in database_schema.dart for the
/// final (fresh-install) shape, the house-scope guard trigger, and
/// rationale, and `BreederWeighingService` for the derived-figure and
/// benchmark-comparison arithmetic.
///
/// `breeder_weighing_sessions` carries a required `houseId` and its own
/// house-scope guard trigger referencing `houses`
/// (`trg_breeder_weighing_sessions_house_scope_*`), so — like v71's
/// `breeder_bird_movements`, v73's `breeder_feed_entries`, and v74's
/// `breeder_egg_production_entries` — its trigger names are added to the
/// v68 houses-rebuild trigger-drop list above
/// (`_rebuildV68HousesTableAndBackfill`'s `hasBreederWeighingSessionGuards`
/// check), unlike v75's `breeder_egg_inventory_movements`, which names no
/// house at all.
Future<void> _applyV77Upgrade(Database db) async {
  await createBreederWeighingSessionsTable(db);
}

/// v78 adds `egg_batches`, `egg_batch_house_sources`, `egg_shipments`,
/// `egg_shipment_batches`, and `egg_batch_receipts` (breeder-flock
/// -performance ticket 14, design doc section 8 and 12). See
/// `createEggBatchesTable`/`createEggBatchHouseSourcesTable`/
/// `createEggShipmentsTable`/`createEggShipmentBatchesTable`/
/// `createEggBatchReceiptsTable` in database_schema.dart for the final
/// (fresh-install) shape and rationale, and `EggBatchDispatchService` for
/// batch/shipment/receipt creation and how a dispatch posts exactly one
/// ledger movement through ticket 11's `BreederEggInventoryService`.
///
/// `egg_batch_house_sources` carries a house-scope guard trigger
/// referencing `houses` (`trg_egg_batch_house_sources_house_scope_*`), so —
/// like v71's `breeder_bird_movements`, v73's `breeder_feed_entries`, v74's
/// `breeder_egg_production_entries`, and v77's `breeder_weighing_sessions`
/// — it is added to the v68 houses-rebuild trigger-drop list above
/// (`_rebuildV68HousesTableAndBackfill`'s `hasEggBatchHouseSourceGuards`
/// check). The other four new tables in this version name no house or
/// isolation area at all, matching v75's `breeder_egg_inventory_movements`
/// and v76's `breeder_report_revisions`.
Future<void> _applyV78Upgrade(Database db) async {
  await createEggBatchesTable(db);
  await createEggBatchHouseSourcesTable(db);
  await createEggShipmentsTable(db);
  await createEggShipmentBatchesTable(db);
  await createEggBatchReceiptsTable(db);
}

/// v79 (breeder-flock-performance ticket 15, design doc section 5.3 and
/// 13.1) adds the `Sync Conflict` state and the daily-report aggregate
/// push's optimistic-concurrency bookkeeping:
///
/// - `breeder_daily_reports.state`'s CHECK gains `'sync_conflict'`,
///   reachable from any of `draft`/`submitted`/`approved` when the report's
///   aggregate push is rejected by a stale concurrency token.
/// - `breeder_daily_reports.previousState` records which of those three
///   states the report held immediately before the conflict, so resolving
///   it can restore that exact state.
/// - `breeder_daily_reports.lastSyncedRevision` is local-only bookkeeping
///   (stripped from cloud payloads exactly like `syncStatus`/`dirtyAt`/
///   `lastSyncedAt`/`syncError`), sent as the aggregate push's
///   `base_revision` argument. Despite its name it does NOT track this
///   table's own `revision` column: it tracks the cloud-only `sync_token`
///   column (`supabase/migrations_unapplied/0012_...sql`), a counter the
///   push RPC (`0013_...sql`) advances by one on every successful
///   aggregate push regardless of whether `revision` changed. The two
///   must stay separate — `revision` is ticket 12's audit counter and can
///   be identical across two devices that never transitioned or corrected
///   the report, so gating concurrency on it would let a second push
///   silently overwrite a first one's already-accepted children with no
///   conflict ever raised. Always `0` for both brand-new reports and every
///   pre-existing report this migration upgrades — no local row, synced or
///   not, has ever confirmed a `sync_token` from the cloud (this column
///   does not exist there before this ticket), so `0` is the only honest
///   value; the first push after upgrading always succeeds regardless,
///   since the cloud has no row yet for any of these reports either.
///
/// SQLite cannot ALTER a CHECK constraint or ALTER COLUMN, so the table is
/// rebuilt via the same shadow-table-and-rename pattern v72 used for
/// `breeder_bird_movements` (see `_rebuildV72BirdMovementsTableForIsolation`
/// above). `breeder_daily_reports` carries no trigger of its own to drop
/// and re-create.
///
/// `sync_conflicts.localDataJson`/`remoteDataJson` need no rebuild — they
/// carry no CHECK constraint, so a plain `ALTER TABLE ADD COLUMN` suffices.
Future<void> _applyV79Upgrade(Database db) async {
  await _rebuildV79BreederDailyReportsTableForSyncConflict(db);

  // `sync_conflicts` is a very old critical table (predates this
  // migration's chain position by many versions) whose own creation on a
  // genuinely legacy database is handled by the surgical-repair pass in
  // `onOpen`, which runs AFTER the whole `_onUpgrade` chain — never by a
  // numbered `_applyVXXUpgrade`. A synthetic pre-v61 test fixture (or any
  // real database old enough to have never been surgically repaired) can
  // therefore legitimately still be missing it at this exact point in the
  // chain. Skip here in that case; the repair pass's own
  // `_createSyncConflictTable` call creates it with these columns already
  // present (database_schema.dart's shared fresh-install definition), so
  // nothing is lost, only deferred to the same pass that already handles
  // this table's existence for legacy databases.
  if (!await _tableExists(db, 'sync_conflicts')) return;

  final conflictColumns = _columnNames(
    await db.rawQuery("PRAGMA table_info('sync_conflicts')"),
  );
  if (!conflictColumns.contains('localDataJson')) {
    await db.execute(
      'ALTER TABLE sync_conflicts ADD COLUMN localDataJson TEXT',
    );
  }
  if (!conflictColumns.contains('remoteDataJson')) {
    await db.execute(
      'ALTER TABLE sync_conflicts ADD COLUMN remoteDataJson TEXT',
    );
  }
}

Future<void> _rebuildV79BreederDailyReportsTableForSyncConflict(
  Database db,
) async {
  final hasTable = await _tableExists(db, 'breeder_daily_reports');
  if (!hasTable) return; // Fresh install already created the v79 shape.

  final columns = _columnNames(
    await db.rawQuery("PRAGMA table_info('breeder_daily_reports')"),
  );
  if (columns.contains('lastSyncedRevision')) {
    return; // Already rebuilt (e.g. surgical repair re-running this).
  }

  final existingRows = await db.query('breeder_daily_reports');

  final foreignKeysRow = await db.rawQuery('PRAGMA foreign_keys');
  final restoreForeignKeys = foreignKeysRow.single.values.first == 1;
  if (restoreForeignKeys) {
    await db.execute('PRAGMA foreign_keys = OFF');
  }

  try {
    const shadow = 'breeder_daily_reports_v79';
    await db.execute('DROP TABLE IF EXISTS $shadow');
    await db.execute('''CREATE TABLE $shadow (
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

    for (final row in existingRows) {
      // No pre-existing row, synced or not, has ever confirmed a cloud
      // `sync_token` — that column does not exist in the cloud until this
      // ticket's migration is applied — so `0` is the only honest value
      // here, never `revision` (see this function's header comment for why
      // the two counters must never be conflated).
      await db.insert(shadow, {
        ...row,
        'previousState': null,
        'lastSyncedRevision': 0,
      });
    }

    final sourceCount = existingRows.length;
    final shadowCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $shadow'),
        ) ??
        0;
    if (sourceCount != shadowCount) {
      throw StateError(
        'v79 breeder_daily_reports rebuild row-count mismatch',
      );
    }

    await db.execute('DROP TABLE breeder_daily_reports');
    await db.execute('ALTER TABLE $shadow RENAME TO breeder_daily_reports');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_breeder_daily_reports_unique '
      'ON breeder_daily_reports (flockId, reportDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_breeder_daily_reports_flock '
      'ON breeder_daily_reports (flockId)',
    );
  } finally {
    if (restoreForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}

/// v80 (breeder-flock-performance ticket 17, design doc section 10 and 12)
/// adds `breeder_alert_rules` and `breeder_performance_alerts`. See
/// `createBreederAlertRulesTable`/`createBreederPerformanceAlertsTable` in
/// database_schema.dart for the final (fresh-install) shape and rationale,
/// `breeder_alert_rule_seeds.dart` for the seeded default rules, and
/// `BreederAlertEvaluationService` for how a rule turns into an alert.
///
/// `breeder_performance_alerts` carries a house-scope guard trigger
/// referencing `houses` (`trg_breeder_performance_alerts_house_scope_*`),
/// so — like v71's `breeder_bird_movements`, v73's `breeder_feed_entries`,
/// v74's `breeder_egg_production_entries`, v77's `breeder_weighing_sessions`,
/// and v78's `egg_batch_house_sources` — it is added to the v68
/// houses-rebuild trigger-drop list above (`_rebuildV68HousesTable`'s
/// `hasBreederPerformanceAlertsGuards` check). `breeder_alert_rules` names
/// no house or isolation area at all, matching v75's
/// `breeder_egg_inventory_movements` and v76's `breeder_report_revisions`.
Future<void> _applyV80Upgrade(Database db) async {
  await createBreederAlertRulesTable(db);
  await createBreederPerformanceAlertsTable(db);
  await seedBreederAlertRules(db);
}
/// v81 retires the Cobb500 Slow Feather parent-stock profile. The flock the
/// app is used against runs the Fast Feather line, and carrying a second Cobb
/// profile only invites picking the wrong one when comparing a flock.
///
/// Retirement, not archival: published benchmark profiles are immutable at
/// the database level, and `trg_breeder_benchmark_profiles_immutable_update`
/// rejects even a state change to `archived`. That immutability exists to
/// stop the *app* from editing reference data — a schema migration is the one
/// sanctioned place to remove it — so this drops the guards, deletes the
/// profile and its values, and puts the guards straight back.
///
/// Installs that never imported the profile (and every fresh install, which
/// no longer ships the asset) find nothing to delete and are unaffected.
Future<void> _applyV81Upgrade(Database db) async {
  const retiredProfileKey = 'cobb500_slow_feather_parent_stock_2020_en';

  final rows = await db.query(
    'breeder_benchmark_profiles',
    columns: ['id'],
    where: 'profileKey = ?',
    whereArgs: [retiredProfileKey],
    limit: 1,
  );
  if (rows.isEmpty) return;
  final profileId = rows.first['id'] as String;

  await db.execute(
    'DROP TRIGGER IF EXISTS trg_breeder_benchmark_values_immutable_delete',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_breeder_benchmark_profiles_immutable_delete',
  );
  try {
    await db.delete(
      'breeder_benchmark_values',
      where: 'profileId = ?',
      whereArgs: [profileId],
    );
    await db.delete(
      'breeder_benchmark_profiles',
      where: 'id = ?',
      whereArgs: [profileId],
    );
  } finally {
    // Recreated from the schema definition rather than inline, so the guards
    // can never drift from the fresh-install shape.
    await createBreederBenchmarkTables(db);
  }
}
