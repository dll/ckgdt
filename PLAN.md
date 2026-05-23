# 实施计划：学生仓库简化 + 权限安全加固

## 一、仓库页面角色分离

### 现状
- `GitRepoPage` 对所有用户相同（4个Tab），学生可以看到所有仓库、配置 Gitee 令牌
- 学生需要的是：查看自己所在小组的仓库详情 + 个人提交信息

### 方案
**学生视图**（替换现有 Tab 8）— 新建 `StudentRepoPage`：
- Tab 1「我的项目」：显示学生所在小组仓库的详细信息（仓库名、描述、成员数、最近活跃）；学生个人分支的提交记录、提交次数统计
- Tab 2「提交规范」：保留现有提交规范指南（复用 `_SubmissionGuidelinesTab`）
- 去掉：仓库列表总览、Gitee 设置（学生不需要配置令牌）

**教师/管理员视图**：保持现有 `GitRepoPage` 不变（4个Tab全功能）

### 实现
1. 新建 `lib/presentation/pages/repo/student_repo_page.dart`
2. `home_page.dart` 中 case 8：根据角色分流 → 学生用 `StudentRepoPage`，教师/管理员用 `GitRepoPage`

## 二、权限安全加固（6项修复）

### 修复 1：登录密码漏洞
**文件**: `lib/data/local/user_dao.dart` 第 174 行
- 移除 `password.isEmpty` 条件 — 不允许空密码登录
- 保留 `last6` 和 `userId` 两种密码格式

### 修复 2：DAO 层增加 userId 校验
**文件**: `lib/data/local/wrong_answer_dao.dart`
- `removeWrongAnswer(int id)` → `removeWrongAnswer(int id, String userId)` — 加 `AND user_id = ?`

**文件**: `lib/data/local/learning_record_dao.dart`
- `deleteRecord(int id)` → `deleteRecord(int id, String userId)` — 加 `AND user_id = ?`

### 修复 3：关键 DAO 方法增加角色守卫
**新建**: `lib/core/constants/role_guard.dart`
```dart
class RoleGuard {
  static bool canManageQuestions(String role) => role == 'admin' || role == 'teacher';
  static bool canManageStudents(String role) => role == 'admin';
  static bool canScoreWorks(String role) => role == 'admin' || role == 'teacher';
  static bool canManageAssessment(String role) => role == 'admin' || role == 'teacher';
  static bool canImportData(String role) => role == 'admin';
  static bool canConfigGitee(String role) => role == 'admin' || role == 'teacher';
}
```

### 修复 4：页面级角色守卫
在以下页面的 `build()` 方法开头增加角色检查（非授权角色显示"无权限"提示页）：
- `QuestionManagePage` — 需 teacher/admin
- `TeacherWorkspacePage` — 需 teacher/admin
- `DataImportPage` — 需 admin
- `StudentManagePage` — 需 admin

### 修复 5：考核页面学生只读
**文件**: `lib/presentation/pages/assessment/assessment_page.dart`
- 保持学生可以查看考核信息（这是合理的）
- 确认编辑按钮的 `canEdit` 检查已到位（已有，line 224）

### 修复 6：首页卡片网格角色过滤
确保首页功能卡片中的"教师工作台"入口对学生不可见（已有 UI 检查，补充 widget 级守卫）

## 三、实施顺序

1. 修复密码漏洞（user_dao.dart）
2. 修复 DAO userId 校验（wrong_answer_dao + learning_record_dao）
3. 新建 RoleGuard 工具类
4. 新建 StudentRepoPage（学生仓库视图）
5. home_page.dart 角色分流
6. 页面级角色守卫
7. flutter analyze + 构建测试
