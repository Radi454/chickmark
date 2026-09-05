/// The daily report header for a breeder flock (breeder-flock-performance
/// ticket 07, design doc section 5). One row per flock and calendar date,
/// covering all of that flock's houses. Age, production week, and breed are
/// deliberately absent from this model: they are always derived for display
/// via `BreederFlockLifecycleService` and `flocks.breed`, never stored or
/// independently editable here.
library;

/// The report's place in the Draft -> Submitted -> Approved state machine
/// (design doc section 5.3), extended by breeder-flock-performance ticket
/// 15 with `Sync Conflict`, reachable from any of the other three states
/// when the report's sync-aggregate push (design section 13.1) is rejected
/// by a stale revision. `Revised` is never a stored state value — a
/// post-approval correction (ticket 12) appends `breeder_report_revisions`
/// rows and bumps `revision` without changing `state`, so a corrected
/// report is simply `approved` with revision history attached.
class BreederDailyReportState {
  static const String draft = 'draft';
  static const String submitted = 'submitted';
  static const String approved = 'approved';
  static const String syncConflict = 'sync_conflict';

  static const List<String> all = [draft, submitted, approved, syncConflict];

  /// States [syncConflict] can be entered from and restored back to.
  static const List<String> resolvable = [draft, submitted, approved];

  static bool isValid(String value) => all.contains(value);
}

class BreederDailyReport {
  final String id;
  final String flockId;

  /// Calendar date only (time-of-day is discarded). Compared and stored via
  /// [dateKey].
  final DateTime reportDate;
  final double? insideTemperature;
  final double? outsideTemperature;

  /// Hours of light provided on this day (breeder-flock-performance ticket
  /// 09, design doc section 5.1/5.2). Stored as a plain hour count, not a
  /// time-of-day; unlike the temperature fields it carries no per-sector
  /// unit convention since "hours" has no alternate unit to label.
  final double? lightHours;
  final String? notes;
  final String state;

  /// The state held immediately before entering [BreederDailyReportState.
  /// syncConflict] (ticket 15) — null unless [state] is currently
  /// [BreederDailyReportState.syncConflict]. Resolving the conflict restores
  /// [state] to this value and clears it back to null.
  final String? previousState;

  /// Optimistic-concurrency counter for ticket 15. This ticket only sets it
  /// to 1 on create and increments it on each state transition.
  final int revision;

  /// The cloud's `sync_token` this device last confirmed — despite the
  /// name, this is NOT [revision]. It is a separate, opaque optimistic
  /// -concurrency counter the cloud push RPC advances on every successful
  /// aggregate push (transition or not), kept apart from [revision]
  /// precisely so two devices sitting at the same [revision] cannot both
  /// present a "matching" base and silently overwrite one another's child
  /// rows. Local-only sync bookkeeping (ticket 15), sent as the aggregate
  /// push's `base_revision` argument and never present in a cloud payload.
  /// `0` means this report has never been successfully pushed.
  final int lastSyncedRevision;

  final String? createdBy;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;

  /// Approval-time snapshot of the egg-production denominator (closing live
  /// females in production houses, summed across the report's house
  /// movements — design doc section 7.1) plus which benchmark profile
  /// version and comparison axis were in effect (ticket 06's
  /// `ComparisonAxis`, ticket 03's benchmark `guideVersion`). Written once
  /// by `BreederBirdLedgerService.approve`; null for a report that has
  /// never been approved, or that approved before the flock entered egg
  /// production (breeder-flock-performance ticket 10, design doc section
  /// 7.1: "The denominator actually used is retained in the approved
  /// report snapshot for auditability, together with the benchmark profile
  /// version and comparison axis").
  final int? eggProductionDenominatorFemales;
  final String? benchmarkProfileVersionAtApproval;
  final String? comparisonAxisAtApproval;

  const BreederDailyReport({
    required this.id,
    required this.flockId,
    required this.reportDate,
    this.insideTemperature,
    this.outsideTemperature,
    this.lightHours,
    this.notes,
    this.state = BreederDailyReportState.draft,
    this.previousState,
    this.revision = 1,
    this.lastSyncedRevision = 0,
    this.createdBy,
    this.submittedBy,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.eggProductionDenominatorFemales,
    this.benchmarkProfileVersionAtApproval,
    this.comparisonAxisAtApproval,
  });

  bool get isDraft => state == BreederDailyReportState.draft;
  bool get isSubmitted => state == BreederDailyReportState.submitted;
  bool get isApproved => state == BreederDailyReportState.approved;
  bool get isSyncConflict => state == BreederDailyReportState.syncConflict;

