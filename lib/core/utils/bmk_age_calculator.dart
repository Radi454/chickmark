import 'date_utils.dart';

class BmkAgeCalculator {
  const BmkAgeCalculator._();

  static int? currentFlockAgeDaysFromWeeks(int? flockAgeWeeks) {
    if (flockAgeWeeks == null) return null;
    return _clamp((flockAgeWeeks * 7).round());
  }

  static int? currentFlockAgeDays({
    int? flockAgeWeeks,
    DateTime? flockEntryDate,
    required DateTime auditDate,
  }) {
    final fromWeeks = currentFlockAgeDaysFromWeeks(flockAgeWeeks);
    if (fromWeeks != null && fromWeeks > 0) return fromWeeks;
    if (flockEntryDate != null) {
      return _clamp(
        HatchDateUtils.flockAgeDays(flockEntryDate, now: auditDate),
      );
    }
    return fromWeeks;
  }

  static int? calculateDaysFromFlockAge({
    required int? currentFlockAgeDays,
    int? storageDays,
    int incubationOffsetDays = 21,
  }) {
    if (currentFlockAgeDays == null) return null;
    if (storageDays != null && storageDays < 0) return null;
    if (incubationOffsetDays < 0) return null;
    return _clamp(
      currentFlockAgeDays - (storageDays ?? 0) - incubationOffsetDays,
    );
  }

  static int? calculateDays({
    int? currentFlockAgeDays,
    required DateTime auditDate,
    DateTime? eggProductionDate,
    int? legacyBmkAgeWeeks,
    int? storageDays,
    DateTime? flockEntryDate,
  }) {
    if (currentFlockAgeDays != null && eggProductionDate != null) {
      return _clamp(
        currentFlockAgeDays -
            _dateOnly(
              auditDate,
            ).difference(_dateOnly(eggProductionDate)).inDays,
      );
    }

    if (legacyBmkAgeWeeks != null) {
      return _clamp(legacyBmkAgeWeeks * 7);
    }

    if (currentFlockAgeDays != null) {
      return calculateDaysFromFlockAge(
        currentFlockAgeDays: currentFlockAgeDays,
        storageDays: storageDays,
      );
    }

    if (flockEntryDate != null) {
      return calculateDaysFromFlockAge(
        currentFlockAgeDays: BmkAgeCalculator.currentFlockAgeDays(
          flockEntryDate: flockEntryDate,
          auditDate: auditDate,
        ),
        storageDays: storageDays,
      );
    }

    return null;
  }

  static int? benchmarkWeekForDays(int? calculatedBmkAgeDays) {
    if (calculatedBmkAgeDays == null) return null;
    return (calculatedBmkAgeDays / 7.0).round();
  }

  static int? displayWeekForDays(int? calculatedBmkAgeDays) {
    if (calculatedBmkAgeDays == null) return null;
    if (calculatedBmkAgeDays <= 0) return 0;
    return (calculatedBmkAgeDays / 7.0).ceil();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  static int _clamp(int value) => value < 0 ? 0 : value;
}
