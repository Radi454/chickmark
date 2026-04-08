class EggStorage {
  final String id;
  final String auditSessionId;
  final String customerId;
  final String flockId;

  // ── Storage room conditions ───────────────────────────────────────────────
  double? temperature;      // °C — room dry-bulb
  double? humidity;         // % RH
  double? eggshellTemperature; // °C — measured at shell surface

  // ── Handling details ──────────────────────────────────────────────────────
  String? turningFrequency;   // e.g. 'hourly', 'every 4h', 'none'
  String? uvTrays;            // 'yes' | 'no' | 'partial'
  int? storageDays;           // days eggs stored before setting

  // ── Sanitization ──────────────────────────────────────────────────────────
  String? sanitizationMethod; // e.g. 'fumigation', 'spray', 'UV', 'none'
  String? sanitizationAgent;  // e.g. 'formaldehyde', 'quaternary ammonium'

  // ── Meta ──────────────────────────────────────────────────────────────────
  bool isCompleted;
  DateTime createdAt;

  EggStorage({
    required this.id,
    required this.auditSessionId,
    required this.customerId,
    required this.flockId,
    this.temperature,
    this.humidity,
    this.eggshellTemperature,
    this.turningFrequency,
    this.uvTrays,
    this.storageDays,
    this.sanitizationMethod,
    this.sanitizationAgent,
    this.isCompleted = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'audit_session_id': auditSessionId,
        'customer_id': customerId,
        'flock_id': flockId,
        'temperature': temperature,
        'humidity': humidity,
        'eggshell_temperature': eggshellTemperature,
        'turning_frequency': turningFrequency,
        'uv_trays': uvTrays,
        'storage_days': storageDays,
        'sanitization_method': sanitizationMethod,
        'sanitization_agent': sanitizationAgent,
        'is_completed': isCompleted ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory EggStorage.fromMap(Map<String, dynamic> m) => EggStorage(
        id: m['id'] as String,
        auditSessionId: m['audit_session_id'] as String,
        customerId: m['customer_id'] as String,
        flockId: m['flock_id'] as String,
        temperature: (m['temperature'] as num?)?.toDouble(),
        humidity: (m['humidity'] as num?)?.toDouble(),
        eggshellTemperature: (m['eggshell_temperature'] as num?)?.toDouble(),
        turningFrequency: m['turning_frequency'] as String?,
        uvTrays: m['uv_trays'] as String?,
        storageDays: (m['storage_days'] as num?)?.toInt(),
        sanitizationMethod: m['sanitization_method'] as String?,
        sanitizationAgent: m['sanitization_agent'] as String?,
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