  /// Canonical calendar-date key (`YYYY-MM-DD`) used for both storage and
  /// the `(flockId, reportDate)` uniqueness rule. Never carries a time
  /// component, so two reports filed at different times on the same day
  /// always collide as intended.
  static String dateKey(DateTime date) {
    final utc = DateTime.utc(date.year, date.month, date.day);
    return utc.toIso8601String().substring(0, 10);
  }

  String get reportDateKey => dateKey(reportDate);

  factory BreederDailyReport.fromMap(Map<String, dynamic> map) {
    return BreederDailyReport(
      id: map['id'] as String,
      flockId: map['flockId'] as String,
      reportDate: DateTime.parse(map['reportDate'] as String),
      insideTemperature: (map['insideTemperature'] as num?)?.toDouble(),
      outsideTemperature: (map['outsideTemperature'] as num?)?.toDouble(),
      lightHours: (map['lightHours'] as num?)?.toDouble(),
      notes: map['notes']?.toString(),
      state: (map['state'] as String?) ?? BreederDailyReportState.draft,
      previousState: map['previousState']?.toString(),
      revision: (map['revision'] as num?)?.toInt() ?? 1,
      lastSyncedRevision: (map['lastSyncedRevision'] as num?)?.toInt() ?? 0,
      createdBy: map['createdBy']?.toString(),
      submittedBy: map['submittedBy']?.toString(),
      submittedAt: map['submittedAt'] != null
          ? DateTime.parse(map['submittedAt'] as String)
          : null,
      approvedBy: map['approvedBy']?.toString(),
      approvedAt: map['approvedAt'] != null
          ? DateTime.parse(map['approvedAt'] as String)
          : null,
      eggProductionDenominatorFemales:
          (map['eggProductionDenominatorFemales'] as num?)?.toInt(),
      benchmarkProfileVersionAtApproval:
          map['benchmarkProfileVersionAtApproval']?.toString(),
      comparisonAxisAtApproval: map['comparisonAxisAtApproval']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'flockId': flockId,
      'reportDate': reportDateKey,
      'insideTemperature': insideTemperature,
      'outsideTemperature': outsideTemperature,
      'lightHours': lightHours,
      'notes': notes,
      'state': state,
      'previousState': previousState,
      'revision': revision,
      'lastSyncedRevision': lastSyncedRevision,
      'createdBy': createdBy,
      'submittedBy': submittedBy,
      'submittedAt': submittedAt?.toIso8601String(),
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.toIso8601String(),
      'eggProductionDenominatorFemales': eggProductionDenominatorFemales,
      'benchmarkProfileVersionAtApproval': benchmarkProfileVersionAtApproval,
      'comparisonAxisAtApproval': comparisonAxisAtApproval,
    };
  }

  BreederDailyReport copyWith({
    String? id,
    String? flockId,
    DateTime? reportDate,
    double? insideTemperature,
    bool clearInsideTemperature = false,
    double? outsideTemperature,
    bool clearOutsideTemperature = false,
    double? lightHours,
    bool clearLightHours = false,
    String? notes,
    bool clearNotes = false,
    String? state,
    String? previousState,
    bool clearPreviousState = false,
    int? revision,
    int? lastSyncedRevision,
    String? createdBy,
    String? submittedBy,
    DateTime? submittedAt,
    String? approvedBy,
    DateTime? approvedAt,
    int? eggProductionDenominatorFemales,
    String? benchmarkProfileVersionAtApproval,
    String? comparisonAxisAtApproval,
  }) {
    return BreederDailyReport(
      id: id ?? this.id,
      flockId: flockId ?? this.flockId,
      reportDate: reportDate ?? this.reportDate,
      insideTemperature: clearInsideTemperature
          ? null
          : (insideTemperature ?? this.insideTemperature),
      outsideTemperature: clearOutsideTemperature
          ? null
          : (outsideTemperature ?? this.outsideTemperature),
      lightHours: clearLightHours ? null : (lightHours ?? this.lightHours),
      notes: clearNotes ? null : (notes ?? this.notes),
      state: state ?? this.state,
      previousState: clearPreviousState
          ? null
          : (previousState ?? this.previousState),
      revision: revision ?? this.revision,
      lastSyncedRevision: lastSyncedRevision ?? this.lastSyncedRevision,
      createdBy: createdBy ?? this.createdBy,
      submittedBy: submittedBy ?? this.submittedBy,
      submittedAt: submittedAt ?? this.submittedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      eggProductionDenominatorFemales:
          eggProductionDenominatorFemales ??
          this.eggProductionDenominatorFemales,
      benchmarkProfileVersionAtApproval:
          benchmarkProfileVersionAtApproval ??
          this.benchmarkProfileVersionAtApproval,
      comparisonAxisAtApproval:
          comparisonAxisAtApproval ?? this.comparisonAxisAtApproval,
    );
  }
}
