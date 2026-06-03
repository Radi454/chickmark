class HatchDateUtils {
  static String formatDisplayDate(DateTime date) {
    return '${_twoDigits(date.day)}-${_twoDigits(date.month)}-${date.year}';
  }

  static String formatDisplayDateKey(String dateKey) {
    final parsed = DateTime.tryParse(dateKey);
    if (parsed == null) return dateKey;
    return formatDisplayDate(parsed);
  }

  static String formatDisplayDateTime(DateTime date) {
    final local = date.toLocal();
    return '${formatDisplayDate(local)} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }

  static String formatDisplayTimestamp(DateTime date) {
    final local = date.toLocal();
    return '${formatDisplayDate(local)} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:${_twoDigits(local.second)}';
  }

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

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
