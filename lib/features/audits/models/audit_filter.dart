class AuditFilter {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String> auditTypes;
  final String? customerId;
  final String? flockId;
  final String? status;

  const AuditFilter({
    this.dateFrom,
    this.dateTo,
    this.auditTypes = const [],
    this.customerId,
    this.flockId,
    this.status,
  });

  static const empty = AuditFilter();

  bool get hasFilters =>
      dateFrom != null ||
      dateTo != null ||
      auditTypes.isNotEmpty ||
      customerId != null ||
      flockId != null ||
      status != null;

  AuditFilter copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    List<String>? auditTypes,
    String? customerId,
    String? flockId,
    String? status,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearCustomerId = false,
    bool clearFlockId = false,
    bool clearStatus = false,
  }) {
    return AuditFilter(
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      auditTypes: auditTypes ?? this.auditTypes,
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      flockId: clearFlockId ? null : (flockId ?? this.flockId),
      status: clearStatus ? null : (status ?? this.status),
    );
  }
}
