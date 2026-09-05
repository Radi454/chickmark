import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_weighing_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/breeder_weighing_sample_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_weighing_session_repository.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_weighing_service.dart';

import '../../support/test_database.dart';

/// Verifies `BreederWeighingService`'s derived-figure arithmetic (mean,
/// uniformity, coefficient of variation — breeder-flock-performance ticket
/// 13, design doc section 9), its blank-not-zero edge cases, the ±10%
/// uniformity window boundary, and its Ross 308 body-weight benchmark
/// comparison (age- and sex-correct, with the profile version and axis
/// recorded).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  final service = BreederWeighingService();
  final sessions = BreederWeighingSessionRepository();
  final samples = BreederWeighingSampleRepository();
  final customers = CustomerRepository();
  final flocks = FlockRepository();
  final houses = PoultryHierarchyRepository();
  var counter = 0;

  Future<(FlockModel, HouseModel)> makeFlockAndHouse(DateTime entryDate) async {
    counter++;
    final customerId = 'weighing-customer-$counter';
    await customers.insertCustomer(
      CustomerModel(
        id: customerId,
        name: 'Weighing Customer $counter',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'tester',
      ),
    );
    final flock = FlockModel(
      id: 'weighing-flock-$counter',
      customerId: customerId,
      flockId: 'WF-$counter',
      breed: 'Ross308',
      entryDate: entryDate,
      status: FlockModel.activeStatus,
    );
    await flocks.insertFlock(flock);
    final house = HouseModel(
      id: 'weighing-house-$counter',
      flockId: flock.id,
      name: 'House $counter',
    );
    await houses.saveHouse(house);
    return (flock, house);
  }

  group('deriveFigures (pure arithmetic)', () {
    test('empty samples yield blank figures, not zero', () {
      final figures = service.deriveFigures(const []);
      expect(figures.sampleCount, 0);
      expect(figures.meanWeightG, isNull);
      expect(figures.uniformityPct, isNull);
      expect(figures.cvPct, isNull);
    });

    test('a single sample: 100% uniform, but CV is blank (undefined for n=1)', () {
      final figures = service.deriveFigures([500.0]);
      expect(figures.sampleCount, 1);
      expect(figures.meanWeightG, 500.0);
      expect(figures.uniformityPct, 100.0);
      expect(figures.cvPct, isNull);
    });

    test('mean/uniformity/CV match CalculationUtils conventions for a simple set', () {
      // mean = 500, sample stdDev (n-1) = sqrt(((-100)^2+0^2+100^2)/2) = 100
      final figures = service.deriveFigures([400.0, 500.0, 600.0]);
      expect(figures.sampleCount, 3);
      expect(figures.meanWeightG, 500.0);
      // Every value is within +/-10% of 500 (450-550)? 400 and 600 are not.
      expect(figures.uniformityPct, closeTo(33.3, 0.1));
      expect(figures.cvPct, 20.0); // 100 / 500 * 100
    });

    test('uniformity window boundary: exactly +/-10% counts as uniform', () {
      // mean = 100; 90 and 110 sit exactly on the +/-10% boundary.
      final figures = service.deriveFigures([90.0, 100.0, 110.0]);
      expect(figures.meanWeightG, 100.0);
      expect(figures.uniformityPct, 100.0);
    });

    test('uniformity window boundary: just outside +/-10% is excluded', () {
      final figures = service.deriveFigures([89.9, 100.0, 110.1]);
      expect(figures.uniformityPct, closeTo(33.3, 0.1));
    });

    test('CV is blank when the mean is zero, unlike cvPercent\'s 0.0 fallback', () {
      final figures = service.deriveFigures([0.0, 0.0, 0.0]);
      expect(figures.meanWeightG, 0.0);
      expect(figures.cvPct, isNull);
    });
  });

  group('officialWeightTarget', () {
    test('picks the female target for the flock\'s age', () async {
      final (flock, _) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      final comparison = await service.officialWeightTarget(
        flock: flock,
        sex: BreederWeighingSessionSex.female,
        sessionDate: DateTime(2026, 1, 8), // age 7 days = ageWeek 1
      );
      expect(comparison.profile, isNotNull);
      expect(comparison.targetWeightG, 115.0);
      expect(comparison.profile!.guideVersion, isNotEmpty);
      expect(comparison.axis, isNotNull);
    });

    test('picks the male target for the same age (sex-correct)', () async {
      final (flock, _) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      final comparison = await service.officialWeightTarget(
        flock: flock,
        sex: BreederWeighingSessionSex.male,
        sessionDate: DateTime(2026, 1, 8),
      );
      expect(comparison.targetWeightG, 150.0);
    });
  });

  group('createSession / computeAndSaveDerived', () {
    test('a session with samples derives and persists mean/uniformity/CV plus the comparison', () async {
      final (flock, house) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      final saved = await service.createSession(
        flock: flock,
        houseId: house.id,
        sessionDate: DateTime(2026, 1, 8),
        sex: BreederWeighingSessionSex.female,
        method: 'Individual bird scale',
        sampleSize: 3,
        weights: [100.0, 115.0, 130.0],
      );

      expect(saved.hasDerivedFigures, isTrue);
      expect(saved.derivedMeanWeightG, 115.0);
      expect(saved.comparisonTargetWeightG, 115.0);
      expect(saved.comparisonProfileId, isNotNull);
      expect(saved.comparisonProfileGuideVersion, isNotEmpty);
      expect(saved.comparisonAxisKind, BreederWeighingComparisonAxisKind.official);

      final reloaded = await sessions.getById(saved.id);
      expect(reloaded!.derivedMeanWeightG, 115.0);
      expect(reloaded.comparisonTargetWeightG, 115.0);
    });

    test('a summary-only session (no samples) has no derived figures', () async {
      final (flock, house) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      final saved = await service.createSession(
        flock: flock,
        houseId: house.id,
        sessionDate: DateTime(2026, 1, 8),
        sex: BreederWeighingSessionSex.female,
        method: 'Batch/platform scale',
        sampleSize: 50,
      );

      expect(saved.hasDerivedFigures, isFalse);
      expect(saved.derivedMeanWeightG, isNull);
      expect(saved.derivedUniformityPct, isNull);
      expect(saved.derivedCvPct, isNull);
      // The comparison is still recorded even without samples, since it
      // depends only on flock/sex/age, not on the sample weights.
      expect(saved.comparisonTargetWeightG, 115.0);

      final storedSamples = await samples.getForSession(saved.id);
      expect(storedSamples, isEmpty);
    });

    test('a negative weight is rejected', () async {
      final (flock, house) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      expect(
        () => service.createSession(
          flock: flock,
          houseId: house.id,
          sessionDate: DateTime(2026, 1, 8),
          sex: BreederWeighingSessionSex.female,
          method: 'Individual bird scale',
          sampleSize: 1,
          weights: [-5.0],
        ),
        throwsArgumentError,
      );
    });

    test('a non-positive sample size is rejected', () async {
      final (flock, house) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      expect(
        () => service.createSession(
          flock: flock,
          houseId: house.id,
          sessionDate: DateTime(2026, 1, 8),
          sex: BreederWeighingSessionSex.female,
          method: 'Individual bird scale',
          sampleSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('updateSamples recomputes figures and clearing weights returns to summary-only', () async {
      final (flock, house) = await makeFlockAndHouse(DateTime(2026, 1, 1));
      var saved = await service.createSession(
        flock: flock,
        houseId: house.id,
        sessionDate: DateTime(2026, 1, 8),
        sex: BreederWeighingSessionSex.female,
        method: 'Individual bird scale',
        sampleSize: 2,
        weights: [100.0, 120.0],
      );
      expect(saved.derivedMeanWeightG, 110.0);

      saved = await service.updateSamples(session: saved, flock: flock, weights: const []);
      expect(saved.hasDerivedFigures, isFalse);
    });
  });
}
