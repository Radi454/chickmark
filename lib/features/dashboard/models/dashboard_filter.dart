class DashboardFilter {
  final String? customerId;
  final String? hatcheryId;
  final String? flockId;
  final int? bmkAge;

  /// Optional single-visit narrowing (used by per-sector Cumulative/period
  /// selection). Additive — null leaves all existing queries unchanged.
  final String? sessionId;

  DashboardFilter({
    this.customerId,
    this.hatcheryId,
    this.flockId,
    this.bmkAge,
    this.sessionId,
  });

  bool get isOperational => customerId != null && hatcheryId != null;

  DashboardFilter copyWith({
    String? customerId,
    String? hatcheryId,
    String? flockId,
    int? bmkAge,
    String? sessionId,
  }) {
    return DashboardFilter(
      customerId: customerId ?? this.customerId,
      hatcheryId: hatcheryId ?? this.hatcheryId,
      flockId: flockId ?? this.flockId,
      bmkAge: bmkAge ?? this.bmkAge,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}
