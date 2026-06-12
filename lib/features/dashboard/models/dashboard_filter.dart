class DashboardFilter {
  final String? customerId;
  final String? flockId;
  final int? bmkAge;

  /// Optional single-visit narrowing (used by per-sector Cumulative/period
  /// selection). Additive — null leaves all existing queries unchanged.
  final String? sessionId;

  DashboardFilter({this.customerId, this.flockId, this.bmkAge, this.sessionId});

  DashboardFilter copyWith({
    String? customerId,
    String? flockId,
    int? bmkAge,
    String? sessionId,
  }) {
    return DashboardFilter(
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      bmkAge: bmkAge ?? this.bmkAge,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}
