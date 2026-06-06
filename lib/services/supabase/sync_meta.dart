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
};

/// Returns a copy of [row] without the device-local sync bookkeeping columns,
/// safe to send to Supabase.
Map<String, dynamic> stripSyncMeta(Map<String, dynamic> row) {
  final copy = Map<String, dynamic>.from(row);
  copy.removeWhere((key, _) => kSyncMetaColumns.contains(key));
  return copy;
}
