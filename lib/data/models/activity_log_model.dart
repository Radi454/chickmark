class ActivityLogModel {
  final String id;
  final String userId;
  final String action;
  final String? entityType;
  final String? entityId;
  final String? details;
  final DateTime timestamp;

  const ActivityLogModel({
    required this.id,
    required this.userId,
    required this.action,
    this.entityType,
    this.entityId,
    this.details,
    required this.timestamp,
  });

  factory ActivityLogModel.fromMap(Map<String, dynamic> map) {
    return ActivityLogModel(
      id: map['id'] as String,
      userId: map['userId'] as String,
      action: map['action'] as String,
      entityType: map['entityType'] as String?,
      entityId: map['entityId'] as String?,
      details: map['details'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
