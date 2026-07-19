enum DashboardActionPriority { watch, critical }

enum DashboardActionStatus { open, inProgress, resolved, reopened }

const Object _unsetDashboardActionValue = Object();

class DashboardActionModel {
  const DashboardActionModel({
    required this.id,
    required this.findingKey,
    required this.customerId,
    required this.hatcheryId,
    this.flockId,
    this.sessionId,
    this.panelName,
    this.panelRowId,
    this.fieldKey,
    this.metricKey,
    required this.title,
    this.description,
    this.priority = DashboardActionPriority.watch,
    this.status = DashboardActionStatus.open,
    this.ownerId,
    this.ownerName,
    this.dueAt,
    this.firstObservedAt,
    this.lastObservedAt,
    this.resolvedAt,
    this.resolutionNotes,
    this.resolutionPhotoId,
    this.recurrenceOfId,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  final String id;
  final String findingKey;
  final String customerId;
  final String hatcheryId;
  final String? flockId;
  final String? sessionId;
  final String? panelName;
  final String? panelRowId;
  final String? fieldKey;
  final String? metricKey;
  final String title;
  final String? description;
  final DashboardActionPriority priority;
  final DashboardActionStatus status;
  final String? ownerId;
  final String? ownerName;
  final DateTime? dueAt;
  final DateTime? firstObservedAt;
  final DateTime? lastObservedAt;
  final DateTime? resolvedAt;
  final String? resolutionNotes;
  final String? resolutionPhotoId;
  final String? recurrenceOfId;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  bool get isResolved => status == DashboardActionStatus.resolved;

  factory DashboardActionModel.fromMap(Map<String, dynamic> map) {
    Object? value(String camel, [String? snake]) =>
        map[camel] ?? (snake == null ? null : map[snake]);
    return DashboardActionModel(
      id: value('id').toString(),
      findingKey: value('findingKey', 'finding_key').toString(),
      customerId: value('customerId', 'customer_id').toString(),
      hatcheryId: value('hatcheryId', 'hatchery_id').toString(),
      flockId: _string(value('flockId', 'flock_id')),
      sessionId: _string(value('sessionId', 'session_id')),
      panelName: _string(value('panelName', 'panel_name')),
      panelRowId: _string(value('panelRowId', 'panel_row_id')),
      fieldKey: _string(value('fieldKey', 'field_key')),
      metricKey: _string(value('metricKey', 'metric_key')),
      title: value('title').toString(),
      description: _string(value('description')),
      priority: _priority(value('priority')),
      status: _status(value('status')),
      ownerId: _string(value('ownerId', 'owner_id')),
      ownerName: _string(value('ownerName', 'owner_name')),
      dueAt: _date(value('dueAt', 'due_at')),
      firstObservedAt: _date(value('firstObservedAt', 'first_observed_at')),
      lastObservedAt: _date(value('lastObservedAt', 'last_observed_at')),
      resolvedAt: _date(value('resolvedAt', 'resolved_at')),
      resolutionNotes: _string(value('resolutionNotes', 'resolution_notes')),
      resolutionPhotoId: _string(
        value('resolutionPhotoId', 'resolution_photo_id'),
      ),
      recurrenceOfId: _string(value('recurrenceOfId', 'recurrence_of_id')),
      createdBy: _string(value('createdBy', 'created_by')),
      createdAt: _date(value('createdAt', 'created_at')) ?? DateTime.now(),
      updatedAt: _date(value('updatedAt', 'updated_at')) ?? DateTime.now(),
      syncStatus: _string(value('syncStatus', 'sync_status')) ?? 'synced',
      dirtyAt: _date(value('dirtyAt', 'dirty_at')),
      lastSyncedAt: _date(value('lastSyncedAt', 'last_synced_at')),
      syncError: _string(value('syncError', 'sync_error')),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'findingKey': findingKey,
    'customerId': customerId,
    'hatcheryId': hatcheryId,
    'flockId': flockId,
    'sessionId': sessionId,
    'panelName': panelName,
    'panelRowId': panelRowId,
    'fieldKey': fieldKey,
    'metricKey': metricKey,
    'title': title,
    'description': description,
    'priority': priority.name,
    'status': status == DashboardActionStatus.inProgress
        ? 'in_progress'
        : status.name,
    'ownerId': ownerId,
    'ownerName': ownerName,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'firstObservedAt': firstObservedAt?.toUtc().toIso8601String(),
    'lastObservedAt': lastObservedAt?.toUtc().toIso8601String(),
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
    'resolutionNotes': resolutionNotes,
    'resolutionPhotoId': resolutionPhotoId,
    'recurrenceOfId': recurrenceOfId,
    'createdBy': createdBy,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'syncStatus': syncStatus,
    'dirtyAt': dirtyAt?.toUtc().toIso8601String(),
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'syncError': syncError,
  };

  DashboardActionModel copyWith({
    DashboardActionPriority? priority,
    DashboardActionStatus? status,
    Object? ownerId = _unsetDashboardActionValue,
    Object? ownerName = _unsetDashboardActionValue,
    Object? dueAt = _unsetDashboardActionValue,
    DateTime? lastObservedAt,
    Object? resolvedAt = _unsetDashboardActionValue,
    Object? resolutionNotes = _unsetDashboardActionValue,
    Object? resolutionPhotoId = _unsetDashboardActionValue,
    DateTime? updatedAt,
    String? syncStatus,
    Object? dirtyAt = _unsetDashboardActionValue,
    Object? lastSyncedAt = _unsetDashboardActionValue,
    Object? syncError = _unsetDashboardActionValue,
  }) => DashboardActionModel(
    id: id,
    findingKey: findingKey,
    customerId: customerId,
    hatcheryId: hatcheryId,
    flockId: flockId,
    sessionId: sessionId,
    panelName: panelName,
    panelRowId: panelRowId,
    fieldKey: fieldKey,
    metricKey: metricKey,
    title: title,
    description: description,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    ownerId: identical(ownerId, _unsetDashboardActionValue)
        ? this.ownerId
        : ownerId as String?,
    ownerName: identical(ownerName, _unsetDashboardActionValue)
        ? this.ownerName
        : ownerName as String?,
    dueAt: identical(dueAt, _unsetDashboardActionValue)
        ? this.dueAt
        : dueAt as DateTime?,
    firstObservedAt: firstObservedAt,
    lastObservedAt: lastObservedAt ?? this.lastObservedAt,
    resolvedAt: identical(resolvedAt, _unsetDashboardActionValue)
        ? this.resolvedAt
        : resolvedAt as DateTime?,
    resolutionNotes: identical(resolutionNotes, _unsetDashboardActionValue)
        ? this.resolutionNotes
        : resolutionNotes as String?,
    resolutionPhotoId: identical(resolutionPhotoId, _unsetDashboardActionValue)
        ? this.resolutionPhotoId
        : resolutionPhotoId as String?,
    recurrenceOfId: recurrenceOfId,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: syncStatus ?? this.syncStatus,
    dirtyAt: identical(dirtyAt, _unsetDashboardActionValue)
        ? this.dirtyAt
        : dirtyAt as DateTime?,
    lastSyncedAt: identical(lastSyncedAt, _unsetDashboardActionValue)
        ? this.lastSyncedAt
        : lastSyncedAt as DateTime?,
    syncError: identical(syncError, _unsetDashboardActionValue)
        ? this.syncError
        : syncError as String?,
  );
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

DashboardActionPriority _priority(Object? value) =>
    value?.toString() == 'critical'
    ? DashboardActionPriority.critical
    : DashboardActionPriority.watch;

DashboardActionStatus _status(Object? value) => switch (value?.toString()) {
  'in_progress' => DashboardActionStatus.inProgress,
  'resolved' => DashboardActionStatus.resolved,
  'reopened' => DashboardActionStatus.reopened,
  _ => DashboardActionStatus.open,
};
