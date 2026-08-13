import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/network/network_status_monitor.dart';
import '../../core/security/safe_debug_log.dart';

enum AppSyncResult { success, offline, transientFailure }

typedef AppSyncCallback = Future<AppSyncResult> Function();

/// Coalesces local-write, reconnect, and app-resume sync requests into a single
/// foreground-safe sync pass.
///
/// Repositories can call [nudge] without depending on authentication or UI
/// providers. [MainShell] owns the callback and enables the coordinator only
/// while an authenticated workspace is mounted.
class AppSyncCoordinator {
  AppSyncCoordinator._({
    required AppSyncCallback sync,
    required NetworkStatusMonitor networkStatus,
    required Duration debounce,
    required Duration initialBackoff,
    required Duration maxBackoff,
  }) : _sync = sync,
       _networkStatus = networkStatus,
       _lastNetworkStatus = networkStatus.status,
       _debounce = debounce,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff {
    _networkStatus.addListener(_handleNetworkStatusChanged);
  }

  final AppSyncCallback _sync;
  final NetworkStatusMonitor _networkStatus;
  final Duration _debounce;
  final Duration _initialBackoff;
  final Duration _maxBackoff;

  static AppSyncCoordinator? _instance;

  Timer? _timer;
  bool _running = false;
  bool _pendingAgain = false;
  bool _disposed = false;
  NetworkStatus _lastNetworkStatus;
  int _retryAttempt = 0;
  DateTime? _retryNotBefore;

  static void enable({
    required AppSyncCallback sync,
    required NetworkStatusMonitor networkStatus,
    Duration debounce = const Duration(seconds: 2),
    Duration initialBackoff = const Duration(seconds: 5),
    Duration maxBackoff = const Duration(minutes: 5),
  }) {
    disable();
    _instance = AppSyncCoordinator._(
      sync: sync,
      networkStatus: networkStatus,
      debounce: debounce,
      initialBackoff: initialBackoff,
      maxBackoff: maxBackoff,
    );
  }

  static void disable() {
    _instance?._dispose();
    _instance = null;
  }

  /// Request a sync after the current local write burst settles.
  ///
  /// Calls are safe before [enable] and are coalesced while a sync is running.
  static void nudge({bool immediate = false}) {
    _instance?._schedule(immediate ? Duration.zero : null);
  }

  @visibleForTesting
  static bool get isEnabled => _instance != null;

  void _schedule([Duration? delay]) {
    if (_disposed) return;
    if (!_networkStatus.isOnline) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    var effectiveDelay = delay ?? _debounce;
    final retryNotBefore = _retryNotBefore;
    if (retryNotBefore != null) {
      final remaining = retryNotBefore.difference(DateTime.now());
      if (!remaining.isNegative && remaining > effectiveDelay) {
        effectiveDelay = remaining;
      }
    }
    _timer?.cancel();
    _timer = Timer(effectiveDelay, () {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_disposed) return;
    if (_running) {
      _pendingAgain = true;
      return;
    }

    _running = true;
    try {
      final result = await _sync();
      switch (result) {
        case AppSyncResult.success:
          _resetBackoff();
        case AppSyncResult.offline:
          if (!_networkStatus.isOffline) {
            _scheduleBackoff();
          }
        case AppSyncResult.transientFailure:
          _scheduleBackoff();
      }
    } catch (error) {
      // The sync service records the visible failure state. Keep this
      // coordinator best-effort so local writes are never rolled back.
      safeDebugLog('Automatic sync pass failed', error: error);
      _scheduleBackoff();
    } finally {
      _running = false;
      if (!_disposed && _pendingAgain) {
        _pendingAgain = false;
        _schedule();
      }
    }
  }

  void _handleNetworkStatusChanged() {
    if (_disposed) return;
    final current = _networkStatus.status;
    final previous = _lastNetworkStatus;
    _lastNetworkStatus = current;

    if (current != NetworkStatus.online) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (previous == NetworkStatus.online) return;

    _resetBackoff();
    _schedule(Duration.zero);
  }

  void _scheduleBackoff() {
    if (_disposed) return;
    if (!_networkStatus.isOnline) {
      return;
    }
    final multiplier = 1 << _retryAttempt.clamp(0, 20);
    final milliseconds = (_initialBackoff.inMilliseconds * multiplier).clamp(
      _initialBackoff.inMilliseconds,
      _maxBackoff.inMilliseconds,
    );
    final delay = Duration(milliseconds: milliseconds);
    _retryAttempt++;
    _retryNotBefore = DateTime.now().add(delay);
    _schedule(delay);
  }

  void _resetBackoff() {
    _retryAttempt = 0;
    _retryNotBefore = null;
  }

  void _dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _networkStatus.removeListener(_handleNetworkStatusChanged);
  }
}
