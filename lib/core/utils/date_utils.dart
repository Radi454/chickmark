class HatchDateUtils {
  static int flockAgeDays(DateTime entryDate, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    final entryDateOnly = DateTime.utc(
      entryDate.year,
      entryDate.month,
      entryDate.day,
    );
    return todayDate.difference(entryDateOnly).inDays;
  }

  static int flockAgeWeeks(DateTime entryDate, {DateTime? now}) {
    return (flockAgeDays(entryDate, now: now) / 7).floor();
  }

  static double bmkAgeWeeks(
    DateTime entryDate,
    int storageDays, {
    DateTime? now,
  }) {
    final days = flockAgeDays(entryDate, now: now) - 21 - storageDays;
    return days > 0 ? days / 7 : 0.0;
  }
}
