class HatcherMeasurements {
  final String id;
  final String auditSessionId;
  final String customerId;
  final String flockId;

  // ── Hatcher identification ────────────────────────────────────────────────
  String? hatcherId;

  // ── Govee BLE ambient readings ────────────────────────────────────────────
  double? temperature;
  double? humidity;

  // ── Chick vent temperature grid (3 × 3) ──────────────────────────────────
  // Row: top / mid / bot   Column: front / middle / back
  double? topFront;
  double? topMiddle;
  double? topBack;
  double? midFront;
  double? midMiddle;
  double? midBack;
  double? botFront;
  double? botMiddle;
  double? botBack;

  /// Average of all non-null grid cells.
  double? get gridAverage {
    final cells = [
      topFront, topMiddle, topBack,
      midFront, midMiddle, midBack,
      botFront, botMiddle, botBack,
    ].whereType<double>().toList();
    if (cells.isEmpty) return null;
    return cells.reduce((a, b) => a + b) / cells.length;
  }

  // ── Meta ──────────────────────────────────────────────────────────────────
  bool isCompleted;
  DateTime createdAt;

  HatcherMeasurements({
    required this.id,
    required this.auditSessionId,
    required this.customerId,
    required this.flockId,
    this.hatcherId,
    this.temperature,
    this.humidity,
    this.topFront,
    this.topMiddle,
    this.topBack,
    this.midFront,
    this.midMiddle,
    this.midBack,
    this.botFront,
    this.botMiddle,
    this.botBack,
    this.isCompleted = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'audit_session_id': auditSessionId,
        'customer_id': customerId,
        'flock_id': flockId,
        'hatcher_id': hatcherId,
        'temperature': temperature,
        'humidity': humidity,
        'top_front': topFront,
        'top_middle': topMiddle,
        'top_back': topBack,
        'mid_front': midFront,
        'mid_middle': midMiddle,
        'mid_back': midBack,
        'bot_front': botFront,
        'bot_middle': botMiddle,
        'bot_back': botBack,
        'is_completed': isCompleted ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory HatcherMeasurements.fromMap(Map<String, dynamic> m) =>
      HatcherMeasurements(
        id: m['id'] as String,
        auditSessionId: m['audit_session_id'] as String,
        customerId: m['customer_id'] as String,
        flockId: m['flock_id'] as String,
        hatcherId: m['hatcher_id'] as String?,
        temperature: (m['temperature'] as num?)?.toDouble(),
        humidity: (m['humidity'] as num?)?.toDouble(),
        topFront: (m['top_front'] as num?)?.toDouble(),
        topMiddle: (m['top_middle'] as num?)?.toDouble(),
        topBack: (m['top_back'] as num?)?.toDouble(),
        midFront: (m['mid_front'] as num?)?.toDouble(),
        midMiddle: (m['mid_middle'] as num?)?.toDouble(),
        midBack: (m['mid_back'] as num?)?.toDouble(),
        botFront: (m['bot_front'] as num?)?.toDouble(),
        botMiddle: (m['bot_middle'] as num?)?.toDouble(),
        botBack: (m['bot_back'] as num?)?.toDouble(),
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
