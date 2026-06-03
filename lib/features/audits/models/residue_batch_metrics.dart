import '../../../data/models/audit_model.dart';
import '../../../core/utils/calculation_utils.dart';
import 'egg_breakout_sample.dart';

class ResidueBatchMetrics {
  final double? hatchabilityPct;
  final double? fertilityPct;
  final double? hofPct;
  final double? culledPct;
  final double? deadPct;

  const ResidueBatchMetrics({
    this.hatchabilityPct,
    this.fertilityPct,
    this.hofPct,
    this.culledPct,
    this.deadPct,
  });

  factory ResidueBatchMetrics.fromAudit(AuditModel audit) {
    final hatchability = _countPercent(audit.haHatched, audit.haTotalEggsSet);
    final fertility = _trayAverageFertility(audit.ebTrayBreakoutJson);

    return ResidueBatchMetrics(
      hatchabilityPct: hatchability,
      fertilityPct: fertility,
      hofPct: hatchability != null && fertility != null && fertility > 0
          ? CalculationUtils.percentOf(
              hatchability,
              fertility,
              allowAbove100: true,
            )
          : null,
      culledPct: _countPercent(audit.haCulled, audit.haTotalEggsSet),
      deadPct: _countPercent(audit.haDead, audit.haTotalEggsSet),
    );
  }

  static double? _countPercent(int? count, int? total) {
    return CalculationUtils.percentOf(count, total);
  }

  static double? _trayAverageFertility(String? source) {
    final samples = EggBreakoutSampleEntry.decodeList(source)
        .where(
          (sample) => sample.breakoutType == EggBreakoutType.residueHatchDay,
        )
        .where((sample) => (sample.totalSample ?? 0) > 0)
        .toList();
    if (samples.isEmpty) return null;

    final percentages = samples
        .map((sample) {
          final total = sample.totalSample!;
          final infertile = sample.counts['infertile'] ?? 0;
          return CalculationUtils.percentOf(total - infertile, total);
        })
        .whereType<double>()
        .toList();
    if (percentages.isEmpty) return null;
    final sum = percentages.reduce((a, b) => a + b);
    return CalculationUtils.roundTo(sum / percentages.length);
  }
}
