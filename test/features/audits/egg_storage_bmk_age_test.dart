import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/utils/bmk_age_calculator.dart';
import 'package:hatchaudit/features/audits/utils/egg_storage_bmk_age.dart';

void main() {
  test('subtracts incubation and storage days before converting to weeks', () {
    final result = EggStorageBmkAge.calculateWeeks(
      flockEntryDate: DateTime(2026, 1, 1),
      auditDate: DateTime(2026, 2, 26),
      storageDays: 7,
    );

    expect(result, 4);
  });

  test('returns zero when incubation and storage exceed current age', () {
    final result = EggStorageBmkAge.calculateWeeks(
      flockEntryDate: DateTime(2026, 1, 1),
      auditDate: DateTime(2026, 1, 15),
      storageDays: 3,
    );

    expect(result, 0);
  });

  test('uses saved flock age weeks when entry date is unavailable', () {
    final result = EggStorageBmkAge.calculateWeeks(
      flockEntryDate: null,
      flockAgeWeeks: 42,
      auditDate: DateTime(2026, 4, 27),
      storageDays: null,
    );

    expect(result, 39);
  });

  test('uses centralized display week conversion for partial BMK weeks', () {
    final result = EggStorageBmkAge.calculateWeeks(
      flockEntryDate: null,
      flockAgeWeeks: 43,
      auditDate: DateTime(2026, 4, 27),
      storageDays: 0,
    );

    expect(result, BmkAgeCalculator.displayWeekForDays(280));
  });

  test('returns null without flock age data', () {
    final result = EggStorageBmkAge.calculateWeeks(
      flockEntryDate: null,
      auditDate: DateTime(2026, 2, 26),
      storageDays: 7,
    );

    expect(result, isNull);
  });
}
