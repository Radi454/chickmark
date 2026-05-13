import '../../../core/utils/bmk_age_calculator.dart';

class EggStorageBmkAge {
  const EggStorageBmkAge._();

  static int? calculateWeeks({
    required DateTime? flockEntryDate,
    int? flockAgeWeeks,
    required DateTime auditDate,
    required int? storageDays,
  }) {
    final currentAgeDays = BmkAgeCalculator.currentFlockAgeDays(
      flockAgeWeeks: flockAgeWeeks,
      flockEntryDate: flockEntryDate,
      auditDate: auditDate,
    );
    final bmkAgeDays = BmkAgeCalculator.calculateDaysFromFlockAge(
      currentFlockAgeDays: currentAgeDays,
      storageDays: storageDays,
    );
    return BmkAgeCalculator.displayWeekForDays(bmkAgeDays);
  }
}
