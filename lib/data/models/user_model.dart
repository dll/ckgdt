class UserModel {
  final String userId;
  final String? realName;
  final String? machineCode;
  final String role; // student, teacher, admin
  final String? createdAt;
  final String? lastLogin;
  final bool isActive;

  UserModel({
    required this.userId,
    this.realName,
    this.machineCode,
    this.role = 'student',
    this.createdAt,
    this.lastLogin,
    this.isActive = true,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      userId: map['user_id'] ?? '',
      realName: map['real_name'],
      machineCode: map['machine_code'],
      role: map['role'] ?? 'student',
      createdAt: map['created_at'],
      lastLogin: map['last_login'],
      isActive: map['is_active'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'real_name': realName,
      'machine_code': machineCode,
      'role': role,
      'created_at': createdAt,
      'last_login': lastLogin,
      'is_active': isActive ? 1 : 0,
    };
  }

  String get password => userId.length >= 6 ? userId.substring(userId.length - 6) : '';

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
}
