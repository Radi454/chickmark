import 'dart:convert';

class AuditSession {
  final String id;
  final String customerId;
  final String flockId;
  String breed;
  double flockAgeWeeks;
  double eggProductionAgeWeeks;
  DateTime auditDate;
  String? benchmarkSet;
  bool isCompleted;
  DateTime createdAt;

  /// Keys are section identifiers. A section is considered completed when
  /// its corresponding model sets isCompleted = true and saves to the DB.
  /// This list is derived from the audit session's related records at runtime.
  /// Stored as a JSON-encoded list of section-name strings in the DB.
  List<String> _completedSections;

  AuditSession({
    required this.id,
    required this.customerId,
    required this.flockId,
    required this.breed,
    required this.flockAgeWeeks,
    required this.eggProductionAgeWeeks,
    required this.auditDate,
    this.benchmarkSet,
    this.isCompleted = false,
    required this.createdAt,
    List<String>? completedSections,
  }) : _completedSections = completedSections ?? [];

  /// Returns the list of section keys that have been marked complete.
  /// Valid section keys:
  ///   'chick_quality', 'egg_breakout', 'setter_measurements',
  ///   'hatcher_measurements', 'vaccine_storage', 'egg_storage',
  ///   'hatchery_results'
  List<String> get completedSections => List.unmodifiable(_completedSections);

  void markSectionCompleted(String sectionKey) {
    if (!_completedSections.contains(sectionKey)) {
      _completedSections.add(sectionKey);
    }
  }

  void markSectionIncomplete(String sectionKey) {
    _completedSections.remove(sectionKey);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'flock_id': flockId,
    'breed': breed,
    'flock_age_weeks': flockAgeWeeks,
    'egg_production_age_weeks': eggProductionAgeWeeks,
    'audit_date': auditDate.toIso8601String(),
    'benchmark_set': benchmarkSet,
    'is_completed': isCompleted ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'completed_sections': jsonEncode(_completedSections),
  };

  factory AuditSession.fromMap(Map<String, dynamic> m) {
    List<String> sections = [];
    if (m['completed_sections'] != null) {
      final decoded = jsonDecode(m['completed_sections'] as String);
      if (decoded is List) {
        sections = decoded.map((e) => e.toString()).toList();
      }
    }
    return AuditSession(
      id: m['id'] as String,
      customerId: m['customer_id'] as String,
      flockId: m['flock_id'] as String,
      breed: m['breed'] as String,
      flockAgeWeeks: (m['flock_age_weeks'] as num).toDouble(),
      eggProductionAgeWeeks: (m['egg_production_age_weeks'] as num).toDouble(),
      auditDate: DateTime.parse(m['audit_date'] as String),
      benchmarkSet: m['benchmark_set'] as String?,
      isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
      createdAt: DateTime.parse(m['created_at'] as String),
      completedSections: sections,
    );
  }
}
