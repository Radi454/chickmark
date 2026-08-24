class PhotoModel {
  final String id;
  final String filePath;
  final String? description;
  final DateTime createdAt;
  final String sessionId;
  final String panelName;
  final String panelRowId;
  final String fieldKey;
  final String? observationId;
  final String uploadStatus;

  PhotoModel({
    required this.id,
    required this.filePath,
    this.description,
    required this.createdAt,
    required this.sessionId,
    required this.panelName,
    required this.panelRowId,
    required this.fieldKey,
    this.observationId,
    this.uploadStatus = 'local',
  });

  factory PhotoModel.fromMap(Map<String, dynamic> map) {
    return PhotoModel(
      id: map['id'] as String,
      filePath: map['filePath'] ?? map['file_path'],
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['createdAt'] ?? map['created_at']),
      sessionId: map['sessionId'] ?? map['session_id'],
      panelName: map['panelName'] ?? map['panel_name'] ?? 'unknown_panel',
      panelRowId: map['panelRowId'] ?? map['panel_row_id'],
      fieldKey: map['fieldKey'] ?? map['field_key'] ?? 'evidence',
      observationId: map['observationId'] ?? map['observation_id'],
      uploadStatus: map['uploadStatus'] ?? map['upload_status'] ?? 'synced',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'sessionId': sessionId,
      'panelName': panelName,
      'panelRowId': panelRowId,
      'fieldKey': fieldKey,
      'observationId': observationId,
      'uploadStatus': uploadStatus,
    };
  }
}
