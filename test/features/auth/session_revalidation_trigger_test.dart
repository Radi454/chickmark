import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/features/auth/services/session_revalidation_trigger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a verified reconnect transition fires the callback once', () async {
    var reachable = false;
    final monitor = NetworkStatusMonitor(
      checkReachability: () async => reachable,
      connectivityStream: const Stream.empty(),
      initialStatus: NetworkStatus.offline,
      startImmediately: false,
    );
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async => calls++,
      networkStatus: monitor,
    );
    trigger.start();

    reachable = true;
    await monitor.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    await monitor.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    trigger.stop();
    monitor.dispose();
  });

  test('offline resume does not revalidate or recreate auth state', () async {
    final monitor = NetworkStatusMonitor(
      checkReachability: () async => false,
      connectivityStream: const Stream.empty(),
      initialStatus: NetworkStatus.offline,
      startImmediately: false,
    );
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async => calls++,
      networkStatus: monitor,
    );
    trigger.start();

    trigger.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
    trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);

    trigger.stop();
    monitor.dispose();
  });

  test('a callback that throws does not break later triggers', () async {
    var reachable = false;
    final monitor = NetworkStatusMonitor(
      checkReachability: () async => reachable,
      connectivityStream: const Stream.empty(),
      initialStatus: NetworkStatus.offline,
      startImmediately: false,
    );
    var calls = 0;
    final trigger = SessionRevalidationTrigger(
      onRevalidate: () async {
        calls++;
        throw StateError('boom');
      },
      networkStatus: monitor,
    );
    trigger.start();

    reachable = true;
    await monitor.refresh();
    await Future<void>.delayed(Duration.zero);
    trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);

    trigger.stop();
    monitor.dispose();
  });
}
