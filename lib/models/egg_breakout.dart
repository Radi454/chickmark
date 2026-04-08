import 'dart:convert';

/// All egg categories tracked per tray during breakout analysis.
const List<String> kEggBreakoutCategories = [
  'infertile',
  'earlyDead24h',
  'earlyDead48h',
  'bloodRing',
  'earlyDead',
  'midBlackEye',
  'feathers',
  'turned',
  'internalPip',
  'lateDead',
  'externalPip',
  'exposedBrain',
  'crossedBeak',
  'contaminated',
  'cracked',
];

/// Human-readable labels for each category.
const Map<String, String> kEggBreakoutCategoryLabels = {
  'infertile': 'Infertile',
  'earlyDead24h': 'Early Dead <24h',
  'earlyDead48h': 'Early Dead 24–48h',
  'bloodRing': 'Blood Ring',
  'earlyDead': 'Early Dead (3–7d)',
  'midBlackEye': 'Mid Dead / Black Eye',
  'feathers': 'Feathers',
  'turned': 'Turned',
  'internalPip': 'Internal Pip',
  'lateDead': 'Late Dead',
  'externalPip': 'External Pip',
  'exposedBrain': 'Exposed Brain',
  'crossedBeak': 'Crossed Beak',
  'contaminated': 'Contaminated',
  'cracked': 'Cracked',
};

/// Tray positions available for selection.
const List<String> kTrayPositions = ['Top', 'Middle', 'Bottom'];

class EggBreakout {
  final String id;
  final String auditSessionId;
  final String customerId;
  final String flockId;

  // ── Top-level fields ──────────────────────────────────────────────────────
  int? eggStorageDays;
  int? eggBreakoutAgeDays;
  String? incubatorId;
  String? hatcherId;
  int? sampleSize;

  // ── Per-tray data (legacy flat format) ───────────────────────────────────
  /// JSON-encoded List<Map<String, dynamic>>.
  /// Each map: {"trayId": "1", "trayPosition": "Top", "infertile": 2, ...}
  String trayDataJson;

  List<Map<String, dynamic>> get trayData {
    if (trayDataJson.isEmpty) return [];
    final decoded = jsonDecode(trayDataJson) as List;
    return decoded.map<Map<String, dynamic>>((tray) {
      final map = tray as Map<String, dynamic>;
      return Map<String, dynamic>.from(map);
    }).toList();
  }

  set trayData(List<Map<String, dynamic>> data) {
    trayDataJson = jsonEncode(data);
  }

  /// Sum of a specific category across all trays.
  int categoryTotal(String category) {
    return trayData.fold(0, (sum, tray) {
      final v = tray[category];
      if (v is num) return sum + v.toInt();
      return sum;
    });
  }

  // ── Multi-hatch data (new format) ─────────────────────────────────────────
  /// JSON-encoded List of hatches, each containing incubatorId, hatcherId,
  /// sampleSize, and a list of trays (with breakoutDate, trayId, trayPosition,
  /// and 15 category counts).
  /// Format: [{incubatorId, hatcherId, sampleSize, trays:[{breakoutDate, trayId, trayPosition, ...cats}]}]
  String? hatchesJson;

  List<Map<String, dynamic>> get hatches {
    if (hatchesJson == null || hatchesJson!.isEmpty) return [];
    final decoded = jsonDecode(hatchesJson!) as List;
    return decoded
        .map<Map<String, dynamic>>((h) => Map<String, dynamic>.from(h as Map))
        .toList();
  }

  set hatches(List<Map<String, dynamic>> data) {
    hatchesJson = jsonEncode(data);
  }

  // ── Meta ──────────────────────────────────────────────────────────────────
  bool isCompleted;
  DateTime createdAt;

  EggBreakout({
    required this.id,
    required this.auditSessionId,
    required this.customerId,
    required this.flockId,
    this.eggStorageDays,
    this.eggBreakoutAgeDays,
    this.incubatorId,
    this.hatcherId,
    this.sampleSize,
    String? trayDataJson,
    this.hatchesJson,
    this.isCompleted = false,
    required this.createdAt,
  }) : trayDataJson = trayDataJson ?? '[]';

  Map<String, dynamic> toMap() => {
        'id': id,
        'audit_session_id': auditSessionId,
        'customer_id': customerId,
        'flock_id': flockId,
        'egg_storage_days': eggStorageDays,
        'egg_breakout_age_days': eggBreakoutAgeDays,
        'incubator_id': incubatorId,
        'hatcher_id': hatcherId,
        'sample_size': sampleSize,
        'tray_data': trayDataJson,
        'hatches_json': hatchesJson,
        'is_completed': isCompleted ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory EggBreakout.fromMap(Map<String, dynamic> m) => EggBreakout(
        id: m['id'] as String,
        auditSessionId: m['audit_session_id'] as String,
        customerId: m['customer_id'] as String,
        flockId: m['flock_id'] as String,
        eggStorageDays: (m['egg_storage_days'] as num?)?.toInt(),
        eggBreakoutAgeDays: (m['egg_breakout_age_days'] as num?)?.toInt(),
        incubatorId: m['incubator_id'] as String?,
        hatcherId: m['hatcher_id'] as String?,
        sampleSize: (m['sample_size'] as num?)?.toInt(),
        trayDataJson: (m['tray_data'] as String?) ?? '[]',
        hatchesJson: m['hatches_json'] as String?,
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
