import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/govee/providers/govee_records_provider.dart';

class _MockGoveeRepo extends Mock implements GoveeCaptureRepository {}

GoveeDailyCaptureModel _cap(
  String id, {
  String customerId = 'c1',
  String hatcheryId = 'h1',
  String captureDate = '2026-05-01',
  TemperaturePlace place = TemperaturePlace.setterRoom,
  String syncStatus = 'synced',
  int readingCount = 10,
  DateTime? updatedAt,
}) => GoveeDailyCaptureModel(
  id: id,
  customerId: customerId,
  hatcheryId: hatcheryId,
  place: place,
  captureDate: captureDate,
  status: 'completed',
  readingCount: readingCount,
  syncStatus: syncStatus,
  createdAt: DateTime(2026, 5, 1),
  updatedAt: updatedAt ?? DateTime(2026, 5, 1),
);

void main() {
  late _MockGoveeRepo repo;

  setUp(() {
    repo = _MockGoveeRepo();
  });

  GoveeRecordsProvider provider() => GoveeRecordsProvider(repository: repo);

  void stub(List<GoveeDailyCaptureModel> captures) {
    when(() => repo.getAllCaptures()).thenAnswer((_) async => captures);
  }

  test('groups captures by customer + hatchery + date', () async {
    stub([
      _cap('a', place: TemperaturePlace.setterRoom),
      _cap('b', place: TemperaturePlace.hatcherRoom),
      _cap('c', captureDate: '2026-05-02'),
      _cap('d', customerId: 'c2'),
    ]);

    final p = provider();
    await p.refresh();
    final groups = p.visibleGroups;

    // (c1,h1,05-01) has 2 spots; (c1,h1,05-02); (c2,h1,05-01) => 3 groups.
    expect(groups.length, 3);
    final day1 = groups.firstWhere(
      (g) => g.customerId == 'c1' && g.captureDate == '2026-05-01',
    );
    expect(day1.captures.length, 2);
    expect(day1.totalReadings, 20);
  });

  test('sorts groups by most recently updated capture first', () async {
    stub([
      _cap(
        'future-old',
        captureDate: '2027-05-01',
        updatedAt: DateTime(2026, 5, 1),
      ),
      _cap(
        'today-new',
        captureDate: '2026-06-11',
        updatedAt: DateTime(2026, 6, 11, 17, 42),
      ),
      _cap(
        'middle',
        captureDate: '2026-05-02',
        updatedAt: DateTime(2026, 5, 2),
      ),
    ]);

    final p = provider();
    await p.refresh();
    expect(p.visibleGroups.map((g) => g.captureDate), [
      '2026-06-11',
      '2026-05-02',
      '2027-05-01',
    ]);
  });

  test(
    'mergeSavedCapture surfaces a floating-panel save immediately',
    () async {
      stub([
        _cap(
          'future-old',
          captureDate: '2027-05-01',
          updatedAt: DateTime(2026, 5, 1),
        ),
      ]);

      final p = provider();
      await p.refresh();

      p.mergeSavedCapture(
        _cap(
          'today-new',
          customerId: 'c-local',
          hatcheryId: 'h-local',
          captureDate: '2026-06-11',
          place: TemperaturePlace.chickHoldingArea,
          syncStatus: 'pending',
          readingCount: 264,
          updatedAt: DateTime(2026, 6, 11, 17, 42),
        ),
      );

      final groups = p.visibleGroups;
      expect(groups.first.customerId, 'c-local');
      expect(groups.first.captureDate, '2026-06-11');
      expect(groups.first.totalReadings, 264);
      expect(groups.first.sync, 'pending');
    },
  );

  test('rolls up sync state: failed > pending > synced', () async {
    stub([
      _cap('a', syncStatus: 'synced'),
      _cap('b', place: TemperaturePlace.hatcherRoom, syncStatus: 'pending'),
      _cap('c', place: TemperaturePlace.eggStorageRoom, syncStatus: 'failed'),
    ]);

    final p = provider();
    await p.refresh();
    expect(p.visibleGroups.single.sync, 'failed');
  });

  test('pending when no failures', () async {
    stub([
      _cap('a', syncStatus: 'synced'),
      _cap('b', place: TemperaturePlace.hatcherRoom, syncStatus: 'pending'),
    ]);
    final p = provider();
    await p.refresh();
    expect(p.visibleGroups.single.sync, 'pending');
  });

  test('deleteCapture removes the row and tombstones via repo', () async {
    stub([
      _cap('a', place: TemperaturePlace.setterRoom),
      _cap('b', place: TemperaturePlace.hatcherRoom),
    ]);
    when(() => repo.deleteCapture(any())).thenAnswer((_) async {});

    final p = provider();
    await p.refresh();
    expect(p.visibleGroups.single.captures.length, 2);

    await p.deleteCapture(_cap('a'));

    verify(() => repo.deleteCapture('a')).called(1);
    final remaining = p.visibleGroups.single.captures;
    expect(remaining.length, 1);
    expect(remaining.single.id, 'b');
  });

  test('search filters by resolved customer name and place', () async {
    stub([
      _cap('a', customerId: 'c-acme', place: TemperaturePlace.setterRoom),
      _cap('b', customerId: 'c-globex', place: TemperaturePlace.hatcherRoom),
    ]);
    final p = provider()
      ..setResolver(
        GoveeRecordResolver(
          customerName: (id) => id == 'c-acme' ? 'Acme Farms' : 'Globex',
          hatcheryName: (id) => 'Hatchery $id',
        ),
      );
    await p.refresh();
    expect(p.visibleGroups.length, 2);

    p.setSearch('acme');
    expect(p.visibleGroups.map((g) => g.customerId), ['c-acme']);

    p.setSearch('hatcher room'); // place label on the globex group
    expect(p.visibleGroups.map((g) => g.customerId), ['c-globex']);
  });
}
