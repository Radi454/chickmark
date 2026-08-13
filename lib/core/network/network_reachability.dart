import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../constants/supabase_config.dart';

/// Cloud reachability check.
///
/// `connectivity_plus` reports interfaces, not usable internet. ChickMark
/// therefore confirms every supported-platform result with a TCP probe to the
/// configured Supabase host. This also avoids treating captive or uplink-less
/// Wi-Fi as cloud connectivity. A reported `none` is still probed because
/// macOS can briefly expose an unsettled `NWPathMonitor` at startup.
class NetworkReachability {
  static const Duration _probeTimeout = Duration(seconds: 4);

  /// True when the device can plausibly reach the cloud.
  ///
  /// Unsupported platforms (notably unit tests without the plugin) retain the
  /// prior optimistic fallback; production platforms must reach the host.
  static Future<bool> isOnline() async {
    List<ConnectivityResult> results;
    try {
      results = await Connectivity().checkConnectivity();
    } catch (_) {
      // Unsupported platform (e.g. unit tests) — assume online, skip the probe.
      return true;
    }
    // dart:io sockets are unavailable in a browser. Web intentionally falls
    // back to interface state; failed Supabase work is still classified as
    // transient and retried with coordinator backoff rather than looped.
    if (kIsWeb) {
      return results.isNotEmpty &&
          !results.every((result) => result == ConnectivityResult.none);
    }
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
