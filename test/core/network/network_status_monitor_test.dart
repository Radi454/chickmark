import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';

void main() {
  test(
    'starts unknown and publishes definitive offline after probing',
    () async {
      final monitor = NetworkStatusMonitor(
        checkReachability: () async => false,
        connectivityStream: const Stream.empty(),
        startImmediately: false,
      );

      expect(monitor.status, NetworkStatus.unknown);
      expect(await monitor.refresh(), NetworkStatus.offline);
      expect(monitor.status, NetworkStatus.offline);

      monitor.dispose();
    },
  );

  test(
    'repeated equivalent connectivity events do not republish state',
    () async {
      final events = StreamController<List<ConnectivityResult>>();
      var notifications = 0;
      final monitor = NetworkStatusMonitor(
        checkReachability: () async => false,
        connectivityStream: events.stream,
        startImmediately: false,
      )..addListener(() => notifications++);
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.status, NetworkStatus.offline);
      expect(notifications, 1);

      events.add([ConnectivityResult.none]);
      events.add([ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(monitor.status, NetworkStatus.offline);
      expect(notifications, 1);

      monitor.dispose();
      await events.close();
    },
  );
}
