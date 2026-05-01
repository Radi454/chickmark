import '../../../core/utils/date_utils.dart' as hatch_dates;

class EggStorageBmkAge {
  const EggStorageBmkAge._();

  static int? calculateWeeks({
    required DateTime? flockEntryDate,
    int? flockAgeWeeks,
    required DateTime auditDate,
    required int? storageDays,
  }) {
    final currentAgeDays = flockAgeWeeks == null ? null : flockAgeWeeks * 7;
    if (currentAgeDays == null && flockEntryDate == null) return null;

    final bmkAgeDays =
        (currentAgeDays ??
            hatch_dates.HatchDateUtils.flockAgeDays(
              flockEntryDate!,
              now: auditDate,
            )) -
        21 -
        (storageDays ?? 0);
    if (bmkAgeDays <= 0) return 0;
    return (bmkAgeDays / 7).ceil();
  }
}
