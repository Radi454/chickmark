class UserModel {
  final String id;
  final String username;
  final String mobile;
  final String email;
  final String birthdate;
  final String gender;
  final String location;
  final String role;
  final bool isBroiler;
  final bool isLayer;
  final bool isBreeder;
  final String password;
  final String createdAt;

  UserModel({
    required this.id,
    required this.username,
    required this.mobile,
    required this.email,
    required this.birthdate,
    required this.gender,
    required this.location,
    required this.role,
    required this.isBroiler,
    required this.isLayer,
    required this.isBreeder,
    required this.password,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'mobile': mobile,
      'email': email,
      'birthdate': birthdate,
      'gender': gender,
      'location': location,
      'role': role,
      'is_broiler': isBroiler ? 1 : 0,
      'is_layer': isLayer ? 1 : 0,
      'is_breeder': isBreeder ? 1 : 0,
      'password': password,
      'created_at': createdAt,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      username: map['username'],
      mobile: map['mobile'] ?? '',
      email: map['email'] ?? '',
      birthdate: map['birthdate'] ?? '',
      gender: map['gender'] ?? '',
      location: map['location'] ?? '',
      role: map['role'] ?? '',
      isBroiler: (map['is_broiler'] as int? ?? 0) == 1,
      isLayer: (map['is_layer'] as int? ?? 0) == 1,
      isBreeder: (map['is_breeder'] as int? ?? 0) == 1,
      password: map['password'],
      createdAt: map['created_at'],
    );
  }
}
