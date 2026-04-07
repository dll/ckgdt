/// 角色权限守卫 — 集中管理各功能的角色访问控制
///
/// 用法：
/// - 页面 build() 中调用 `RoleGuard.requireTeacher(context, authService)` 检查权限
/// - DAO/Service 中调用 `RoleGuard.canManageQuestions(role)` 判断是否有权限
class RoleGuard {
  // ── 权限判断（纯逻辑，不依赖 Flutter） ──────────────────────────────

  /// 是否可以管理题库（增删改题目）
  static bool canManageQuestions(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否可以管理学生账号
  static bool canManageStudents(String role) => role == 'admin';

  /// 是否可以评分作品
  static bool canScoreWorks(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否可以管理考核（编辑分组/评分/答辩）
  static bool canManageAssessment(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否可以导入/导出系统数据
  static bool canImportData(String role) => role == 'admin';

  /// 是否可以配置 Gitee 令牌
  static bool canConfigGitee(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否可以查看所有学生仓库
  static bool canViewAllRepos(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否是教师或管理员
  static bool isTeacherOrAdmin(String role) =>
      role == 'admin' || role == 'teacher';
}
