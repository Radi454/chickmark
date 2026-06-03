import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DatabaseHelper {}

class MockTransaction extends Mock implements Transaction {}

void main() {
  late MockDatabase db;
  late MockDatabaseHelper dbHelper;
  late MockTransaction txn;
  late GoveeCaptureRepository repository;

  final now = DateTime.parse('2026-05-02T10:00:00');
  late GoveeDailyCaptureModel oldCapture;
  late GoveeDailyCaptureModel newCapture;
  late List<GoveePlaceReadingModel> newReadings;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    db = MockDatabase();
    dbHelper = MockDatabaseHelper();
    txn = MockTransaction();
    repository = GoveeCaptureRepository(dbHelper: dbHelper);

    oldCapture = GoveeDailyCaptureModel(
      id: 'old-capture',
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      stationKey: 'egg',
      place: TemperaturePlace.eggStorageRoom,
      captureDate: '2026-05-02',
      status: 'completed',
      readingCount: 180,
      createdAt: now,
      updatedAt: now,
    );
    newCapture = oldCapture.copyWith(
      id: 'new-capture',
      tempAvg: 72.4,
      tempSd: 1.23,
      tempCvPct: 1.7,
      rhAvg: 56.8,
      rhSd: 2.1,
      rhCvPct: 3.7,
      readingCount: 100,
      updatedAt: now.add(const Duration(minutes: 10)),
    );
    newReadings = List.generate(100, (index) {
      return GoveePlaceReadingModel(
        id: 'reading-$index',
        captureId: newCapture.id,
        readingIndex: index,
        recordedAt: now.add(Duration(seconds: index)),
        temperatureFahrenheit: 70 + (index / 10),
        humidity: 55 + (index / 20),
        createdAt: now,
      );
    });

    when(() => dbHelper.db).thenAnswer((_) async => db);
    when(
      () => db.query(
        any(),
        columns: any(named: 'columns'),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
        groupBy: any(named: 'groupBy'),
        having: any(named: 'having'),
        orderBy: any(named: 'orderBy'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
        distinct: any(named: 'distinct'),
      ),
    ).thenAnswer((_) async => <Map<String, Object?>>[]);
    when(
      () => txn.query(
        any(),
        columns: any(named: 'columns'),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
        groupBy: any(named: 'groupBy'),
        having: any(named: 'having'),
        orderBy: any(named: 'orderBy'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
        distinct: any(named: 'distinct'),
      ),
    ).thenAnswer((_) async => <Map<String, Object?>>[]);
    when(
      () => txn.delete(
        any(),
        where: any(named: 'where'),
        whereArgs: any(named: 'whereArgs'),
      ),
    ).thenAnswer((_) async => 1);
    when(
      () => txn.insert(
        any(),
        any(),
        conflictAlgorithm: any(named: 'conflictAlgorithm'),
      ),
    ).thenAnswer((_) async => 1);
    when(() => db.transaction<void>(any())).thenAnswer((invocation) {
      final action =
          invocation.positionalArguments.single
              as Future<void> Function(Transaction);
      return action(txn);
    });
  });

  test(
    'saveReplacement writes one daily capture row with chart point JSON',
    () async {
      when(
        () => txn.query(
          'govee_daily_captures',
          where:
              'customerId = ? AND hatcheryId = ? AND place = ? AND machineId = ? AND captureDate = ?',
          whereArgs: [
            newCapture.customerId,
            newCapture.hatcheryId,
            newCapture.place.name,
            '',
            newCapture.captureDate,
          ],
          limit: 1,
        ),
      ).thenAnswer((_) async => [oldCapture.toMap()]);

      await repository.saveReplacement(
        capture: newCapture,
        readings: newReadings,
      );

      verify(() => db.transaction<void>(any())).called(1);
      verify(
        () => txn.delete(
          'govee_daily_captures',
          where: 'id = ?',
          whereArgs: [oldCapture.id],
        ),
      ).called(1);
      verify(
        () => txn.insert('govee_daily_captures', {
          ...newCapture.toMap(),
          'machineId': '',
          'chartPointsJson': GoveePlaceReadingModel.listToJson(newReadings),
        }),
      ).called(1);
      verifyNever(
        () => txn.insert(
          'govee_spot_captures',
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        ),
      );
      verifyNever(
        () => txn.insert(
          'govee_spot_readings',
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        ),
      );
      verifyNever(
        () => txn.insert(
          'govee_place_readings',
          any(),
          conflictAlgorithm: any(named: 'conflictAlgorithm'),
        ),
      );
    },
  );

  test(
    'saveReplacement stores raw readings and clears prior raw rows',
    () async {
      when(
        () => txn.query(
          'govee_daily_captures',
          where:
              'customerId = ? AND hatcheryId = ? AND place = ? AND machineId = ? AND captureDate = ?',
          whereArgs: [
            newCapture.customerId,
            newCapture.hatcheryId,
            newCapture.place.name,
            '',
            newCapture.captureDate,
          ],
          limit: 1,
        ),
      ).thenAnswer((_) async => [oldCapture.toMap()]);

      await repository.saveReplacement(
        capture: newCapture,
        readings: newReadings,
        rawReadings: newReadings,
      );

      verify(
        () => txn.delete(
          'govee_capture_readings',
          where: 'captureId = ?',
          whereArgs: [oldCapture.id],
        ),
      ).called(1);

      final inserted = verify(
        () => txn.insert(
          'govee_capture_readings',
          captureAny(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      ).captured;

      expect(inserted, hasLength(newReadings.length));
      expect(inserted.first, {
        'id': 'reading-0',
        'captureId': newCapture.id,
        'recordedAtMs':
            DateTime.parse('2026-05-02T10:00:00').millisecondsSinceEpoch,
        'temperatureFahrenheit': 70.0,
        'humidity': 55.0,
      });
    },
  );

  test(
    'getCaptureForScope queries one machine-aware place date capture',
    () async {
      when(
        () => db.query(
          'govee_daily_captures',
          where:
              'customerId = ? AND hatcheryId = ? AND place = ? AND machineId = ? AND captureDate = ?',
          whereArgs: [
            'customer-1',
            'hatchery-1',
            TemperaturePlace.eggStorageRoom.name,
            'setter-1',
            '2026-05-02',
          ],
          limit: 1,
        ),
      ).thenAnswer((_) async => [newCapture.toMap()]);

      final result = await repository.getCaptureForScope(
        customerId: 'customer-1',
        hatcheryId: 'hatchery-1',
        stationKey: 'egg',
        place: TemperaturePlace.eggStorageRoom,
        machineId: 'setter-1',
        captureDate: '2026-05-02',
      );

      expect(result, isNotNull);
      expect(result!.id, newCapture.id);
    },
  );

  test('getCapturesForDashboard queries date-scoped hatchery captures', () async {
    when(
      () => db.query(
        'govee_daily_captures',
        where: 'customerId = ? AND hatcheryId = ? AND captureDate = ?',
        whereArgs: ['customer-1', 'hatchery-1', '2026-05-02'],
        orderBy:
            'captureDate DESC, stationKey ASC, place ASC, machineId ASC, updatedAt DESC',
      ),
    ).thenAnswer((_) async => [newCapture.toMap()]);

    final result = await repository.getCapturesForDashboard(
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      captureDate: '2026-05-02',
    );

    expect(result, hasLength(1));
    expect(result.single.id, newCapture.id);
  });

  test(
    'getReadingsForCapture returns chart points from capture JSON',
    () async {
      final captureWithChartPoints = newCapture.copyWith(
        chartPointsJson: GoveePlaceReadingModel.listToJson(newReadings),
      );
      when(
        () => db.query(
          'govee_daily_captures',
          where: 'id = ?',
          whereArgs: [newCapture.id],
          limit: 1,
        ),
      ).thenAnswer((_) async => [captureWithChartPoints.toMap()]);

      final result = await repository.getReadingsForCapture(newCapture.id);

      expect(result, hasLength(100));
      expect(result.first.id, '${newCapture.id}-0');
      expect(result.last.readingIndex, 99);
    },
  );
}
