import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/services/sync/app_sync_coordinator.dart';

void main() {
  tearDown(AppSyncCoordinator.disable);

  NetworkStatusMonitor onlineMonitor() => NetworkStatusMonitor(
    checkReachability: () async => true,
    connectivityStream: const Stream.empty(),
    initialStatus: NetworkStatus.online,
    startImmediately: false,
  );

  test('coalesces a burst of local-write nudges into one sync', () async {
    var runs = 0;
    AppSyncCoordinator.enable(
      sync: () async {
        runs += 1;
        return AppSyncResult.success;
      },
      networkStatus: onlineMonitor(),
      debounce: const Duration(milliseconds: 10),
    );

    AppSyncCoordinator.nudge();
    AppSyncCoordinator.nudge();
    AppSyncCoordinator.nudge();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(runs, 1);
  });

  test('runs once more when data changes during an active sync', () async {
    var runs = 0;
    final firstRunStarted = Completer<void>();
    final finishFirstRun = Completer<void>();
    AppSyncCoordinator.enable(
      sync: () async {
        runs += 1;
        if (runs == 1) {
          firstRunStarted.complete();
          await finishFirstRun.future;
        }
        return AppSyncResult.success;
      },
      networkStatus: onlineMonitor(),
      debounce: const Duration(milliseconds: 10),
    );

    AppSyncCoordinator.nudge(immediate: true);
    await firstRunStarted.future;
    AppSyncCoordinator.nudge(immediate: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    finishFirstRun.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(runs, 2);
  });

  test(
    'definitive offline state suppresses repeated automatic nudges',
    () async {
      final monitor = NetworkStatusMonitor(
        checkReachability: () async => false,
        connectivityStream: const Stream.empty(),
        initialStatus: NetworkStatus.offline,
        startImmediately: false,
      );
      var runs = 0;
      AppSyncCoordinator.enable(
        sync: () async {
          runs++;
          return AppSyncResult.success;
        },
        networkStatus: monitor,
        debounce: const Duration(milliseconds: 5),
      );

      AppSyncCoordinator.nudge(immediate: true);
      AppSyncCoordinator.nudge(immediate: true);
      AppSyncCoordinator.nudge(immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(runs, 0);
    },
  );

  test('one real reconnect transition releases one queued sync', () async {
    var reachable = false;
    final monitor = NetworkStatusMonitor(
      checkReachability: () async => reachable,
      connectivityStream: const Stream.empty(),
      initialStatus: NetworkStatus.offline,
      startImmediately: false,
    );
    var runs = 0;
    AppSyncCoordinator.enable(
      sync: () async {
        runs++;
        return AppSyncResult.success;
      },
      networkStatus: monitor,
      debounce: const Duration(milliseconds: 5),
    );
    AppSyncCoordinator.nudge(immediate: true);
    AppSyncCoordinator.nudge(immediate: true);

    reachable = true;
    await monitor.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(runs, 1);
  });

  test(
    'uncertain sync failure retries with backoff instead of looping',
    () async {
      var runs = 0;
      AppSyncCoordinator.enable(
        sync: () async {
          runs++;
          return runs == 1
              ? AppSyncResult.transientFailure
              : AppSyncResult.success;
        },
        networkStatus: onlineMonitor(),
        debounce: const Duration(milliseconds: 1),
        initialBackoff: const Duration(milliseconds: 30),
        maxBackoff: const Duration(milliseconds: 60),
      );

      AppSyncCoordinator.nudge(immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(runs, 1);

      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(runs, 2);
    },
  );
}
