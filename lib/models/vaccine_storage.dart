import 'dart:convert';

class FridgeVaccine {
  String name;
  String? manufacturer;
  String? batchNumber;
  DateTime? expiryDate;
  double? storageTemp; // °C

  FridgeVaccine({
    required this.name,
    this.manufacturer,
    this.batchNumber,
    this.expiryDate,
    this.storageTemp,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'manufacturer': manufacturer,
        'batch_number': batchNumber,
        'expiry_date': expiryDate?.toIso8601String(),
        'storage_temp': storageTemp,
      };

  factory FridgeVaccine.fromMap(Map<String, dynamic> m) => FridgeVaccine(
        name: m['name'] as String,
        manufacturer: m['manufacturer'] as String?,
        batchNumber: m['batch_number'] as String?,
        expiryDate: m['expiry_date'] != null
            ? DateTime.parse(m['expiry_date'] as String)
            : null,
        storageTemp: (m['storage_temp'] as num?)?.toDouble(),
      );
}

class HvtContainer {
  String? id;
  String? lotNumber;
  DateTime? expiryDate;
  double? storageTemp; // typically liquid nitrogen, -196 °C

  HvtContainer({
    this.id,
    this.lotNumber,
    this.expiryDate,
    this.storageTemp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'lot_number': lotNumber,
        'expiry_date': expiryDate?.toIso8601String(),
        'storage_temp': storageTemp,
      };

  factory HvtContainer.fromMap(Map<String, dynamic> m) => HvtContainer(
        id: m['id'] as String?,
        lotNumber: m['lot_number'] as String?,
        expiryDate: m['expiry_date'] != null
            ? DateTime.parse(m['expiry_date'] as String)
            : null,
        storageTemp: (m['storage_temp'] as num?)?.toDouble(),
      );
}

class VaccineStorage {
  final String id;
  final String auditSessionId;
  final String customerId;
  final String flockId;

  // ── Ambient room conditions ───────────────────────────────────────────────
  double? roomTemperature;
  double? roomHumidity;

  // ── Fridge vaccines ───────────────────────────────────────────────────────
  /// JSON-encoded List of FridgeVaccine maps
  String fridgeVaccinesJson;

  List<FridgeVaccine> get fridgeVaccines {
    if (fridgeVaccinesJson.isEmpty || fridgeVaccinesJson == '[]') return [];
    final decoded = jsonDecode(fridgeVaccinesJson) as List;
    return decoded
        .map((e) => FridgeVaccine.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  set fridgeVaccines(List<FridgeVaccine> value) {
    fridgeVaccinesJson = jsonEncode(value.map((v) => v.toMap()).toList());
  }

  // ── HVT containers (liquid nitrogen) ─────────────────────────────────────
  /// JSON-encoded List of HvtContainer maps
  String hvtContainersJson;

  List<HvtContainer> get hvtContainers {
    if (hvtContainersJson.isEmpty || hvtContainersJson == '[]') return [];
    final decoded = jsonDecode(hvtContainersJson) as List;
    return decoded
        .map((e) => HvtContainer.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  set hvtContainers(List<HvtContainer> value) {
    hvtContainersJson = jsonEncode(value.map((c) => c.toMap()).toList());
  }

  // ── Compliance checklist ──────────────────────────────────────────────────
  bool coldChainMaintained;
  bool expiryDatesChecked;
  bool dilutionProtocolFollowed;
  bool vaccinationRoomBiosecure;

  // ── Meta ──────────────────────────────────────────────────────────────────
  bool isCompleted;
  DateTime createdAt;

  VaccineStorage({
    required this.id,
    required this.auditSessionId,
    required this.customerId,
    required this.flockId,
    this.roomTemperature,
    this.roomHumidity,
    String? fridgeVaccinesJson,
    String? hvtContainersJson,
    this.coldChainMaintained = false,
    this.expiryDatesChecked = false,
    this.dilutionProtocolFollowed = false,
    this.vaccinationRoomBiosecure = false,
    this.isCompleted = false,
    required this.createdAt,
  })  : fridgeVaccinesJson = fridgeVaccinesJson ?? '[]',
        hvtContainersJson = hvtContainersJson ?? '[]';

  Map<String, dynamic> toMap() => {
        'id': id,
        'audit_session_id': auditSessionId,
        'customer_id': customerId,
        'flock_id': flockId,
        'room_temperature': roomTemperature,
        'room_humidity': roomHumidity,
        'fridge_vaccines': fridgeVaccinesJson,
        'hvt_containers': hvtContainersJson,
        'cold_chain_maintained': coldChainMaintained ? 1 : 0,
        'expiry_dates_checked': expiryDatesChecked ? 1 : 0,
        'dilution_protocol_followed': dilutionProtocolFollowed ? 1 : 0,
        'vaccination_room_biosecure': vaccinationRoomBiosecure ? 1 : 0,
        'is_completed': isCompleted ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory VaccineStorage.fromMap(Map<String, dynamic> m) => VaccineStorage(
        id: m['id'] as String,
        auditSessionId: m['audit_session_id'] as String,
        customerId: m['customer_id'] as String,
        flockId: m['flock_id'] as String,
        roomTemperature: (m['room_temperature'] as num?)?.toDouble(),
        roomHumidity: (m['room_humidity'] as num?)?.toDouble(),
        fridgeVaccinesJson: (m['fridge_vaccines'] as String?) ?? '[]',
        hvtContainersJson: (m['hvt_containers'] as String?) ?? '[]',
        coldChainMaintained:
            (m['cold_chain_maintained'] == 1 || m['cold_chain_maintained'] == true),
        expiryDatesChecked:
            (m['expiry_dates_checked'] == 1 || m['expiry_dates_checked'] == true),
        dilutionProtocolFollowed: (m['dilution_protocol_followed'] == 1 ||
            m['dilution_protocol_followed'] == true),
        vaccinationRoomBiosecure: (m['vaccination_room_biosecure'] == 1 ||
            m['vaccination_room_biosecure'] == true),
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
