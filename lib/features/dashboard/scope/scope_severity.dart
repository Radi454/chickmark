import '../models/egg_storage_models.dart';
import 'scope_models.dart';

/// Threshold bands for BMK-diff severity, in percentage points (or raw units).
///
/// Default `errDelta = 3.0` matches the existing breakout-severity convention in
/// `test/features/dashboard/dashboard_aggregation_test.dart` (actual ≤ bmk+3 → medium,
/// else high).
///
/// [nearMargin] is the band (in the value's own units) used by [absoluteLimit]
/// grading: a reading on the *good* side of the limit is good, one that breaches
/// it by up to `nearMargin` is "slightly off" (warn), and beyond that is err.
class SeverityThresholds {
  final double warnDelta;
  final double errDelta;
  final double nearMargin;

  const SeverityThresholds({
    this.warnDelta = 1.0,
    this.errDelta = 3.0,
    this.nearMargin = 1.0,
  });
}

/// Map a value to good/warn/err.
///
/// When a [bmk] reference exists (>0), severity is driven by how much *worse* than
/// the benchmark the value is (defects: value-bmk; higher-is-better metrics like
/// fertility: bmk-value). Bands: ≤ warnDelta → good, ≤ errDelta → warn, else err.
///
/// When there is no benchmark but an [absoluteLimit] is set, the value is graded
/// in three bands around that hard cap (e.g. navel %, CV%, CO₂): on the good side
/// of the cap → good (a reading under a ceiling never alarms), breaching it by up
/// to [SeverityThresholds.nearMargin] → warn (slightly off), beyond that → err
/// (big gap). Otherwise → good (no false alarms for un-capped params).
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
    return higherIsBetter
        ? floorSeverity(value, absoluteLimit, thresholds.nearMargin)
        : ceilingSeverity(value, absoluteLimit, thresholds.nearMargin);
  }
  return ScopeSeverity.good;
}

/// Grade a *lower-is-better* reading against a hard ceiling [limit]: on the good
/// side (≤ limit) → good (a reading under a ceiling never alarms), breaching it
/// by up to [margin] → warn (slightly off), beyond that → err (big gap).
///
/// Shared by the scope engine ([severityFor]), egg-storage triage, and govee
/// triage so the three-band ceiling semantic lives in exactly one place.
ScopeSeverity ceilingSeverity(num value, num limit, num margin) {
  if (value <= limit) return ScopeSeverity.good;
  if (value <= limit + margin) return ScopeSeverity.warn;
  return ScopeSeverity.err;
}

/// Grade a *higher-is-better* reading against a floor [limit]: at/above it →
/// good, within [margin] below → warn, further below → err. Mirror of
/// [ceilingSeverity].
ScopeSeverity floorSeverity(num value, num limit, num margin) {
  if (value >= limit) return ScopeSeverity.good;
  if (value >= limit - margin) return ScopeSeverity.warn;
  return ScopeSeverity.err;
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
