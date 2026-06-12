import '../scope/scope_config.dart';
import '../scope/scope_models.dart';

/// One point on a sector's Cumulative axis — a flock age (age axis) or an audit
/// visit (visit axis). [n] is the leaf/sample count shown on the axis chip.
class ScopePeriod {
  final String label; // 'W36' (age) or '12 Mar' (visit)
  final int? age; // age axis: flock age weeks; null for visit axis
  final String? sessionId; // visit axis: session id; null for age axis
  final int n;

  const ScopePeriod({
    required this.label,
    this.age,
    this.sessionId,
    this.n = 0,
  });

  /// Same period (used to keep a selection highlighted across rebuilds).
  bool sameAs(ScopePeriod? o) =>
      o != null && o.age == age && o.sessionId == sessionId;
}

/// One parameter's pooled value across the cumulative axis, aligned index-for-
/// index to [CumulativeSeries.periods]. Values come from the SAME pooled
/// aggregation the Incremental view uses (ScopeEngine), so they never diverge.
class CumulativeParam {
  final ScopeParam param;
  final List<num?> values; // pooled actual per period
  final List<num?> bmks; // benchmark per period (null where none)
  final List<String> texts; // formatted display text per period
  final List<ScopeSeverity> severities;

  const CumulativeParam({
    required this.param,
    required this.values,
    required this.bmks,
    required this.texts,
    required this.severities,
  });

  bool get hasBmk => bmks.any((b) => b != null);

  /// Trend direction first→last: +1 up, -1 down, 0 flat/insufficient.
  int get trend {
    final nums = values.whereType<num>().toList();
    if (nums.length < 2) return 0;
    final diff = values.lastWhere((v) => v != null, orElse: () => null)! -
        values.firstWhere((v) => v != null, orElse: () => null)!;
    if (diff.abs() < (nums.first.abs() * 0.01)) return 0;
    return diff > 0 ? 1 : -1;
  }
}

/// A sector's full cumulative dataset: the axis points + one series per param.
class CumulativeSeries {
  final List<ScopePeriod> periods;
  final List<CumulativeParam> params;

  const CumulativeSeries({required this.periods, required this.params});

  bool get isEmpty => periods.isEmpty || params.isEmpty;
}
