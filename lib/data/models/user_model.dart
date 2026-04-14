class UserModel {
  final String userId;
  final String? realName;
  final String? machineCode;
  final String role; // student, teacher, admin
  final String? createdAt;
  final String? lastLogin;
  final bool isActive;
  final String? repositoryUrl; // Gitee 仓库地址
  final String? lastActive; // 心跳时间戳（在线状态）

  UserModel({
    required this.userId,
    this.realName,
    this.machineCode,
    this.role = 'student',
    this.createdAt,
    this.lastLogin,
    this.isActive = true,
    this.repositoryUrl,
    this.lastActive,
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
      repositoryUrl: map['repository_url'],
      lastActive: map['last_active'],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'user_id': userId,
      'real_name': realName,
      'machine_code': machineCode,
      'role': role,
      'created_at': createdAt,
      'last_login': lastLogin,
      'is_active': isActive ? 1 : 0,
    };
    // repository_url 仅在有值时写入，避免表缺少此列时 insert/update 失败
    if (repositoryUrl != null) {
      map['repository_url'] = repositoryUrl;
    }
    if (lastActive != null) {
      map['last_active'] = lastActive;
    }
    return map;
  }

  /// 创建一个更新了部分字段的副本
  UserModel copyWith({
    String? userId,
    String? realName,
    String? machineCode,
    String? role,
    String? createdAt,
    String? lastLogin,
    bool? isActive,
    String? repositoryUrl,
    String? lastActive,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      realName: realName ?? this.realName,
      machineCode: machineCode ?? this.machineCode,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      isActive: isActive ?? this.isActive,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  String get password => userId.length >= 6 ? userId.substring(userId.length - 6) : '';

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
}
