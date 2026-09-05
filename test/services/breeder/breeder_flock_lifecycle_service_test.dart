import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/breeder_flock_milestone_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/repositories/customer_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_flock_lifecycle_service.dart';

import '../../support/test_database.dart';

/// Verifies the single place breeder-flock-performance calculations live
/// (design doc section 7): total age, official production-week lookup read
/// from the Ross 308 profile's `productionWeek` column (never derived by
/// arithmetic), and the milestone-aligned comparison axis offered only past
/// the one-week tolerance (design section 3.1).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  final service = BreederFlockLifecycleService();
  final customers = CustomerRepository();
  final flocks = FlockRepository();
  var flockCounter = 0;

  Future<FlockModel> makeFlock(DateTime entryDate) async {
    flockCounter++;
    final customerId = 'lifecycle-customer-$flockCounter';
    await customers.insertCustomer(
      CustomerModel(
        id: customerId,
        name: 'Lifecycle Customer $flockCounter',
        createdAt: DateTime(2026, 1, 1),
        createdBy: 'tester',
      ),
    );
    final flock = FlockModel(
      id: 'lifecycle-flock-$flockCounter',
      customerId: customerId,
      flockId: 'F-$flockCounter',
      breed: 'Ross308', // no space — must still match the "Ross 308" profile.
      entryDate: entryDate,
      status: FlockModel.activeStatus,
    );
    await flocks.insertFlock(flock);
    return flock;
  }

  group('ageSummary', () {
    test('computes whole days and whole weeks from entryDate', () {
      final now = DateTime(2026, 1, 1);
      final flock = FlockModel(
        id: 'age-1',
        customerId: 'c',
        flockId: 'F',
        breed: 'Ross308',
        entryDate: now.subtract(const Duration(days: 25 * 7)),
      );
      final age = service.ageSummary(flock, now: now);
      expect(age.ageDays, 175);
      expect(age.ageWeeks, 25);
    });

    test('zero age on entry day', () {
      final now = DateTime(2026, 1, 1);
      final flock = FlockModel(
        id: 'age-2',
        customerId: 'c',
        flockId: 'F',
        breed: 'Ross308',
        entryDate: now,
      );
      final age = service.ageSummary(flock, now: now);
      expect(age.ageDays, 0);
      expect(age.ageWeeks, 0);
    });

    test('partial week floors down, not up', () {
      final now = DateTime(2026, 1, 1);
      // 25 weeks + 3 days: still 25 whole weeks.
      final flock = FlockModel(
        id: 'age-3',
        customerId: 'c',
        flockId: 'F',
        breed: 'Ross308',
        entryDate: now.subtract(const Duration(days: 25 * 7 + 3)),
      );
      final age = service.ageSummary(flock, now: now);
      expect(age.ageDays, 25 * 7 + 3);
      expect(age.ageWeeks, 25);
    });
  });

  group('officialProductionWeek', () {
    final now = DateTime(2026, 1, 1);

    test('is null before the profile production range begins', () async {
      final flock = await makeFlock(now.subtract(const Duration(days: 24 * 7)));
      final result = await service.officialProductionWeek(flock, now: now);
      expect(result.ageWeeks, 24);
      expect(result.productionWeek, isNull);
      expect(result.isPreProduction, isTrue);
      expect(result.profile, isNotNull);
      expect(result.profile!.breed, 'Ross 308');
    });

    test('reads the official productionWeek at the profile boundary (25w -> 1)', () async {
      final flock = await makeFlock(now.subtract(const Duration(days: 25 * 7)));
      final result = await service.officialProductionWeek(flock, now: now);
      expect(result.ageWeeks, 25);
      expect(result.productionWeek, 1);
      expect(result.isPreProduction, isFalse);
    });

    test('reads the official productionWeek deeper into lay (34w -> 10)', () async {
      final flock = await makeFlock(now.subtract(const Duration(days: 34 * 7)));
      final result = await service.officialProductionWeek(flock, now: now);
      expect(result.ageWeeks, 34);
      expect(result.productionWeek, 10);
    });

    test('records the official axis and the profile version used', () async {
      final flock = await makeFlock(now.subtract(const Duration(days: 30 * 7)));
      final result = await service.officialProductionWeek(flock, now: now);
      expect(result.axis.kind, ComparisonAxisKind.official);
      expect(result.axis.offsetWeeks, 0);
      expect(result.profile!.guideVersion, isNotEmpty);
    });
  });

  group(
    'hasEnteredProductionRange (breeder-flock-performance ticket 10, design '
    'doc section 5.1: the egg section appears only once the flock has '
    'entered the benchmark profile\'s official production range)',
    () {
      final now = DateTime(2026, 1, 1);

      test('is false before the profile production range begins', () async {
        final flock = await makeFlock(now.subtract(const Duration(days: 24 * 7)));
        expect(await service.hasEnteredProductionRange(flock, now: now), isFalse);
      });

      test('is true at the profile boundary (25w)', () async {
        final flock = await makeFlock(now.subtract(const Duration(days: 25 * 7)));
        expect(await service.hasEnteredProductionRange(flock, now: now), isTrue);
      });

      test('is true deeper into lay', () async {
        final flock = await makeFlock(now.subtract(const Duration(days: 34 * 7)));
        expect(await service.hasEnteredProductionRange(flock, now: now), isTrue);
      });
    },
  );

  group('comparisonAxes', () {
    final now = DateTime(2026, 1, 1);

    test('offers only the official axis when within the one-week tolerance', () async {
      // Flock is 30 weeks old; recorded 5% milestone at flock-age 26 weeks
      // (official 5%-production age is 25 weeks) -> offset is exactly 1
      // week, which must NOT clear the tolerance.
      final entryDate = now.subtract(const Duration(days: 30 * 7));
      final flock = await makeFlock(entryDate);
      await service.recordMilestone(
        flockId: flock.id,
        eventType: BreederFlockMilestoneType.fivePercentProduction,
        eventDate: entryDate.add(const Duration(days: 26 * 7)),
      );

      final offer = await service.comparisonAxes(flock, now: now);
      expect(offer.hasMilestoneAlignedAxis, isFalse);
      expect(offer.official.axis.kind, ComparisonAxisKind.official);
    });

    test('offers a milestone-aligned axis past the one-week tolerance', () async {
      // Recorded 5% milestone at flock-age 27 weeks vs official 25 weeks:
      // offset is 2 weeks, past tolerance.
      final entryDate = now.subtract(const Duration(days: 30 * 7));
      final flock = await makeFlock(entryDate);
      await service.recordMilestone(
        flockId: flock.id,
        eventType: BreederFlockMilestoneType.fivePercentProduction,
        eventDate: entryDate.add(const Duration(days: 27 * 7)),
      );

      final offer = await service.comparisonAxes(flock, now: now);
      expect(offer.hasMilestoneAlignedAxis, isTrue);
      final milestoneAligned = offer.milestoneAligned!;
      expect(milestoneAligned.axis.kind, ComparisonAxisKind.milestoneAligned);
      expect(milestoneAligned.axis.offsetWeeks, 2);
      // Actual age is 30 weeks; guide-equivalent age is 30 - 2 = 28 weeks.
      expect(milestoneAligned.guideAgeWeeks, 28);
      // The official axis is still present, unreplaced, alongside it.
      expect(offer.official.axis.kind, ComparisonAxisKind.official);
      expect(offer.official.guideAgeWeeks, 30);
      // Both results carry the same profile version.
      expect(milestoneAligned.profile!.guideVersion, offer.official.profile!.guideVersion);
    });

    test('never offers a milestone axis with no recorded 5% milestone', () async {
      final entryDate = now.subtract(const Duration(days: 30 * 7));
      final flock = await makeFlock(entryDate);
      final offer = await service.comparisonAxes(flock, now: now);
      expect(offer.hasMilestoneAlignedAxis, isFalse);
    });
  });

  group('milestone recording and retrieval', () {
    test('records and retrieves milestones for a flock', () async {
      final entryDate = DateTime(2025, 1, 1);
      final flock = await makeFlock(entryDate);

      await service.recordMilestone(
        flockId: flock.id,
        eventType: BreederFlockMilestoneType.grading,
        eventDate: entryDate.add(const Duration(days: 10)),
      );
      await service.recordMilestone(
        flockId: flock.id,
        eventType: BreederFlockMilestoneType.firstEgg,
        eventDate: entryDate.add(const Duration(days: 150)),
      );

      final milestones = await service.milestonesForFlock(flock.id);
      expect(milestones, hasLength(2));
      expect(
        milestones.map((m) => m.eventType),
        containsAll([
          BreederFlockMilestoneType.grading,
          BreederFlockMilestoneType.firstEgg,
        ]),
      );
    });

    test('recording the same event type again corrects the date, not append', () async {
      final entryDate = DateTime(2025, 1, 1);
      final flock = await makeFlock(entryDate);

      final first = await service.recordMilestone(
        flockId: flock.id,
        eventType: BreederFlockMilestoneType.fivePercentProduction,
        eventDate: entryDate.add(const Duration(days: 175)),
      );
      final corrected = await service.recordMilestone(
        flockId: flock.id,
        eventType: BreederFlockMilestoneType.fivePercentProduction,
        eventDate: entryDate.add(const Duration(days: 182)),
      );

      expect(corrected.id, first.id);
      final milestones = await service.milestonesForFlock(flock.id);
      expect(milestones, hasLength(1));
      expect(milestones.single.eventDate, entryDate.add(const Duration(days: 182)));
    });
  });
}
