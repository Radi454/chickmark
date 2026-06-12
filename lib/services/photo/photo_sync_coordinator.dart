import 'dart:async';

import 'photo_sync_service.dart';

/// Fires opportunistic photo sync shortly after captures are saved, so evidence
/// reaches the cloud without waiting for the next startup / background full
/// sync.
///
/// Disabled by default: [nudge] is a no-op until [enable] is called once at app
/// startup. This keeps stray timers and network calls out of widget/unit tests,
/// which never call [enable].
class PhotoSyncCoordinator {
  PhotoSyncCoordinator._(this._service, this._debounce);

  final PhotoSyncService _service;
  final Duration _debounce;
  Timer? _timer;
  bool _running = false;
  bool _pendingAgain = false;

  static PhotoSyncCoordinator? _instance;

  /// Turn on opportunistic sync. Safe to call more than once (last wins).
  static void enable({
    PhotoSyncService? service,
    Duration debounce = const Duration(seconds: 2),
  }) {
    _instance?._timer?.cancel();
    _instance = PhotoSyncCoordinator._(service ?? PhotoSyncService(), debounce);
  }

  /// Disable and cancel any pending sync. Primarily for tests.
  static void disable() {
    _instance?._timer?.cancel();
    _instance = null;
  }

  /// Request a sync soon. No-op until [enable] has been called. Debounced so a
  /// burst of captures coalesces into a single sync pass.
  static void nudge() => _instance?._schedule();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, _run);
  }

  Future<void> _run() async {
    if (_running) {
      // A sync is already in flight; remember to run once more so captures
      // saved during this pass aren't stranded until the next nudge.
      _pendingAgain = true;
      return;
    }
    _running = true;
    try {
      await _service.syncPending();
    } catch (_) {
      // Best-effort; the next startup / background sync will retry.
    } finally {
      _running = false;
      if (_pendingAgain) {
        _pendingAgain = false;
        _schedule();
      }
    }
  }
}
