import 'package:flutter/material.dart';

/// 角色权限守卫 — 集中管理各功能的角色访问控制
///
/// 用法：
/// - 页面 build() 中调用 `RoleGuard.requireRole(context, role)` 检查权限并拦截
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
  static bool canImportData(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否可以配置 Gitee 令牌
  static bool canConfigGitee(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否可以查看所有学生仓库
  static bool canViewAllRepos(String role) =>
      role == 'admin' || role == 'teacher';

  /// 是否是教师或管理员
  static bool isTeacherOrAdmin(String role) =>
      role == 'admin' || role == 'teacher';

  // ── UI 层路由守卫 ──────────────────────────────────────────────────

  /// 检查当前用户是否拥有指定角色，无权限时弹出提示并返回 false
  ///
  /// ```dart
  /// if (!RoleGuard.requireRole(context, 'teacher')) return;
  /// ```
  static bool requireRole(BuildContext context, String requiredRole) {
    final currentRole = _currentRole;
    if (currentRole == null) {
      _showDeniedDialog(context, '未登录，请先登录');
      return false;
    }
    if (requiredRole == 'admin' && currentRole != 'admin') {
      _showDeniedDialog(context, '此功能仅管理员可用');
      return false;
    }
    if (requiredRole == 'teacher' &&
        currentRole != 'admin' &&
        currentRole != 'teacher') {
      _showDeniedDialog(context, '此功能仅教师或管理员可用');
      return false;
    }
    return true;
  }

  /// 快捷方法：要求教师或管理员角色
  static bool requireTeacher(BuildContext context) =>
      requireRole(context, 'teacher');

  /// 快捷方法：要求管理员角色
  static bool requireAdmin(BuildContext context) =>
      requireRole(context, 'admin');

  /// 当前用户角色（由 AuthService 在登录时设置）
  static String? _currentRole;

  /// 更新当前角色缓存（应在登录成功后调用）
  static void updateCurrentRole(String? role) {
    _currentRole = role;
  }

  static void _showDeniedDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Text('权限不足'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
