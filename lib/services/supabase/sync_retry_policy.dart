/// Bounds how often a table whose push keeps failing is retried.
///
/// `getDirtyRows` selects `syncStatus IN ('pending','failed')`, so a row that
/// failed to upload is re-read on *every* subsequent sync. Without a bound, a
/// table whose cloud counterpart does not exist (or whose batch the cloud
/// schema rejects) re-attempts the same doomed upload on every single run,
/// forever — a network round-trip per table per sync that can never succeed.
///
/// After a failure the table is skipped for an exponentially growing window
/// (1, 2, 4, 8, 16, then 30 minutes). One success clears the table's state.
///
/// The state is process-local on purpose: it needs no SQLite schema change,
/// and an app restart is a cheap, explicit "try again now" for the user.
/// Skipped tables are still reported as failed in the run's `SyncOutcome`, so
/// backing off never makes the problem invisible again.
class SyncRetryPolicy {
  SyncRetryPolicy({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const Duration baseBackoff = Duration(minutes: 1);
  static const Duration maxBackoff = Duration(minutes: 30);
  static const int maxDoublings = 6;

  /// Default instance. Every `StartupSyncService()` is constructed fresh by
  /// its callers, so the policy has to outlive the service to be of any use.
  static final SyncRetryPolicy shared = SyncRetryPolicy();

  final DateTime Function() _now;
  final Map<String, _TableRetryState> _stateByTable = {};

  /// False while [table] is inside its backoff window.
  bool shouldAttempt(String table) {
    final state = _stateByTable[table];
    if (state == null) return true;
    return !_now().isBefore(state.nextAttemptAt);
  }

  int consecutiveFailures(String table) => _stateByTable[table]?.failures ?? 0;

  DateTime? nextAttemptAt(String table) => _stateByTable[table]?.nextAttemptAt;

  void recordSuccess(String table) {
    _stateByTable.remove(table);
  }

  void recordFailure(String table) {
    final failures = consecutiveFailures(table) + 1;
    _stateByTable[table] = _TableRetryState(
      failures: failures,
      nextAttemptAt: _now().add(backoffFor(failures)),
    );
  }

  void reset() {
    _stateByTable.clear();
  }

  static Duration backoffFor(int failures) {
    final doublings = failures.clamp(1, maxDoublings) - 1;
    final minutes = baseBackoff.inMinutes << doublings;
    return minutes >= maxBackoff.inMinutes
        ? maxBackoff
        : Duration(minutes: minutes);
  }
}

class _TableRetryState {
  const _TableRetryState({required this.failures, required this.nextAttemptAt});

  final int failures;
  final DateTime nextAttemptAt;
}
