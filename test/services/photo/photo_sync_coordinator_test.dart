import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/photo/photo_sync_coordinator.dart';
import 'package:hatchaudit/services/photo/photo_sync_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockPhotoSyncService extends Mock implements PhotoSyncService {}

Future<void> _settle([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _MockPhotoSyncService sync;

  setUp(() {
    sync = _MockPhotoSyncService();
    when(() => sync.syncPending()).thenAnswer((_) async {});
  });

  tearDown(PhotoSyncCoordinator.disable);

  test('nudge is a no-op until enabled', () async {
    PhotoSyncCoordinator.nudge();
    await _settle();
    verifyNever(() => sync.syncPending());
  });

  test('nudge triggers a sync after the debounce when enabled', () async {
    PhotoSyncCoordinator.enable(
      service: sync,
      debounce: const Duration(milliseconds: 5),
    );

    PhotoSyncCoordinator.nudge();
    await _settle();

    verify(() => sync.syncPending()).called(1);
  });

  test('a burst of nudges coalesces into a single sync', () async {
    PhotoSyncCoordinator.enable(
      service: sync,
      debounce: const Duration(milliseconds: 15),
    );

    PhotoSyncCoordinator.nudge();
    PhotoSyncCoordinator.nudge();
    PhotoSyncCoordinator.nudge();
    await _settle();

    verify(() => sync.syncPending()).called(1);
  });

  test('disable cancels a pending sync', () async {
    PhotoSyncCoordinator.enable(
      service: sync,
      debounce: const Duration(milliseconds: 30),
    );

    PhotoSyncCoordinator.nudge();
    PhotoSyncCoordinator.disable();
    await _settle();

    verifyNever(() => sync.syncPending());
  });
}
