import 'dart:convert';

const supportedStationKeys = [
  'egg',
  'chicks',
  'hatch_analysis_egg_breakouts',
  'setters',
  'hatchers',
];

/// Canonical map of a station key to the panel tables that store its data.
/// Single source of truth for "does this station have data" and per-station
/// sync rollups (mirrors `_panelTablesForStationKey` used inside the audit
/// workflow screens).
const kStationPanelTables = <String, List<String>>{
  'egg': ['egg_storage', 'egg_quality'],
  'chicks': ['chick_quality', 'chick_weights'],
  'hatch_analysis_egg_breakouts': [
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
  ],
  'setters': ['setter_optimizing'],
  'hatchers': ['hatcher_optimizing'],
};

const _legacyStationKeyAliases = {
  'egg_storage': 'egg',
  'chick_quality': 'chicks',
  'hatch_analysis': 'hatch_analysis_egg_breakouts',
  'setter_optimizing': 'setters',
  'hatcher_optimizing': 'hatchers',
};

String normalizeStationKey(String key) => _legacyStationKeyAliases[key] ?? key;

List<String> normalizeStationKeys(List<String>? stationKeys) {
  if (stationKeys == null || stationKeys.isEmpty) {
    return List.unmodifiable(supportedStationKeys);
  }

  final normalized = <String>[];
  for (final rawKey in stationKeys) {
    final key = normalizeStationKey(rawKey);
    if (!supportedStationKeys.contains(key) || normalized.contains(key)) {
      continue;
    }
    normalized.add(key);
  }

  if (normalized.isEmpty) {
    return List.unmodifiable(supportedStationKeys);
  }
  return List.unmodifiable(normalized);
}

List<String> parseStationKeysJson(Object? raw, {required bool defaultToAll}) {
  if (raw == null || raw == '') {
    return defaultToAll ? normalizeStationKeys(null) : const [];
  }
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is List) {
      final normalized = <String>[];
      for (final rawKey in decoded.map((e) => e.toString())) {
        final key = normalizeStationKey(rawKey);
        if (!supportedStationKeys.contains(key) || normalized.contains(key)) {
          continue;
        }
        normalized.add(key);
      }
      if (normalized.isNotEmpty) return List.unmodifiable(normalized);
    }
  } catch (_) {}
  return defaultToAll ? normalizeStationKeys(null) : const [];
}

class AuditSessionModel {
  final String id;
  final String customerId;
  final String flockId;
  final String hatcheryId;
  final DateTime date;
  final String? breed;
  final int? flockAgeWeeks;
  final String status;
  final List<String> selectedStationKeys;
  final List<String> stationsCompleted;
  final String? findingsJson;
  final String? scorecardJson;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  /// Per-row sync state: 'pending' (local edit awaiting push), 'synced'
  /// (confirmed in Supabase), or 'failed' (last push errored).
  final String syncStatus;

  /// When the row last became dirty (local edit). Null once synced.
  final DateTime? dirtyAt;
  final DateTime? lastSyncedAt;
  final String? syncError;

  const AuditSessionModel({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.hatcheryId,
    required this.date,
    this.breed,
    this.flockAgeWeeks,
    this.status = 'in_progress',
    this.selectedStationKeys = supportedStationKeys,
    this.stationsCompleted = const [],
    this.findingsJson,
    this.scorecardJson,
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.syncStatus = 'pending',
    this.dirtyAt,
    this.lastSyncedAt,
    this.syncError,
  });

  factory AuditSessionModel.fromMap(Map<String, dynamic> map) {
    final selectedStationKeys = parseStationKeysJson(
      map['selectedStationKeys'],
      defaultToAll: true,
    );
    final completed = parseStationKeysJson(
      map['stationsCompleted'],
      defaultToAll: false,
    ).where(selectedStationKeys.contains).toList();

    return AuditSessionModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      flockId: map['flockId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      breed: map['breed'] as String?,
      flockAgeWeeks: map['flockAgeWeeks'] as int?,
      status: map['status'] as String? ?? 'in_progress',
      selectedStationKeys: selectedStationKeys,
      stationsCompleted: completed,
      findingsJson: map['findingsJson'] as String?,
      scorecardJson: map['scorecardJson'] as String?,
      notes: map['notes'] as String?,
      createdBy: map['createdBy'] as String?,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      completedAt: map['completedAt'] == null
          ? null
          : DateTime.tryParse(map['completedAt'] as String),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
      dirtyAt: map['dirtyAt'] == null
          ? null
          : DateTime.tryParse(map['dirtyAt'] as String),
      lastSyncedAt: map['lastSyncedAt'] == null
          ? null
          : DateTime.tryParse(map['lastSyncedAt'] as String),
      syncError: map['syncError'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final selected = normalizeStationKeys(selectedStationKeys);
    final completed = stationsCompleted
        .where((key) => selected.contains(key))
        .toList(growable: false);
    return {
      'id': id,
      'customerId': customerId,
      'flockId': flockId,
      'hatcheryId': hatcheryId,
      'date': date.toIso8601String(),
      'breed': breed,
      'flockAgeWeeks': flockAgeWeeks,
      'status': status,
      'selectedStationKeys': jsonEncode(selected),
      'stationsCompleted': completed.isEmpty ? null : jsonEncode(completed),
      'findingsJson': findingsJson,
      'scorecardJson': scorecardJson,
      'notes': notes,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'syncStatus': syncStatus,
      'dirtyAt': dirtyAt?.toIso8601String(),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  AuditSessionModel copyWith({
    String? flockId,
    String? hatcheryId,
    DateTime? date,
    String? breed,
    int? flockAgeWeeks,
    String? status,
    List<String>? selectedStationKeys,
    List<String>? stationsCompleted,
    String? findingsJson,
    String? scorecardJson,
    String? notes,
    String? createdBy,
    DateTime? updatedAt,
    DateTime? completedAt,
    String? syncStatus,
    DateTime? dirtyAt,
    DateTime? lastSyncedAt,
    String? syncError,
  }) {
    return AuditSessionModel(
      id: id,
      customerId: customerId,
      flockId: flockId ?? this.flockId,
      hatcheryId: hatcheryId ?? this.hatcheryId,
      date: date ?? this.date,
      breed: breed ?? this.breed,
      flockAgeWeeks: flockAgeWeeks ?? this.flockAgeWeeks,
      status: status ?? this.status,
      selectedStationKeys: selectedStationKeys ?? this.selectedStationKeys,
      stationsCompleted: stationsCompleted ?? this.stationsCompleted,
      findingsJson: findingsJson ?? this.findingsJson,
      scorecardJson: scorecardJson ?? this.scorecardJson,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      dirtyAt: dirtyAt ?? this.dirtyAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: syncError ?? this.syncError,
    );
  }
}
