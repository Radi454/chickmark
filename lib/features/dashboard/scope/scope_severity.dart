import '../models/egg_storage_models.dart';
import 'scope_models.dart';

/// Threshold bands for BMK-diff severity, in percentage points (or raw units).
///
/// Default `errDelta = 3.0` matches the existing breakout-severity convention in
/// `test/features/dashboard/dashboard_aggregation_test.dart` (actual ≤ bmk+3 → medium,
/// else high).
class SeverityThresholds {
  final double warnDelta;
  final double errDelta;

  const SeverityThresholds({this.warnDelta = 1.0, this.errDelta = 3.0});
}

/// Map a value to good/warn/err.
///
/// When a [bmk] reference exists (>0), severity is driven by how much *worse* than
/// the benchmark the value is (defects: value-bmk; higher-is-better metrics like
/// fertility: bmk-value). Bands: ≤ warnDelta → good, ≤ errDelta → warn, else err.
///
/// When there is no benchmark but an [absoluteLimit] is set, the value is flagged
/// `err` once it crosses the limit (used for prototype-style hard caps, e.g. navel %).
/// Otherwise → good (no false alarms for un-benchmarked params like temps/CV%).
ScopeSeverity severityFor({
  required num value,
  required num? bmk,
  required bool higherIsBetter,
  required SeverityThresholds thresholds,
  num? absoluteLimit,
}) {
  if (bmk != null && bmk > 0) {
    final diff = higherIsBetter ? (bmk - value) : (value - bmk);
    if (diff <= thresholds.warnDelta) return ScopeSeverity.good;
    if (diff <= thresholds.errDelta) return ScopeSeverity.warn;
    return ScopeSeverity.err;
  }
  if (absoluteLimit != null) {
    final exceeded =
        higherIsBetter ? value < absoluteLimit : value > absoluteLimit;
    return exceeded ? ScopeSeverity.err : ScopeSeverity.good;
  }
  return ScopeSeverity.good;
}

/// Resolve a [ScopeParam.bmkField] key to the matching [BmkReference] value.
/// Returns null when there is no benchmark counterpart (→ no severity flag).
num? bmkLookup(BmkReference? bmk, String? field) {
  if (bmk == null || field == null) return null;
  switch (field) {
    case 'infertilePct':
      return bmk.infertilePct;
    case 'earlyDeadPct':
      return bmk.earlyDeadPct;
    case 'early24hPct':
      return bmk.early24hPct;
    case 'early48hPct':
      return bmk.early48hPct;
    case 'midDeadPct':
      return bmk.midDeadPct;
    case 'lateDeadPct':
      return bmk.lateDeadPct;
    case 'bloodRingPct':
      return bmk.bloodRingPct;
    case 'blackEyePct':
      return bmk.blackEyePct;
    case 'externalPipPct':
      return bmk.externalPipPct;
    case 'crackedPct':
      return bmk.crackedPct;
    case 'contamPct':
      return bmk.contamPct;
    case 'cullPct':
      return bmk.cullPct;
    case 'fertilityPct':
      return bmk.fertilityPct;
    case 'hatchabilityPct':
      return bmk.hatchabilityPct;
    case 'hofPct':
      return bmk.hofPct;
    case 'eggWeightG':
      return bmk.eggWeightG;
    case 'chickWeightG':
      return bmk.chickWeightG;
    default:
      return null;
  }
}
