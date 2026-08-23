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
