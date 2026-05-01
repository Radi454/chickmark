import 'date_utils.dart';

class BmkAgeCalculator {
  const BmkAgeCalculator._();

  static int? currentFlockAgeDaysFromWeeks(int? flockAgeWeeks) {
    if (flockAgeWeeks == null) return null;
    return (flockAgeWeeks * 7).round();
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
      return _clamp(currentFlockAgeDays - 21 - (storageDays ?? 0));
    }

    if (flockEntryDate != null) {
      return _clamp(
        HatchDateUtils.flockAgeDays(flockEntryDate, now: auditDate) -
            21 -
            (storageDays ?? 0),
      );
    }

    return null;
  }

  static int? benchmarkWeekForDays(int? calculatedBmkAgeDays) {
    if (calculatedBmkAgeDays == null) return null;
    return (calculatedBmkAgeDays / 7.0).round();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  static int _clamp(int value) => value < 0 ? 0 : value;
}
