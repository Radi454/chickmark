import 'dart:convert';

/// Filter state for the session-driven Audits screen.
///
/// `statuses` / `dateFrom` / `dateTo` / `customerId` / `flockId` are applied in
/// SQL by [AuditSessionRepository.querySessions]. `syncStatuses` is applied in
/// Dart on the loaded page (a session's sync state is derived from its panel
/// rows, so it cannot be a simple SQL predicate).
class SessionFilter {
  /// Session lifecycle statuses: 'in_progress', 'completed'.
  final Set<String> statuses;

  /// Derived sync states: 'pending', 'synced', 'failed'.
  final Set<String> syncStatuses;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? customerId;
  final String? flockId;

  const SessionFilter({
    this.statuses = const {},
    this.syncStatuses = const {},
    this.dateFrom,
    this.dateTo,
    this.customerId,
    this.flockId,
  });

  static const empty = SessionFilter();

  bool get hasFilters =>
      statuses.isNotEmpty ||
      syncStatuses.isNotEmpty ||
      dateFrom != null ||
      dateTo != null ||
      customerId != null ||
      flockId != null;

  int get activeCount {
    var count = 0;
    if (statuses.isNotEmpty) count++;
    if (syncStatuses.isNotEmpty) count++;
    if (dateFrom != null || dateTo != null) count++;
    if (customerId != null) count++;
    if (flockId != null) count++;
    return count;
  }

  SessionFilter copyWith({
    Set<String>? statuses,
    Set<String>? syncStatuses,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? customerId,
    String? flockId,
    bool clearDateRange = false,
    bool clearCustomerId = false,
    bool clearFlockId = false,
  }) {
    return SessionFilter(
      statuses: statuses ?? this.statuses,
      syncStatuses: syncStatuses ?? this.syncStatuses,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      flockId: clearFlockId ? null : (flockId ?? this.flockId),
    );
  }

  Map<String, dynamic> toJson() => {
    'statuses': statuses.toList(),
    'syncStatuses': syncStatuses.toList(),
    'dateFrom': dateFrom?.toIso8601String(),
    'dateTo': dateTo?.toIso8601String(),
    'customerId': customerId,
    'flockId': flockId,
  };

  factory SessionFilter.fromJson(Map<String, dynamic> json) {
    Set<String> readSet(Object? raw) => raw is List
        ? raw.map((e) => e.toString()).toSet()
        : const <String>{};
    DateTime? readDate(Object? raw) =>
        raw == null ? null : DateTime.tryParse(raw.toString());
    return SessionFilter(
      statuses: readSet(json['statuses']),
      syncStatuses: readSet(json['syncStatuses']),
      dateFrom: readDate(json['dateFrom']),
      dateTo: readDate(json['dateTo']),
      customerId: json['customerId'] as String?,
      flockId: json['flockId'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static SessionFilter decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SessionFilter.fromJson(decoded);
      }
    } catch (_) {}
    return empty;
  }
}
