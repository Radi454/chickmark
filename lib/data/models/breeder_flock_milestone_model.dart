/// Operational milestone events for a breeder flock (breeder-flock
/// -performance ticket 06). `breeder_flock_milestones` records dated events
/// such as grading and first egg against a flock. Event types are a
/// constrained set (see [BreederFlockMilestoneType]), not free text, so
/// downstream lookups (e.g. the 5%-production comparison axis in
/// `BreederFlockLifecycleService`) can rely on a known vocabulary.
library;

/// The fixed set of operational milestone events a flock can record. This
/// mirrors the CHECK constraint on `breeder_flock_milestones.eventType` in
/// `database_schema.dart` — keep both in sync.
class BreederFlockMilestoneType {
  static const String grading = 'grading';
  static const String physicalTransfer = 'physical_transfer';
  static const String lightStimulation = 'light_stimulation';
  static const String firstEgg = 'first_egg';
  static const String fivePercentProduction = 'five_percent_production';
  static const String fiftyPercentProduction = 'fifty_percent_production';
  static const String peakProduction = 'peak_production';
  static const String partialDepletion = 'partial_depletion';
  static const String startOfDepletion = 'start_of_depletion';
  static const String finalDepletion = 'final_depletion';

  static const List<String> all = [
    grading,
    physicalTransfer,
    lightStimulation,
    firstEgg,
    fivePercentProduction,
    fiftyPercentProduction,
    peakProduction,
    partialDepletion,
    startOfDepletion,
    finalDepletion,
  ];

  static bool isValid(String value) => all.contains(value);

  /// Short display label for the milestone type, used by flock-detail UI.
  static String label(String eventType) {
    switch (eventType) {
      case grading:
        return 'Grading';
      case physicalTransfer:
        return 'Physical transfer';
      case lightStimulation:
        return 'Light stimulation';
      case firstEgg:
        return 'First egg';
      case fivePercentProduction:
        return '5% production';
      case fiftyPercentProduction:
        return '50% production';
      case peakProduction:
        return 'Peak production';
      case partialDepletion:
        return 'Partial depletion';
      case startOfDepletion:
        return 'Start of depletion';
      case finalDepletion:
        return 'Final depletion';
      default:
        return eventType;
    }
  }
}

class BreederFlockMilestone {
  final String id;
  final String flockId;
  final String eventType;
  final DateTime eventDate;
  final String? notes;

  const BreederFlockMilestone({
    required this.id,
    required this.flockId,
    required this.eventType,
    required this.eventDate,
    this.notes,
  });

  factory BreederFlockMilestone.fromMap(Map<String, dynamic> map) {
    return BreederFlockMilestone(
      id: map['id'] as String,
      flockId: map['flockId'] as String,
      eventType: map['eventType'] as String,
      eventDate: DateTime.parse(map['eventDate'] as String),
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'flockId': flockId,
      'eventType': eventType,
      'eventDate': eventDate.toIso8601String(),
      'notes': notes,
    };
  }

  BreederFlockMilestone copyWith({
    String? id,
    String? flockId,
    String? eventType,
    DateTime? eventDate,
    String? notes,
  }) {
    return BreederFlockMilestone(
      id: id ?? this.id,
      flockId: flockId ?? this.flockId,
      eventType: eventType ?? this.eventType,
      eventDate: eventDate ?? this.eventDate,
      notes: notes ?? this.notes,
    );
  }
}
