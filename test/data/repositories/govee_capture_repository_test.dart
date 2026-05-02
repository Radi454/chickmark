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
  late List<GoveeSpotCaptureModel> newSpots;
  late List<GoveeSpotReadingModel> newReadings;

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
      place: TemperaturePlace.eggStorageRoom,
      captureDate: '2026-05-02',
      status: 'completed',
      spotCount: 3,
      readingCount: 180,
      createdAt: now,
      updatedAt: now,
    );
    newCapture = oldCapture.copyWith(
      id: 'new-capture',
      tempAvg: 72.4,
      rhAvg: 56.8,
      updatedAt: now.add(const Duration(minutes: 10)),
    );
    newSpots = List.generate(3, (index) {
      final spotIndex = index + 1;
      return GoveeSpotCaptureModel(
        id: 'spot-$spotIndex',
        captureId: newCapture.id,
        spotIndex: spotIndex,
        spotLabel: 'Spot $spotIndex',
        warmupStartedAt: now.add(Duration(minutes: index * 10)),
        validStartedAt: now
            .add(Duration(minutes: index * 10))
            .add(const Duration(seconds: 60)),
        validEndedAt: now
            .add(Duration(minutes: index * 10))
            .add(const Duration(seconds: 120)),
        validDurationSeconds: 60,
        readingCount: 60,
        createdAt: now,
        updatedAt: now,
      );
    });
    newReadings = List.generate(60, (index) {
      return GoveeSpotReadingModel(
        id: 'reading-$index',
        captureId: newCapture.id,
        spotId: newSpots.first.id,
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
    'saveReplacement replaces existing capture for same scope atomically',
    () async {
      when(
        () => txn.query(
          'govee_daily_captures',
          where:
              'customerId = ? AND hatcheryId = ? AND place = ? AND captureDate = ?',
          whereArgs: [
            newCapture.customerId,
            newCapture.hatcheryId,
            newCapture.place.name,
            newCapture.captureDate,
          ],
          limit: 1,
        ),
      ).thenAnswer((_) async => [oldCapture.toMap()]);

      await repository.saveReplacement(
        capture: newCapture,
        spots: newSpots,
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
        () => txn.insert(
          'govee_daily_captures',
          newCapture.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      ).called(1);
      verify(
        () => txn.insert(
          'govee_spot_captures',
          newSpots.first.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      ).called(1);
      verify(
        () => txn.insert(
          'govee_spot_readings',
          newReadings.first.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        ),
      ).called(1);
    },
  );

  test('getCaptureForScope queries one place date capture', () async {
    when(
      () => db.query(
        'govee_daily_captures',
        where:
            'customerId = ? AND hatcheryId = ? AND place = ? AND captureDate = ?',
        whereArgs: [
          'customer-1',
          'hatchery-1',
          TemperaturePlace.eggStorageRoom.name,
          '2026-05-02',
        ],
        limit: 1,
      ),
    ).thenAnswer((_) async => [newCapture.toMap()]);

    final result = await repository.getCaptureForScope(
      customerId: 'customer-1',
      hatcheryId: 'hatchery-1',
      place: TemperaturePlace.eggStorageRoom,
      captureDate: '2026-05-02',
    );

    expect(result, isNotNull);
    expect(result!.id, newCapture.id);
  });

  test('getReadingsForSpot returns ordered bucketed readings', () async {
    when(
      () => db.query(
        'govee_spot_readings',
        where: 'spotId = ?',
        whereArgs: [newSpots.first.id],
        orderBy: 'readingIndex ASC',
      ),
    ).thenAnswer((_) async => newReadings.map((r) => r.toMap()).toList());

    final result = await repository.getReadingsForSpot(newSpots.first.id);

    expect(result, hasLength(60));
    expect(result.first.id, newReadings.first.id);
    expect(result.last.readingIndex, 59);
  });
}
