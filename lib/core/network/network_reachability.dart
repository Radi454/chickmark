import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../constants/supabase_config.dart';

/// Cloud reachability check.
///
/// `connectivity_plus` on macOS reads `NWPathMonitor.currentPath`
/// synchronously, but that path is `unsatisfied` until the monitor settles
/// asynchronously — so the first `checkConnectivity()` (app start, sync gate)
/// wrongly reports `none` and the app shows "Offline" despite a working
/// connection. We treat connectivity only as a fast positive hint; when it
/// reports no interface we confirm with a real TCP probe to the Supabase host
/// before declaring offline.
class NetworkReachability {
  static const Duration _probeTimeout = Duration(seconds: 4);

  /// True when the device can plausibly reach the cloud.
  ///
  /// Fast path: any active network interface is treated as online. Slow path
  /// (interface reports `none`): a TCP probe to the Supabase host decides,
  /// rescuing the connectivity_plus first-read false negative.
  static Future<bool> isOnline() async {
    List<ConnectivityResult> result;
    try {
      result = await Connectivity().checkConnectivity();
    } catch (_) {
      // Unsupported platform (e.g. unit tests) — assume online, skip the probe.
      return true;
    }
    final hasInterface =
        result.isNotEmpty && !result.contains(ConnectivityResult.none);
    if (hasInterface) return true;
    return _probeHost();
  }

  static Future<bool> _probeHost() async {
    final host = Uri.tryParse(SupabaseConfig.url)?.host ?? '';
    if (host.isEmpty) return false;
    try {
      final socket = await Socket.connect(host, 443, timeout: _probeTimeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
