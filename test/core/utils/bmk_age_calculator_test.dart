import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/bmk_age_calculator.dart';

void main() {
  group('BmkAgeCalculator', () {
    test('derives current flock age days from stored flock age weeks', () {
      expect(BmkAgeCalculator.currentFlockAgeDaysFromWeeks(42), 294);
      expect(BmkAgeCalculator.currentFlockAgeDaysFromWeeks(null), isNull);
    });

    test('calculates per-sample BMK age from egg production date', () {
      final auditDate = DateTime(2026, 4, 27);

      final first = BmkAgeCalculator.calculateDays(
        currentFlockAgeDays: 294,
        auditDate: auditDate,
        eggProductionDate: DateTime(2026, 4, 6),
      );
      final second = BmkAgeCalculator.calculateDays(
        currentFlockAgeDays: 294,
        auditDate: auditDate,
        eggProductionDate: DateTime(2026, 4, 13),
      );

      expect(first, 273);
      expect(second, 280);
      expect(first, isNot(second));
    });

    test(
      'falls back to legacy BMK weeks when egg production date is missing',
      () {
        final bmkDays = BmkAgeCalculator.calculateDays(
          currentFlockAgeDays: 294,
          auditDate: DateTime(2026, 4, 27),
          legacyBmkAgeWeeks: 40,
        );

        expect(bmkDays, 280);
      },
    );

    test(
      'falls back to old storage-day formula when egg production date is missing',
      () {
        final bmkDays = BmkAgeCalculator.calculateDays(
          currentFlockAgeDays: 294,
          auditDate: DateTime(2026, 4, 27),
          storageDays: 5,
        );

        expect(bmkDays, 268);
      },
    );

    test(
      'falls back to flock entry date and clamps negative values to zero',
      () {
        final bmkDays = BmkAgeCalculator.calculateDays(
          auditDate: DateTime(2026, 4, 27),
          flockEntryDate: DateTime(2026, 4, 20),
          storageDays: 3,
        );

        expect(bmkDays, 0);
      },
    );

    test('converts stored BMK days to nearest benchmark week', () {
      expect(BmkAgeCalculator.benchmarkWeekForDays(283), 40);
      expect(BmkAgeCalculator.benchmarkWeekForDays(284), 41);
    });

    test('converts stored BMK days to display and legacy storage weeks', () {
      expect(BmkAgeCalculator.displayWeekForDays(280), 40);
      expect(BmkAgeCalculator.displayWeekForDays(281), 41);
      expect(BmkAgeCalculator.displayWeekForDays(0), 0);
      expect(BmkAgeCalculator.displayWeekForDays(null), isNull);
    });

    test('derives current flock days from weeks or entry date', () {
      expect(
        BmkAgeCalculator.currentFlockAgeDays(
          flockAgeWeeks: 42,
          flockEntryDate: DateTime(2026, 1, 1),
          auditDate: DateTime(2026, 4, 27),
        ),
        294,
      );
      expect(
        BmkAgeCalculator.currentFlockAgeDays(
          flockEntryDate: DateTime(2026, 4, 20),
          auditDate: DateTime(2026, 4, 27),
        ),
        7,
      );
      expect(
        BmkAgeCalculator.currentFlockAgeDays(
          flockAgeWeeks: 0,
          flockEntryDate: DateTime(2025, 8, 1),
          auditDate: DateTime(2026, 5, 8),
        ),
        280,
      );
    });
  });
}
