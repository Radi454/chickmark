class DashboardFilter {
  final String? customerId;
  final String? flockId;
  final int? bmkAge;

  DashboardFilter({this.customerId, this.flockId, this.bmkAge});

  DashboardFilter copyWith({String? customerId, String? flockId, int? bmkAge}) {
    return DashboardFilter(
      customerId: customerId ?? this.customerId,
      flockId: flockId ?? this.flockId,
      bmkAge: bmkAge ?? this.bmkAge,
    );
  }
}
