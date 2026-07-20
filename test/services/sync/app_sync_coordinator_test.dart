import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/sync/app_sync_coordinator.dart';

void main() {
  tearDown(AppSyncCoordinator.disable);

  test('coalesces a burst of local-write nudges into one sync', () async {
    var runs = 0;
    AppSyncCoordinator.enable(
      sync: () async {
        runs += 1;
      },
      debounce: const Duration(milliseconds: 10),
      listenForConnectivity: false,
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
      },
      debounce: const Duration(milliseconds: 10),
      listenForConnectivity: false,
    );

    AppSyncCoordinator.nudge(immediate: true);
    await firstRunStarted.future;
    AppSyncCoordinator.nudge(immediate: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    finishFirstRun.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(runs, 2);
  });
}
