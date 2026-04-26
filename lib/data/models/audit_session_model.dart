import 'dart:convert';

const supportedStationKeys = [
  'egg_storage',
  'chick_quality',
  'hatch_analysis',
  'setter_optimizing',
  'hatcher_optimizing',
];

class AuditSessionModel {
  final String id;
  final String customerId;
  final String flockId;
  final String hatcheryId;
  final DateTime date;
  final String? breed;
  final int? flockAgeWeeks;
  final String status;
  final List<String> stationsCompleted;
  final String? findingsJson;
  final String? scorecardJson;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const AuditSessionModel({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.hatcheryId,
    required this.date,
    this.breed,
    this.flockAgeWeeks,
    this.status = 'in_progress',
    this.stationsCompleted = const [],
    this.findingsJson,
    this.scorecardJson,
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory AuditSessionModel.fromMap(Map<String, dynamic> map) {
    List<String> parseStationsCompleted(String? raw) {
      if (raw == null || raw.isEmpty) return [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return [];
    }

    return AuditSessionModel(
      id: map['id'] as String,
      customerId: map['customerId'] as String,
      flockId: map['flockId'] as String,
      hatcheryId: map['hatcheryId'] as String,
      date:
          DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      breed: map['breed'] as String?,
      flockAgeWeeks: map['flockAgeWeeks'] as int?,
      status: map['status'] as String? ?? 'in_progress',
      stationsCompleted: parseStationsCompleted(map['stationsCompleted'] as String?),
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'flockId': flockId,
      'hatcheryId': hatcheryId,
      'date': date.toIso8601String(),
      'breed': breed,
      'flockAgeWeeks': flockAgeWeeks,
      'status': status,
      'stationsCompleted': stationsCompleted.isEmpty
          ? null
          : jsonEncode(stationsCompleted),
      'findingsJson': findingsJson,
      'scorecardJson': scorecardJson,
      'notes': notes,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  AuditSessionModel copyWith({
    String? flockId,
    String? hatcheryId,
    DateTime? date,
    String? breed,
    int? flockAgeWeeks,
    String? status,
    List<String>? stationsCompleted,
    String? findingsJson,
    String? scorecardJson,
    String? notes,
    String? createdBy,
    DateTime? updatedAt,
    DateTime? completedAt,
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
      stationsCompleted: stationsCompleted ?? this.stationsCompleted,
      findingsJson: findingsJson ?? this.findingsJson,
      scorecardJson: scorecardJson ?? this.scorecardJson,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
