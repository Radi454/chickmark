class HatcheryMachineModel {
  HatcheryMachineModel({
    required this.id,
    required this.hatcheryId,
    required this.kind,
    required String code,
    required this.name,
    required this.batchSize,
    required this.trolleyCapacity,
    required this.traySize,
    required this.trolleyCount,
    required this.traysPerTrolley,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  }) : code = normalizeCode(code) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (hatcheryId.trim().isEmpty) {
      throw ArgumentError.value(hatcheryId, 'hatcheryId');
    }
    if (kind != 'setter' && kind != 'hatcher') {
      throw ArgumentError.value(kind, 'kind', 'Expected setter or hatcher');
    }
    if (this.code.isEmpty) throw ArgumentError.value(code, 'code');
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    final calculated = calculateCounts(
      batchSize: batchSize,
      trolleyCapacity: trolleyCapacity,
      traySize: traySize,
    );
    if (trolleyCount != calculated.trolleyCount ||
        traysPerTrolley != calculated.traysPerTrolley) {
      throw ArgumentError(
        'Registered trolley and tray counts must match the supplied capacities.',
      );
    }
  }

  final String id;
  final String hatcheryId;
  final String kind;
  final String code;
  final String name;
  final int batchSize;
  final int trolleyCapacity;
  final int traySize;
  final int trolleyCount;
  final int traysPerTrolley;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  static String normalizeCode(String value) => value.trim().toUpperCase();

  static ({int trolleyCount, int traysPerTrolley}) calculateCounts({
    required int batchSize,
    required int trolleyCapacity,
    required int traySize,
  }) {
    if (batchSize <= 0) throw ArgumentError.value(batchSize, 'batchSize');
    if (trolleyCapacity <= 0) {
      throw ArgumentError.value(trolleyCapacity, 'trolleyCapacity');
    }
    if (traySize <= 0) throw ArgumentError.value(traySize, 'traySize');
    return (
      trolleyCount: (batchSize + trolleyCapacity - 1) ~/ trolleyCapacity,
      traysPerTrolley: (trolleyCapacity + traySize - 1) ~/ traySize,
    );
  }

  factory HatcheryMachineModel.fromMap(Map<String, dynamic> map) {
    final batchSize = _readInt(map['batchSize'] ?? map['batch_size']);
    final trolleyCapacity = _readInt(
      map['trolleyCapacity'] ?? map['trolley_capacity'],
    );
    final traySize = _readInt(map['traySize'] ?? map['tray_size']);
    final counts = calculateCounts(
      batchSize: batchSize,
      trolleyCapacity: trolleyCapacity,
      traySize: traySize,
    );
    return HatcheryMachineModel(
      id: _readText(map['id']),
      hatcheryId: _readText(map['hatcheryId'] ?? map['hatchery_id']),
      kind: _readText(map['kind']),
      code: _readText(map['code']),
      name: _readText(map['name']),
      batchSize: batchSize,
      trolleyCapacity: trolleyCapacity,
      traySize: traySize,
      trolleyCount:
          _readOptionalInt(map['trolleyCount'] ?? map['trolley_count']) ??
          counts.trolleyCount,
      traysPerTrolley:
          _readOptionalInt(
            map['traysPerTrolley'] ?? map['trays_per_trolley'],
          ) ??
          counts.traysPerTrolley,
      createdAt: _readDate(map['createdAt'] ?? map['created_at']),
      updatedAt: _readDate(map['updatedAt'] ?? map['updated_at']),
      createdBy: _readOptionalText(map['createdBy'] ?? map['created_by']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'hatcheryId': hatcheryId,
    'kind': kind,
    'code': code,
    'name': name.trim(),
    'batchSize': batchSize,
    'trolleyCapacity': trolleyCapacity,
    'traySize': traySize,
    'trolleyCount': trolleyCount,
    'traysPerTrolley': traysPerTrolley,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (createdBy != null) 'createdBy': createdBy,
  };
}

String _readText(Object? value) => value?.toString() ?? '';

String? _readOptionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _readInt(Object? value) => _readOptionalInt(value) ?? 0;

int? _readOptionalInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

DateTime? _readDate(Object? value) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}
