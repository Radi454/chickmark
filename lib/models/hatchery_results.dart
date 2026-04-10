import 'dart:convert';

/// Data for a single hatcher machine within a hatchery results record.
class HatcherEntry {
  String setterId;
  String hatcherId;
  int? eggsSet;
  int? hatched;
  int? culled;
  int? dead;
  int? infertileCount;
  double? fertilityPercent; // manual input

  HatcherEntry({
    this.setterId = '',
    this.hatcherId = '',
    this.eggsSet,
    this.hatched,
    this.culled,
    this.dead,
    this.infertileCount,
    this.fertilityPercent,
  });

  /// Hatchability% = Hatched / TotalHatcherCapacity × 100
  /// (Computed by screen — requires totalHatcherCapacity from parent)
  double? hatchabilityPct(int totalHatcherCapacity) {
    if (hatched == null || totalHatcherCapacity == 0) return null;
    return (hatched! / totalHatcherCapacity) * 100;
  }

  /// HOF% = Hatchability% / Fertility% × 100
  double? hofPct(int totalHatcherCapacity) {
    final h = hatchabilityPct(totalHatcherCapacity);
    final f = fertilityPercent;
    if (h == null || f == null || f == 0) return null;
    return (h / f) * 100;
  }

  Map<String, dynamic> toMap() => {
        'setterId': setterId,
        'hatcherId': hatcherId,
        'eggsSet': eggsSet,
        'hatched': hatched,
        'culled': culled,
        'dead': dead,
        'infertileCount': infertileCount,
        'fertilityPercent': fertilityPercent,
      };

  factory HatcherEntry.fromMap(Map<String, dynamic> m) => HatcherEntry(
        setterId: m['setterId'] as String? ?? '',
        hatcherId: m['hatcherId'] as String? ?? '',
        eggsSet: (m['eggsSet'] as num?)?.toInt(),
        hatched: (m['hatched'] as num?)?.toInt(),
        culled: (m['culled'] as num?)?.toInt(),
        dead: (m['dead'] as num?)?.toInt(),
        infertileCount: (m['infertileCount'] as num?)?.toInt(),
        fertilityPercent: (m['fertilityPercent'] as num?)?.toDouble(),
      );
}

class HatcheryResults {
  final String id;
  final String auditSessionId;
  final String customerId;
  final String flockId;

  // ── Top-level fixed fields ─────────────────────────────────────────────────
  int? eggStorageDays;
  int? totalHatcherCapacity; // default 19200

  // ── Per-hatcher data ──────────────────────────────────────────────────────
  /// JSON-encoded `List<HatcherEntry>`
  String hatchersJson;

  List<HatcherEntry> get hatchers {
    if (hatchersJson.isEmpty) return [];
    final decoded = jsonDecode(hatchersJson) as List;
    return decoded
        .map((e) => HatcherEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  set hatchers(List<HatcherEntry> entries) {
    hatchersJson = jsonEncode(entries.map((e) => e.toMap()).toList());
  }

  // ── Meta ──────────────────────────────────────────────────────────────────
  bool isCompleted;
  DateTime createdAt;

  HatcheryResults({
    required this.id,
    required this.auditSessionId,
    required this.customerId,
    required this.flockId,
    this.eggStorageDays,
    this.totalHatcherCapacity = 19200,
    String? hatchersJson,
    this.isCompleted = false,
    required this.createdAt,
  }) : hatchersJson = hatchersJson ?? '[]';

  Map<String, dynamic> toMap() => {
        'id': id,
        'audit_session_id': auditSessionId,
        'customer_id': customerId,
        'flock_id': flockId,
        'egg_storage_days': eggStorageDays,
        'total_hatcher_capacity': totalHatcherCapacity ?? 19200,
        'hatchers_json': hatchersJson,
        'is_completed': isCompleted ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory HatcheryResults.fromMap(Map<String, dynamic> m) => HatcheryResults(
        id: m['id'] as String,
        auditSessionId: m['audit_session_id'] as String,
        customerId: m['customer_id'] as String,
        flockId: m['flock_id'] as String,
        eggStorageDays: (m['egg_storage_days'] as num?)?.toInt(),
        totalHatcherCapacity:
            (m['total_hatcher_capacity'] as num?)?.toInt() ?? 19200,
        hatchersJson: (m['hatchers_json'] as String?) ?? '[]',
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
