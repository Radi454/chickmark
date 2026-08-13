import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../security/safe_debug_log.dart';
import 'network_reachability.dart';

enum NetworkStatus { unknown, online, offline }

typedef NetworkReachabilityCheck = Future<bool> Function();

/// App-lifetime source of truth for whether ChickMark can plausibly reach its
/// cloud endpoint. Connectivity events are hints that trigger one coalesced
/// reachability check; consumers react only to verified state transitions.
class NetworkStatusMonitor extends ChangeNotifier {
  NetworkStatusMonitor({
    NetworkReachabilityCheck? checkReachability,
    Stream<List<ConnectivityResult>>? connectivityStream,
    NetworkStatus initialStatus = NetworkStatus.unknown,
    bool startImmediately = true,
  }) : _checkReachability = checkReachability ?? NetworkReachability.isOnline,
       _connectivityStream =
           connectivityStream ?? Connectivity().onConnectivityChanged,
       _status = initialStatus {
    if (startImmediately) start();
  }

  final NetworkReachabilityCheck _checkReachability;
  final Stream<List<ConnectivityResult>> _connectivityStream;

  NetworkStatus _status;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<NetworkStatus>? _activeRefresh;
  bool _refreshQueued = false;
  bool _started = false;
  bool _disposed = false;

  NetworkStatus get status => _status;
  bool get isOnline => _status == NetworkStatus.online;
  bool get isOffline => _status == NetworkStatus.offline;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    try {
      _subscription = _connectivityStream.listen(
        (_) => unawaited(refresh()),
        onError: (Object error) {
          safeDebugLog('Connectivity stream error', error: error);
          _setStatus(NetworkStatus.unknown);
        },
      );
    } catch (error) {
      safeDebugLog('Connectivity listener unavailable', error: error);
    }
    unawaited(refresh());
  }

  /// Re-check reachability, coalescing overlapping lifecycle/connectivity
  /// requests. An exception is deliberately `unknown`, never online.
  Future<NetworkStatus> refresh() {
    final active = _activeRefresh;
    if (active != null) {
      _refreshQueued = true;
      return active;
    }

    late final Future<NetworkStatus> operation;
    operation = _performRefresh().whenComplete(() {
      if (identical(_activeRefresh, operation)) {
        _activeRefresh = null;
      }
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    });
    _activeRefresh = operation;
    return operation;
  }

  Future<NetworkStatus> _performRefresh() async {
    try {
      final reachable = await _checkReachability();
      final next = reachable ? NetworkStatus.online : NetworkStatus.offline;
      _setStatus(next);
      return next;
    } catch (error) {
      safeDebugLog('Network reachability check failed', error: error);
      _setStatus(NetworkStatus.unknown);
      return NetworkStatus.unknown;
    }
  }

  void _setStatus(NetworkStatus next) {
    if (_disposed || next == _status) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
