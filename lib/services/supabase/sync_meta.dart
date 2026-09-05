/// Device-local sync bookkeeping columns.
///
/// These track per-row sync state on *this* device only (is the row pending a
/// push, synced, or failed). They must never be pushed to Supabase — the cloud
/// is the source of truth for data, not for our local sync flags. Stripping
/// them also keeps the cloud schema free of these columns.
const kSyncMetaColumns = <String>{
  'syncStatus',
  'dirtyAt',
  'lastSyncedAt',
  'syncError',
  // breeder-flock-performance ticket 15: the daily-report sync aggregate's
  // own local-only optimistic-concurrency bookkeeping (design doc section
  // 13.1). Neither column exists in the cloud `breeder_daily_reports`
  // table — see database_schema.dart's `createBreederDailyReportTables` doc
  // comment for what each one means.
  'lastSyncedRevision',
  'previousState',
};

/// Returns a copy of [row] without the device-local sync bookkeeping columns,
/// safe to send to Supabase.
Map<String, dynamic> stripSyncMeta(Map<String, dynamic> row) {
  final copy = Map<String, dynamic>.from(row);
  copy.removeWhere((key, _) => kSyncMetaColumns.contains(key));
  return copy;
}
