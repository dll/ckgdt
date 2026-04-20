import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/navigation_service.dart';
import '../../../data/local/notification_dao.dart';
import '../notification/notification_list_page.dart';
import '../../widgets/agent_chat_overlay.dart';
import '../login/login_page.dart';
import '../graph/knowledge_graph_page.dart';
import '../graph/favorites_page.dart';
import '../quiz/quiz_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../learning/progress_page.dart';
import '../learning/learning_hub_page.dart';
import '../learning/learning_plan_page.dart';
import '../learning/student_lab_page.dart';
import '../assessment/assessment_page.dart';
import '../survey/survey_page.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
import '../admin/class_manage_page.dart';
import '../admin/survey_manage_page.dart';
import '../admin/question_manage_page.dart';
import '../admin/data_export_page.dart';
import '../admin/teaching_manage_page.dart';
import '../admin/repo_analytics_page.dart';
import '../admin/teacher_manage_page.dart';
import '../analytics/learning_analytics_page.dart';
import '../works/works_page.dart';
import '../lab/lab_tasks_page.dart';
import '../repo/git_repo_page.dart';
import '../repo/student_repo_page.dart';
import '../achievement/achievement_page.dart';
import '../profile/student_center_page.dart';
import '../profile/teacher_workspace_page.dart';
import '../help/handbook_page.dart';
import '../skill/ai_skill_page.dart';
import '../classroom/classroom_page.dart';
import '../sync/data_sync_page.dart';
import '../feedback/feedback_manage_page.dart';
import '../practice/deep_practice_page.dart';
import '../practice/growth_curve_page.dart';
import '../cross_platform/cross_platform_hub_page.dart';
import '../settings/course_manage_page.dart';
import '../../widgets/course_generator_sheet.dart';
import '../../../data/local/course_dao.dart';
import '../../../data/models/course_model.dart';
import 'settings_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  final int initialTabIndex;

  const HomePage({super.key, this.initialTabIndex = 0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _notificationDao = NotificationDao();
  final _notificationService = NotificationService();
  final _courseDao = CourseDao();
  late int _selectedIndex;
  int _unreadCount = 0;
  Timer? _notificationTimer;
  CourseModel? _activeCourse;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _refreshUnreadCount();
    _loadActiveCourse();
    // 每30秒轮询未读通知数
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnreadCount(),
    );
    // 注册全局导航服务回调
    NavigationService.instance.onSwitchTab = (index) {
      if (mounted) {
        setState(() => _selectedIndex = index);
      }
    };
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    NavigationService.instance.dispose();
    super.dispose();
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final userId = _authService.getCurrentUserId();
      if (userId == null) return;
      // 顺便检查自动提醒
      await _notificationService.checkAndCreateReminders();
      final count = await _notificationDao.getUnreadCount(userId);
      if (mounted && count != _unreadCount) {
        setState(() => _unreadCount = count);
      }
    } catch (_) {}
  }

  Future<void> _loadActiveCourse() async {
    try {
      final course = await _courseDao.getActiveCourse();
      if (mounted && course != null) {
        setState(() => _activeCourse = course);
      }
    } catch (_) {}
  }

  /// 当前平台显示名称：基于激活课程动态生成
  String get _platformTitle {
    final name = _activeCourse?.name ?? '移动应用开发';
    return '$name知识图谱';
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isAdmin = _authService.isAdmin;
    final isTeacher = _authService.isTeacher;
    final isTeacherOrAdmin = isTeacher || isAdmin;

    // ── 构建角色对应的 Tab 列表 ────────────────────────────────────
    final destinations = <NavigationDestination>[];
    final bodyMap = <int, Widget Function()>{};

    // 0: 首页（所有角色）
    destinations.add(const NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: '首页',
    ));
    bodyMap[0] = () => _buildHome();

    // 1: 图谱（所有角色）
    destinations.add(const NavigationDestination(
      icon: Icon(Icons.account_tree_outlined),
      selectedIcon: Icon(Icons.account_tree),
      label: '图谱',
    ));
    bodyMap[1] = () => const KnowledgeGraphPage();

    if (isTeacherOrAdmin) {
      // ── 教师/管理员导航 ──────────────────────────────────────────
      // 2: 教学（教师/管理员用"教学"替代学生的"学习"）
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: '教学',
      ));
      bodyMap[destinations.length - 1] = () => const LearningHubPage();

      // 3: 课堂
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.cast_for_education_outlined),
        selectedIcon: Icon(Icons.cast_for_education),
        label: '课堂',
      ));
      bodyMap[destinations.length - 1] = () => const ClassroomPage();

      // 4: 实验
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.science_outlined),
        selectedIcon: Icon(Icons.science),
        label: '实验',
      ));
      bodyMap[destinations.length - 1] = () => const LabTasksPage();

      // 5: 考核
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.assessment_outlined),
        selectedIcon: Icon(Icons.assessment),
        label: '考核',
      ));
      bodyMap[destinations.length - 1] = () => const AssessmentPage();

      // 6: 作品
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.workspace_premium_outlined),
        selectedIcon: Icon(Icons.workspace_premium),
        label: '作品',
      ));
      bodyMap[destinations.length - 1] = () => const WorksPage();

      // 7: 达成
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: '达成',
      ));
      bodyMap[destinations.length - 1] = () => const AchievementPage();

      // 8: 管理（仅管理员）
      if (isAdmin) {
        destinations.add(const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: '管理',
        ));
        bodyMap[destinations.length - 1] = () => const _AdminToolsPage();
      }
    } else {
      // ── 学生导航 ────────────────────────────────────────────────
      // 2: 学习
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: '学习',
      ));
      bodyMap[2] = () => const LearningHubPage();

      // 3: 实验
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.science_outlined),
        selectedIcon: Icon(Icons.science),
        label: '实验',
      ));
      bodyMap[3] = () => const StudentLabPage();

      // 4: 考核
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.assessment_outlined),
        selectedIcon: Icon(Icons.assessment),
        label: '考核',
      ));
      bodyMap[4] = () => const AssessmentPage();

      // 5: 作品
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.workspace_premium_outlined),
        selectedIcon: Icon(Icons.workspace_premium),
        label: '作品',
      ));
      bodyMap[5] = () => const WorksPage();
    }

    // 确保 _selectedIndex 不越界
    if (_selectedIndex >= destinations.length) {
      _selectedIndex = 0;
    }

    // 注册 Tab 关键词映射，供语音导航 / 智能体使用
    final tabMapping = <String, int>{};
    for (var i = 0; i < destinations.length; i++) {
      tabMapping[destinations[i].label] = i;
    }
    NavigationService.instance.registerTabMapping(tabMapping);

    return Scaffold(
      appBar: AppBar(
        title: Text(_platformTitle),

        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              );
            },
          ),
          // 通知铃铛图标（带未读数 Badge）
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(fontSize: 10),
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: '通知',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationListPage()),
              );
              // 返回后刷新未读数
              _refreshUnreadCount();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.person),
            tooltip: '显示菜单',
            onSelected: (value) async {
              if (value == 'logout') {
                final navigator = Navigator.of(context);
                await _authService.logout();
                if (mounted) {
                  navigator.pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                }
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              } else if (value == 'progress') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProgressPage()),
                );
              } else if (value == 'learning_center') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const StudentCenterPage()),
                );
              } else if (value == 'teacher_workspace') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherWorkspacePage()),
                );
              } else if (value == 'handbook') {
                final handRole = isAdmin
                    ? 'admin'
                    : isTeacher
                        ? 'teacher'
                        : 'student';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => HandbookPage(role: handRole)),
                );
              } else if (value == 'change_password') {
                _showChangePasswordDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user?.realName ?? user?.userId ?? '用户'),
                  subtitle: Text(user?.role == 'admin' ? '管理员' :
                                 user?.role == 'teacher' ? '教师' : '学生'),
                ),
              ),
              const PopupMenuDivider(),
              // 学生：我的学习中心
              if (!isAdmin && !isTeacher)
                const PopupMenuItem(
                  value: 'learning_center',
                  child: ListTile(
                    leading: Icon(Icons.school, color: Colors.blue),
                    title: Text('学习中心'),
                  ),
                ),
              // 教师/管理员：工作台
              if (isTeacher || isAdmin)
                PopupMenuItem(
                  value: 'teacher_workspace',
                  child: ListTile(
                    leading: const Icon(Icons.dashboard, color: Colors.indigo),
                    title: Text(isAdmin ? '管理员工作台' : '教师工作台'),
                  ),
                ),
              const PopupMenuItem(
                value: 'progress',
                child: ListTile(
                  leading: Icon(Icons.trending_up, color: Colors.green),
                  title: Text('学习进度'),
                ),
              ),
              const PopupMenuItem(
                value: 'change_password',
                child: ListTile(
                  leading: Icon(Icons.lock_outline, color: Colors.orange),
                  title: Text('修改密码'),
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('系统设置'),
                ),
              ),
              PopupMenuItem(
                value: 'handbook',
                child: ListTile(
                  leading: Icon(Icons.menu_book,
                      color: isAdmin
                          ? Colors.deepPurple
                          : isTeacher
                              ? Colors.indigo
                              : Colors.blue),
                  title: Text(isAdmin
                      ? '管理员手册'
                      : isTeacher
                          ? '教师手册'
                          : '学生手册'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('退出登录'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: bodyMap[_selectedIndex]?.call() ?? _buildHome(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: destinations,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }

  Widget _buildHome() {
    final user = _authService.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 欢迎卡片
          Card(
            elevation: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: AppGradientTheme.of(context).linearGradient,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '欢迎回来，${user?.realName ?? user?.userId ?? '同学'}！',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user?.role == 'admin' ? '管理员账号' :
                    user?.role == 'teacher' ? '教师账号' : '学生账号',
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 学习流程导航条（图谱→路径→学习→测验）────────────────────
          _buildLearningFlowBar(),
          const SizedBox(height: 16),

          // 功能菜单
          Text(
            _authService.isAdmin ? '管理功能' :
            _authService.isTeacher ? '教学功能' : '学习功能',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 900
                  ? 5
                  : constraints.maxWidth > 600
                      ? 4
                      : 3;

              final isTeacher = _authService.isTeacher;
              final isAdmin = _authService.isAdmin;
              final isTeacherOrAdmin = isTeacher || isAdmin;

              final menuItems = <Widget>[
                // ── 核心功能卡片（所有角色）──────────────────────────
                _buildMenuCard(
                  icon: Icons.account_tree,
                  title: '知识图谱',
                  color: Colors.blue,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                _buildMenuCard(
                  icon: Icons.route,
                  title: '学习路径',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LearningPlanPage())),
                ),
                _buildMenuCard(
                  icon: Icons.quiz,
                  title: '章节测验',
                  color: Colors.orange,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const QuizPage())),
                ),
                _buildMenuCard(
                  icon: Icons.source,
                  title: 'Git仓库',
                  color: Colors.blueGrey,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) =>
                        isTeacherOrAdmin ? const GitRepoPage() : const StudentRepoPage())),
                ),
                _buildMenuCard(
                  icon: Icons.auto_awesome,
                  title: 'AI 技能',
                  color: Colors.deepPurple[400]!,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SkillsHubPage())),
                ),
                _buildMenuCard(
                  icon: Icons.smart_toy,
                  title: '多智能体',
                  color: Colors.indigo[400]!,
                  onTap: () => AgentChatOverlay.show(context),
                ),
                _buildMenuCard(
                  icon: Icons.biotech,
                  title: '深度实践',
                  color: Colors.cyan[700]!,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DeepPracticePage())),
                ),
                _buildMenuCard(
                  icon: Icons.show_chart,
                  title: '成长曲线',
                  color: Colors.purple[400]!,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GrowthCurvePage())),
                ),
                _buildMenuCard(
                  icon: Icons.sync,
                  title: '数据同步',
                  color: Colors.teal[600]!,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DataSyncPage())),
                ),
                _buildMenuCard(
                  icon: Icons.devices,
                  title: '三端互通',
                  color: Colors.deepPurple,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CrossPlatformHubPage())),
                ),

                // ── 学生专属功能 ──────────────────────────────────
                if (!isTeacherOrAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.trending_up,
                    title: '学习进度',
                    color: Colors.green,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProgressPage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.error,
                    title: '错题本',
                    color: Colors.red[400]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const WrongAnswersPage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.star,
                    title: '我的收藏',
                    color: Colors.amber,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FavoritesPage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.poll,
                    title: '问卷调查',
                    color: Colors.teal[400]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SurveyPage())),
                  ),
                ],

                // ── 教师/管理员功能 ──────────────────────────────
                if (isTeacherOrAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.bar_chart,
                    title: '成绩统计',
                    color: Colors.green,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LearningAnalyticsPage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.class_,
                    title: '班级管理',
                    color: Colors.cyan[700]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ClassManagePage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.school,
                    title: '教学管理',
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TeachingManagePage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.quiz_outlined,
                    title: '题库管理',
                    color: Colors.orange[700]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const QuestionManagePage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.poll,
                    title: '问卷管理',
                    color: Colors.pink,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SurveyManagePage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.feedback,
                    title: '反馈管理',
                    color: Colors.amber[700]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const FeedbackManagePage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.auto_awesome,
                    title: '一键生课',
                    color: Colors.deepPurple[300]!,
                    onTap: () async {
                      final result = await showModalBottomSheet<CourseModel>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => const CourseGeneratorSheet(),
                      );
                      if (result != null) {
                        // 自动激活新课程并刷新平台标题
                        await _courseDao.setActiveCourse(result.id);
                        _loadActiveCourse();
                      }
                    },
                  ),
                  _buildMenuCard(
                    icon: Icons.school_outlined,
                    title: '课程管理',
                    color: Colors.teal[400]!,
                    onTap: () async {
                      await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CourseManagePage()));
                      // 返回后刷新平台标题（可能切换了课程）
                      _loadActiveCourse();
                    },
                  ),
                ],

                // ── 管理员专属功能 ──────────────────────────────
                if (isAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.people,
                    title: '学生管理',
                    color: Colors.brown,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const StudentManagePage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.upload,
                    title: '数据导入',
                    color: Colors.indigo[400]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DataImportPage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.download,
                    title: '数据导出',
                    color: Colors.indigo[600]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DataExportPage())),
                  ),
                  _buildMenuCard(
                    icon: Icons.analytics,
                    title: '仓库分析',
                    color: Colors.blueGrey[700]!,
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RepoAnalyticsPage())),
                  ),
                ],
              ];

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                childAspectRatio: 1.1,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: menuItems,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 学习流程导航条: 图谱 → 路径 → 学习 → 测验
  Widget _buildLearningFlowBar() {
    final primary = Theme.of(context).colorScheme.primary;
    final isTeacherOrAdmin = _authService.isTeacher || _authService.isAdmin;

    final steps = [
      _FlowStep(Icons.account_tree, '图谱', () => setState(() => _selectedIndex = 1)),
      _FlowStep(Icons.route, '路径', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LearningPlanPage()))),
      _FlowStep(Icons.menu_book, isTeacherOrAdmin ? '教学' : '学习',
          () => setState(() => _selectedIndex = 2)),
      _FlowStep(Icons.biotech, '实践', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const DeepPracticePage()))),
      _FlowStep(Icons.quiz, '测验', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const QuizPage()))),
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: steps[i].onTap,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(steps[i].icon, color: primary, size: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(steps[i].label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primary)),
                    ],
                  ),
                ),
              ),
              if (i < steps.length - 1)
                Icon(Icons.arrow_forward_ios, size: 14, color: primary.withValues(alpha: 0.4)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30, color: color),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 修改密码对话框 ──────────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final user = _authService.currentUser;
    if (user == null) return;

    final currentPwdCtrl = TextEditingController();
    final newPwdCtrl = TextEditingController();
    final confirmPwdCtrl = TextEditingController();
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFF667eea)),
              SizedBox(width: 8),
              Text('修改密码', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '当前密码',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码（至少6位）',
                    prefixIcon: Icon(Icons.lock_open),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认新密码',
                    prefixIcon: Icon(Icons.lock_open),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                // 验证
                if (currentPwdCtrl.text.isEmpty || newPwdCtrl.text.isEmpty) {
                  setDialogState(() => errorMsg = '请填写所有字段');
                  return;
                }
                if (newPwdCtrl.text.length < 6) {
                  setDialogState(() => errorMsg = '新密码至少6位');
                  return;
                }
                if (newPwdCtrl.text != confirmPwdCtrl.text) {
                  setDialogState(() => errorMsg = '两次输入的密码不一致');
                  return;
                }

                // 验证当前密码
                final success = await _authService.changePassword(
                  user.userId,
                  currentPwdCtrl.text,
                  newPwdCtrl.text,
                );
                if (success) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('密码修改成功！下次登录请使用新密码')),
                    );
                  }
                } else {
                  setDialogState(() => errorMsg = '当前密码不正确');
                }
              },
              child: const Text('确认修改'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowStep {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _FlowStep(this.icon, this.label, this.onTap);
}

/// 管理员工具面板 — 以网格方式集中管理功能入口
class _AdminToolsPage extends StatelessWidget {
  const _AdminToolsPage();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final tools = <_AdminTool>[
      _AdminTool(Icons.people, '学生管理', Colors.brown,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentManagePage()))),
      _AdminTool(Icons.person_add, '教师管理', Colors.indigo,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherManagePage()))),
      _AdminTool(Icons.class_, '班级管理', Colors.cyan[700]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassManagePage()))),
      _AdminTool(Icons.school, '教学管理', Colors.deepOrange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeachingManagePage()))),
      _AdminTool(Icons.quiz_outlined, '题库管理', Colors.orange[700]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionManagePage()))),
      _AdminTool(Icons.poll, '问卷管理', Colors.pink,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SurveyManagePage()))),
      _AdminTool(Icons.feedback, '反馈管理', Colors.amber[700]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackManagePage()))),
      _AdminTool(Icons.upload, '数据导入', Colors.indigo[400]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataImportPage()))),
      _AdminTool(Icons.download, '数据导出', Colors.indigo[600]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataExportPage()))),
      _AdminTool(Icons.analytics, '仓库分析', Colors.blueGrey[700]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RepoAnalyticsPage()))),
      _AdminTool(Icons.sync, '数据同步', Colors.teal[600]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataSyncPage()))),
      _AdminTool(Icons.devices, '三端互通', Colors.deepPurple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CrossPlatformHubPage()))),
      _AdminTool(Icons.settings, '系统设置', Colors.grey[700]!,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
    ];

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 管理员头部
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.7)],
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('系统管理', style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('管理系统各项功能和数据', style: TextStyle(
                          color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth > 900
                    ? 5
                    : constraints.maxWidth > 600
                        ? 4
                        : 3;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cols,
                  childAspectRatio: 1.1,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: tools.map((t) => Card(
                    elevation: 1,
                    child: InkWell(
                      onTap: t.onTap,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(t.icon, size: 30, color: t.color),
                            const SizedBox(height: 6),
                            Text(t.title,
                                style: TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w500, color: t.color),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTool {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  const _AdminTool(this.icon, this.title, this.color, this.onTap);
}
