import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared v41-era fixture support for the schema-parity net.
///
/// There is no code path left in `DatabaseHelper` that builds a literal
/// "version 41" schema in isolation: `_onUpgrade` collapses every database
/// older than v41 straight into a fresh v56 `_onCreate` via
/// `_resetForPanelCutover` (see database_helper.dart's `_onUpgrade`). The
/// real, currently-live migration chain — `_applyV46Upgrade` through
/// `_applyV56Upgrade` — only ever runs for a database whose stored version is
/// already >= 41. To exercise that chain for real (not a hand-reimplied
/// stand-in for it), this file builds a v41-style baseline by taking a
/// genuine fresh v56 database (so every kept table's DDL is the real
/// production definition, never re-typed by hand) and dropping every table
/// that a v46+ migration introduces. The caller then replays
/// `_applyV46Upgrade` .. `_applyV56Upgrade` directly via their
/// `@visibleForTesting` hooks on `DatabaseHelper`.
///
/// [kV41BaselineTables] is the set of tables created by `_onCreate`'s first
/// block — `_createCoreTablesIfMissing` through `_createGoveeCaptureTables`
/// in `database_schema.dart` — which is exactly the table set produced by
/// the v41 panel-only cutover and left structurally untouched by every
/// migration from v46 through v56. Everything else a fresh v56 database
/// contains was introduced by one of those later migrations: dashboard
/// actions (v46), lab analysis tables (v47), the performance-monitoring
/// tables (v51), the hatchery-agent tables (v52), the agent-intake tables
/// (v53), and the unified-agent-harness tables (v54-v56).
const kV41BaselineTables = <String>{
  // _createCoreTablesIfMissing
  'users',
  'customers',
  'flocks',
  'bmk_breeds',
  'troubleshooting',
  'photos',
  'activity_log',
  // _createCleanBmkEggBreakoutTable
  'bmk_egg_breakout',
  // _createBmkOperationalStandardsTable
  'bmk_operational_standards',
  // _createHatcheryTables
  'hatcheries',
  // _createAuditSessionTables
  'audit_sessions',
  // _createPanelSampleSchemaTables (the v41 panel cutover tables)
  'egg_storage',
  'egg_quality',
  'chick_quality',
  'chick_weights',
  'fresh_egg_breakout',
  'candled_egg_breakout',
  'residue_breakout',
  'setter_optimizing',
  'hatcher_optimizing',
  // _createSyncTombstoneTable / _createSyncConflictTable
  'sync_tombstones',
  'sync_conflicts',
  // _createGoveeCaptureTables
  'govee_daily_captures',
};

/// All non-system table names currently in [db].
Future<Set<String>> tableNamesFor(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((row) => row['name']! as String).toSet();
}

/// Mutates an already-open, freshly-created v56 [db] in place into a
/// v41-style baseline: drops every table not in [kV41BaselineTables].
///
/// The caller is expected to then replay the real migration chain by calling
/// `DatabaseHelper().applyV46UpgradeForTest(db)` through
/// `applyV56UpgradeForTest(db)` directly, in the same order
/// `_onUpgrade(db, oldVersion, newVersion)` invokes them for any
/// `oldVersion` in `[41, 45]` (see database_helper.dart's `_onUpgrade`).
/// Deliberately *not* routed through `DatabaseHelper().db`/`onOpen`: the
/// `onOpen` callback runs `_surgicalSchemaRepair`, which idempotently
/// recreates any of its `_criticalTables` that are missing — precisely the
/// kind of gap this parity test exists to catch. Going through `.db` would
/// let that repair pass silently paper over a real chain regression before
/// the schema is ever compared, which was confirmed by temporarily
/// disabling a migration step and observing `_surgicalSchemaRepair` restore
/// the missing tables on reopen.
///
/// Returns the set of tables that were dropped, so callers can assert the
/// baseline genuinely differs from a fresh v56 database (i.e. that this
/// helper didn't silently no-op).
Future<Set<String>> dropTablesIntroducedAfterV41(Database db) async {
  final allTables = await tableNamesFor(db);
  final tablesToDrop = allTables.difference(kV41BaselineTables);
  await db.execute('PRAGMA foreign_keys = OFF');
  for (final table in tablesToDrop) {
    await db.execute('DROP TABLE IF EXISTS "$table"');
  }
  return tablesToDrop;
}
