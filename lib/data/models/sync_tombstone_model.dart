class SyncTombstone {
  const SyncTombstone({
    required this.id,
    required this.tableName,
    required this.rowId,
    required this.deletedAt,
    required this.createdAt,
    this.syncedAt,
    this.lastError,
  });

  final String id;
  final String tableName;
  final String rowId;
  final DateTime deletedAt;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final String? lastError;

  bool get isPending => syncedAt == null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tableName': tableName,
      'rowId': rowId,
      'deletedAt': deletedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'lastError': lastError,
    };
  }

  factory SyncTombstone.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return SyncTombstone(
      id: '${map['id']}',
      tableName: '${map['tableName'] ?? map['table_name']}',
      rowId: '${map['rowId'] ?? map['row_id']}',
      deletedAt: _parseDate(map['deletedAt'] ?? map['deleted_at']) ?? now,
      createdAt: _parseDate(map['createdAt'] ?? map['created_at']) ?? now,
      syncedAt: _parseDate(map['syncedAt'] ?? map['synced_at']),
      lastError: (map['lastError'] ?? map['last_error']) as String?,
    );
  }

  SyncTombstone copyWith({
    DateTime? syncedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return SyncTombstone(
      id: id,
      tableName: tableName,
      rowId: rowId,
      deletedAt: deletedAt,
      createdAt: createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  static String makeId(String tableName, String rowId) => '$tableName:$rowId';

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }
}
