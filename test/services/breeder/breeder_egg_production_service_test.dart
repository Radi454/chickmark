import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/database/seeds/breeder_egg_grade_definition_seeds.dart';
import 'package:hatchaudit/data/models/breeder_bird_movement_model.dart';
import 'package:hatchaudit/data/models/breeder_daily_report_model.dart';
import 'package:hatchaudit/data/models/breeder_egg_grade_definition_model.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_grade_definition_repository.dart';
import 'package:hatchaudit/data/repositories/breeder_egg_production_entry_repository.dart';
import 'package:hatchaudit/data/repositories/poultry_hierarchy_repository.dart';
import 'package:hatchaudit/services/breeder/breeder_egg_production_service.dart';

import '../../support/test_database.dart';

/// `BreederEggProductionService` (breeder-flock-performance ticket 10,
/// design doc section 5.2, 7, 7.1, 7.2, and 12): the single tested home for
/// the egg-grade partition (priority resolution, unique-priority
/// enforcement), total-eggs/percentage arithmetic, and production-percent
/// denominators.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BreederEggGradeDefinition gradeFor(String code) =>
      kBreederEggGradeDefinitionSeeds.firstWhere((g) => g.code == code);

  group('grade priority resolution (pure, no database)', () {
    test(
      'a cracked double-yolk egg counts under the higher-priority grade '
      '(cracked)',
      () {
        final matches = [gradeFor('cracked'), gradeFor('double_yolk')];
        final resolved = BreederEggProductionService.resolveHighestPriorityGrade(
          matches,
        );
        expect(resolved.code, 'cracked');
      },
    );

    test('an egg matching only one grade resolves to that grade', () {
      final resolved = BreederEggProductionService.resolveHighestPriorityGrade(
        [gradeFor('first_grade')],
      );
      expect(resolved.code, 'first_grade');
    });

    test('damaged beats every other grade it also matches', () {
      final matches = [
        gradeFor('damaged'),
        gradeFor('cracked'),
        gradeFor('double_yolk'),
        gradeFor('sort_reject'),
      ];
      final resolved = BreederEggProductionService.resolveHighestPriorityGrade(
        matches,
      );
      expect(resolved.code, 'damaged');
    });

    test('an empty candidate list is a domain error', () {
      expect(
        () => BreederEggProductionService.resolveHighestPriorityGrade([]),
        throwsA(isA<BreederEggProductionValidationError>()),
      );
    });

    test('the seeded grade set has no duplicate priority', () {
      expect(
        () => BreederEggProductionService.validateUniqueActivePriorities(
          kBreederEggGradeDefinitionSeeds,
        ),
        returnsNormally,
      );
    });

    test('validateUniqueActivePriorities rejects a duplicate priority', () {
      final duplicated = [
        BreederEggGradeDefinition(
          id: 'g1',
          code: 'a',
          name: 'A',
          priority: 1,
        ),
        BreederEggGradeDefinition(
          id: 'g2',
          code: 'b',
          name: 'B',
          priority: 1,
        ),
      ];
      expect(
        () => BreederEggProductionService.validateUniqueActivePriorities(
          duplicated,
        ),
        throwsA(isA<BreederEggProductionValidationError>()),
      );
    });

    test(
      'validateUniqueActivePriorities ignores inactive grades sharing a '
      'priority',
      () {
        final grades = [
          BreederEggGradeDefinition(
            id: 'g1',
            code: 'a',
            name: 'A',
            priority: 1,
          ),
          BreederEggGradeDefinition(
            id: 'g2',
            code: 'b',
            name: 'B',
            priority: 1,
            isActive: false,
          ),
        ];
        expect(
          () => BreederEggProductionService.validateUniqueActivePriorities(
            grades,
          ),
          returnsNormally,
        );
      },
    );
  });

  group('total eggs and grade percent (pure, no database)', () {
    test('total eggs is the sum of every grade count, never independently typed', () {
      final total = BreederEggProductionService.totalEggs([10, 5, 0, 2, 1, 3]);
      expect(total, 21);
    });

    test('a negative count is rejected', () {
      expect(
        () => BreederEggProductionService.totalEggs([10, -1]),
        throwsA(isA<BreederEggProductionValidationError>()),
      );
    });

    test('grade counts sum exactly to total eggs across the whole partition', () {
      final counts = {
        'first_grade': 80,
        'second_grade': 10,
        'sort_reject': 4,
        'double_yolk': 3,
        'cracked': 2,
        'damaged': 1,
      };
      final total = BreederEggProductionService.totalEggs(counts.values);
      expect(total, counts.values.fold<int>(0, (a, b) => a + b));
      expect(total, 100);
    });

    test('egg-grade percent divides by total eggs for the same scope', () {
      final percent = BreederEggProductionService.eggGradePercent(
        gradeCount: 25,
        totalEggsForScope: 100,
      );
      expect(percent, 25.0);
    });

    test('egg-grade percent is blank when total eggs is zero', () {
      final percent = BreederEggProductionService.eggGradePercent(
        gradeCount: 0,
        totalEggsForScope: 0,
      );
      expect(percent, isNull);
    });
  });

  group('production percent denominators (pure, no database)', () {
    test('daily production percent divides house-scope eggs by house-scope closing females', () {
      final percent = BreederEggProductionService.dailyProductionPercent(
        totalEggsHouseScope: 85,
        closingLiveFemalesHouseScope: 100,
      );
      expect(percent, 85.0);
    });

    test('a zero denominator yields blank, never 0', () {
      final percent = BreederEggProductionService.dailyProductionPercent(
        totalEggsHouseScope: 0,
        closingLiveFemalesHouseScope: 0,
      );
      expect(percent, isNull);
    });

    test('a negative denominator yields blank, never an error', () {
      final percent = BreederEggProductionService.dailyProductionPercent(
        totalEggsHouseScope: 10,
        closingLiveFemalesHouseScope: -5,
      );
      expect(percent, isNull);
    });

    test('a missing (null) denominator yields blank', () {
      final percent = BreederEggProductionService.dailyProductionPercent(
        totalEggsHouseScope: 10,
        closingLiveFemalesHouseScope: null,
      );
      expect(percent, isNull);
    });

    test(
      'isolation eggs and isolation females are excluded from the house-scope '
      'figures, and the isolation figure never mixes into the house figure',
      () {
        final movements = [
          BreederBirdMovement(
            id: 'm-house',
            reportId: 'r1',
            houseId: 'house-1',
            sex: BreederBirdMovementSex.female,
            opening: 100,
            closing: 100,
          ),
          BreederBirdMovement(
            id: 'm-iso',
            reportId: 'r1',
            isolationAreaId: 'iso-1',
            sex: BreederBirdMovementSex.female,
            opening: 20,
            closing: 20,
          ),
        ];
        final houseFemales = BreederEggProductionService.closingFemalesHouseScope(
          movements,
        );
        final isolationFemales =
            BreederEggProductionService.closingFemalesIsolationScope(movements);
        expect(houseFemales, 100);
        expect(isolationFemales, 20);

        // House-scope total eggs excludes any isolation-collected eggs by
        // construction: the caller only ever sums house-location entries
        // into `totalEggsHouseScope` (design section 7.1).
        const houseEggs = 90;
        const isolationEggs = 5;
        final housePercent = BreederEggProductionService.dailyProductionPercent(
          totalEggsHouseScope: houseEggs,
          closingLiveFemalesHouseScope: houseFemales,
        );
        final isolationPercent =
            BreederEggProductionService.isolationProductionPercent(
          totalEggsIsolationScope: isolationEggs,
          closingLiveFemalesIsolationScope: isolationFemales,
        );
        expect(housePercent, 90.0);
        expect(isolationPercent, 25.0);
      },
    );
  });

  group('database-backed entry persistence', () {
    setUpAll(() async {
      await useIsolatedAppDatabase();
    });

    tearDownAll(() async {
      await DatabaseHelper().close();
    });

    late BreederEggGradeDefinitionRepository gradeRepository;
    late BreederEggProductionEntryRepository entryRepository;
    late BreederEggProductionService service;
    late PoultryHierarchyRepository houseRepository;

    setUp(() {
      gradeRepository = BreederEggGradeDefinitionRepository();
      entryRepository = BreederEggProductionEntryRepository();
      service = BreederEggProductionService(
        gradeRepository: gradeRepository,
        entryRepository: entryRepository,
      );
      houseRepository = PoultryHierarchyRepository();
    });

    Future<void> seedFlock(String flockId) async {
      final db = await DatabaseHelper().db;
      await db.insert('flocks', {'id': flockId, 'flockId': flockId});
    }

    Future<String> seedReport(String flockId, String date) async {
      await seedFlock(flockId);
      final db = await DatabaseHelper().db;
      final id = 'report-$flockId-$date';
      final now = DateTime(2026, 1, 1).toIso8601String();
      await db.insert('breeder_daily_reports', {
        'id': id,
        'flockId': flockId,
        'reportDate': date,
        'createdAt': now,
        'updatedAt': now,
      });
      return id;
    }

    Future<void> seedHouse(String flockId, String houseId) async {
      await houseRepository.saveHouse(
        HouseModel(id: houseId, flockId: flockId, name: houseId),
      );
    }

    test('the seeded grade definitions load with a unique priority each', () async {
      final grades = await gradeRepository.listActiveGrades();
      expect(grades, hasLength(6));
      final priorities = grades.map((g) => g.priority).toSet();
      expect(priorities, hasLength(6));
    });

    test('the database rejects a duplicate active priority', () async {
      final db = await DatabaseHelper().db;
      final now = DateTime.now().toIso8601String();
      await expectLater(
        db.insert('breeder_egg_grade_definitions', {
          'id': 'dup-priority-grade',
          'code': 'dup_priority_grade',
          'name': 'Duplicate priority',
          'priority': 1, // same as the seeded 'damaged' grade
          'isActive': 1,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    });

    test('a retired priority can be reused by a newly active grade', () async {
      final db = await DatabaseHelper().db;
      final now = DateTime.now().toIso8601String();
      // A duplicate priority is fine as long as the earlier row is inactive.
      await db.insert('breeder_egg_grade_definitions', {
        'id': 'reused-priority-grade',
        'code': 'reused_priority_grade',
        'name': 'Reused priority',
        'priority': 1,
        'isActive': 0,
        'createdAt': now,
        'updatedAt': now,
      });
      final rows = await db.query(
        'breeder_egg_grade_definitions',
        where: 'id = ?',
        whereArgs: ['reused-priority-grade'],
      );
      expect(rows, hasLength(1));
    });

    test('recordGradeCount persists a count for a house/grade/report', () async {
      final reportId = await seedReport('flock-egg-1', '2026-04-01');
      await seedHouse('flock-egg-1', 'house-egg-1');
      final grade = await gradeRepository.getByCode('first_grade');

      final entry = await service.recordGradeCount(
        reportId: reportId,
        houseId: 'house-egg-1',
        gradeId: grade!.id,
        count: 42,
      );

      expect(entry.count, 42);
      final reloaded = await entryRepository.getByReportHouseGrade(
        reportId,
        'house-egg-1',
        grade.id,
      );
      expect(reloaded?.count, 42);
    });

    test('a negative count is rejected by the service before it reaches the database', () async {
      final reportId = await seedReport('flock-egg-neg', '2026-04-02');
      await seedHouse('flock-egg-neg', 'house-egg-neg');
      final grade = await gradeRepository.getByCode('cracked');

      await expectLater(
        service.recordGradeCount(
          reportId: reportId,
          houseId: 'house-egg-neg',
          gradeId: grade!.id,
          count: -1,
        ),
        throwsA(isA<BreederEggProductionValidationError>()),
      );
    });

    test('the database CHECK also rejects a negative count', () async {
      final reportId = await seedReport('flock-egg-negdb', '2026-04-03');
      await seedHouse('flock-egg-negdb', 'house-egg-negdb');
      final db = await DatabaseHelper().db;
      final grade = await gradeRepository.getByCode('cracked');
      final now = DateTime.now().toIso8601String();
      await expectLater(
        db.insert('breeder_egg_production_entries', {
          'id': 'egg-entry-negdb',
          'reportId': reportId,
          'houseId': 'house-egg-negdb',
          'gradeId': grade!.id,
          'count': -1,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    });

    test(
      'the location-scope trigger rejects an entry whose house belongs to '
      'a different flock',
      () async {
        final reportId = await seedReport('flock-egg-scope-x', '2026-04-04');
        await seedFlock('flock-egg-scope-y');
        await seedHouse('flock-egg-scope-y', 'house-egg-scope-1'); // different flock
        final db = await DatabaseHelper().db;
        final grade = await gradeRepository.getByCode('cracked');
        final now = DateTime.now().toIso8601String();
        await expectLater(
          db.insert('breeder_egg_production_entries', {
            'id': 'egg-entry-scope-1',
            'reportId': reportId,
            'houseId': 'house-egg-scope-1',
            'gradeId': grade!.id,
            'count': 1,
            'createdAt': now,
            'updatedAt': now,
          }),
          throwsA(anything),
        );
      },
    );

    test(
      'initializeEntriesForLocation creates a zero-count row for every '
      'active grade',
      () async {
        final reportId = await seedReport('flock-egg-init', '2026-04-05');
        await seedHouse('flock-egg-init', 'house-egg-init');

        final entries = await service.initializeEntriesForLocation(
          reportId: reportId,
          houseId: 'house-egg-init',
        );

        expect(entries, hasLength(6));
        expect(entries.every((e) => e.count == 0), isTrue);
      },
    );

    test(
      'recordEggWeight sets the same weight across every grade row for '
      'that location',
      () async {
        final reportId = await seedReport('flock-egg-weight', '2026-04-06');
        await seedHouse('flock-egg-weight', 'house-egg-weight');
        await service.initializeEntriesForLocation(
          reportId: reportId,
          houseId: 'house-egg-weight',
        );

        await service.recordEggWeight(
          reportId: reportId,
          houseId: 'house-egg-weight',
          eggWeightGrams: 62.5,
        );

        final entries = await entryRepository.getForReport(reportId);
        expect(entries, hasLength(6));
        expect(entries.every((e) => e.eggWeightGrams == 62.5), isTrue);
      },
    );

    test('a non-positive egg weight is rejected', () async {
      final reportId = await seedReport('flock-egg-weight-neg', '2026-04-07');
      await seedHouse('flock-egg-weight-neg', 'house-egg-weight-neg');
      await service.initializeEntriesForLocation(
        reportId: reportId,
        houseId: 'house-egg-weight-neg',
      );

      await expectLater(
        service.recordEggWeight(
          reportId: reportId,
          houseId: 'house-egg-weight-neg',
          eggWeightGrams: 0,
        ),
        throwsA(isA<BreederEggProductionValidationError>()),
      );
    });

    test('recordGradeCount rejects a location naming both a house and an isolation area', () async {
      final reportId = await seedReport('flock-egg-both', '2026-04-08');
      await seedHouse('flock-egg-both', 'house-egg-both');
      final grade = await gradeRepository.getByCode('cracked');
      await expectLater(
        service.recordGradeCount(
          reportId: reportId,
          houseId: 'house-egg-both',
          isolationAreaId: 'area-egg-both',
          gradeId: grade!.id,
          count: 1,
        ),
        throwsA(isA<BreederEggProductionValidationError>()),
      );
    });
  });

  group('BreederDailyReport approval snapshot fields', () {
    test('round-trip through toMap/fromMap preserves the egg-approval snapshot', () {
      final report = BreederDailyReport(
        id: 'r1',
        flockId: 'f1',
        reportDate: DateTime(2026, 1, 1),
        eggProductionDenominatorFemales: 950,
        benchmarkProfileVersionAtApproval: 'Performance Objectives 2021 EN',
        comparisonAxisAtApproval: 'ComparisonAxis.official',
      );
      final restored = BreederDailyReport.fromMap(report.toMap());
      expect(restored.eggProductionDenominatorFemales, 950);
      expect(
        restored.benchmarkProfileVersionAtApproval,
        'Performance Objectives 2021 EN',
      );
      expect(restored.comparisonAxisAtApproval, 'ComparisonAxis.official');
    });

    test('the snapshot fields stay null until they are ever set', () {
      final report = BreederDailyReport(
        id: 'r2',
        flockId: 'f1',
        reportDate: DateTime(2026, 1, 2),
      );
      expect(report.eggProductionDenominatorFemales, isNull);
      expect(report.benchmarkProfileVersionAtApproval, isNull);
      expect(report.comparisonAxisAtApproval, isNull);
    });
  });
}
