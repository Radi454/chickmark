class UserModel {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final String? customerId;
  final String? accessToken;
  final DateTime? tokenExpiry;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    this.customerId,
    this.accessToken,
    this.tokenExpiry,
    required this.createdAt,
    this.lastLoginAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      fullName: map['fullName'],
      email: map['email'],
      role: map['role'],
      status: map['status'],
      customerId: map['customerId'],
      accessToken: map['accessToken'],
      tokenExpiry: map['tokenExpiry'] != null
          ? DateTime.parse(map['tokenExpiry'])
          : null,
      createdAt: DateTime.parse(map['createdAt']),
      lastLoginAt: map['lastLoginAt'] != null
          ? DateTime.parse(map['lastLoginAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'role': role,
      'status': status,
      'customerId': customerId,
      'accessToken': accessToken,
      'tokenExpiry': tokenExpiry?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
    };
  }

  bool get isTokenValid {
    if (tokenExpiry == null) return false;
    return tokenExpiry!.isAfter(DateTime.now());
  }

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isAuditor => role.toLowerCase() == 'auditor';
  bool get isCustomer => role.toLowerCase() == 'customer';
  bool get canEditAudits => isApproved && (isAdmin || isAuditor);
}
