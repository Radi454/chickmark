class PhotoModel {
  final String id;
  final String filePath;
  final String? description;
  final DateTime createdAt;
  final String auditId;

  PhotoModel({
    required this.id,
    required this.filePath,
    this.description,
    required this.createdAt,
    required this.auditId,
  });

  factory PhotoModel.fromMap(Map<String, dynamic> map) {
    return PhotoModel(
      id: map['id'],
      filePath: map['filePath'],
      description: map['description'],
      createdAt: DateTime.parse(map['createdAt']),
      auditId: map['auditId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'auditId': auditId,
    };
  }
}
