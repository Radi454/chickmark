/// One changed field from a correction made to an already-APPROVED daily
/// report (breeder-flock-performance ticket 12, design doc section 5.3, 12,
/// and 13.1). See `createBreederReportRevisionsTable` in
/// database_schema.dart for the immutability guarantee this model's rows
/// are stored under, and `BreederReportRevisionService` for how a
/// correction diffs old/new field values into these rows.
library;

class BreederReportRevision {
  final String id;
  final String reportId;

  /// The table the corrected value actually lives in — `breeder_daily_reports`
  /// for a header field, or a child table name
  /// (`breeder_bird_movements`, `breeder_feed_entries`, etc.) for a
  /// corrected child row.
  final String tableName;

  /// The corrected row's own id — the report's own id when [tableName] is
  /// `breeder_daily_reports` itself.
  final String rowId;

  final String fieldName;

  /// Stored as plain text; every field this feature corrects round-trips
  /// through `toString()` cleanly. `null` means the field was previously
  /// unset.
  final String? oldValue;
  final String? newValue;

  final String reason;
  final String actorUserId;

  /// The report's own `revision` counter value after this correction was
  /// applied — every row from the same correction save shares one value.
  final int revisionAfter;

  final DateTime changedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  BreederReportRevision({
    required this.id,
    required this.reportId,
    required this.tableName,
    required this.rowId,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    required this.reason,
    required this.actorUserId,
    required this.revisionAfter,
    required this.changedAt,
    this.createdAt,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(
        reason,
        'reason',
        'is required for a report revision entry',
      );
    }
    if (actorUserId.trim().isEmpty) {
      throw ArgumentError.value(
        actorUserId,
        'actorUserId',
        'is required for a report revision entry',
      );
    }
    if (revisionAfter < 1) {
      throw ArgumentError.value(
        revisionAfter,
        'revisionAfter',
        'must be at least 1',
      );
    }
  }

  factory BreederReportRevision.fromMap(Map<String, dynamic> map) {
    return BreederReportRevision(
      id: map['id'] as String,
      reportId: map['reportId'] as String,
      tableName: map['tableName'] as String,
      rowId: map['rowId'] as String,
      fieldName: map['fieldName'] as String,
      oldValue: map['oldValue']?.toString(),
      newValue: map['newValue']?.toString(),
      reason: map['reason'] as String,
      actorUserId: map['actorUserId'] as String,
      revisionAfter: (map['revisionAfter'] as num).toInt(),
      changedAt: DateTime.parse(map['changedAt'] as String),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
      syncStatus: map['syncStatus']?.toString() ?? 'synced',
      dirtyAt: map['dirtyAt'] != null
          ? DateTime.tryParse(map['dirtyAt'].toString())
          : null,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.tryParse(map['lastSyncedAt'].toString())
          : null,
      syncError: map['syncError']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reportId': reportId,
      'tableName': tableName,
      'rowId': rowId,
      'fieldName': fieldName,
      'oldValue': oldValue,
      'newValue': newValue,
      'reason': reason,
      'actorUserId': actorUserId,
      'revisionAfter': revisionAfter,
      'changedAt': changedAt.toUtc().toIso8601String(),
    };
  }
}
