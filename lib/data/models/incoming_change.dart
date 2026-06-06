import 'dart:convert';

/// A single record pulled from Supabase that did NOT originate on this device —
/// either created on another device (no local copy before the pull) or edited on
/// another device (remote `updatedAt` strictly newer than ours). Surfaced on the
/// home "Sync & Offline" sector until the user acknowledges it.
///
/// Detected during pull by [StartupSyncService]; persisted by [SettingsProvider]
/// to SharedPreferences as JSON so the notice survives app restarts.
class IncomingChange {
  final String table;
  final String rowId;

  /// true = created on another device, false = updated on another device.
  final bool isNew;

  /// Human label, e.g. "Acme Farms · Flock 12".
  final String label;

  /// Secondary line, e.g. "Audit 2026-06-05 · by jane@x.com".
  final String subtitle;

  /// Remote `updatedAt` at detection time (ISO 8601).
  final String updatedAt;

  const IncomingChange({
    required this.table,
    required this.rowId,
    required this.isNew,
    required this.label,
    required this.subtitle,
    required this.updatedAt,
  });

  /// Stable identity for dedupe across sync runs.
  String get key => '$table:$rowId';

  Map<String, dynamic> toJson() => {
    'table': table,
    'rowId': rowId,
    'isNew': isNew,
    'label': label,
    'subtitle': subtitle,
    'updatedAt': updatedAt,
  };

  factory IncomingChange.fromJson(Map<String, dynamic> json) => IncomingChange(
    table: json['table'] as String? ?? '',
    rowId: json['rowId'] as String? ?? '',
    isNew: json['isNew'] as bool? ?? false,
    label: json['label'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    updatedAt: json['updatedAt'] as String? ?? '',
  );

  static String encodeList(List<IncomingChange> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<IncomingChange> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => IncomingChange.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
