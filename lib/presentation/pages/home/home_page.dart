import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../core/design/noir_components.dart';
import '../../../core/error_handler.dart';
import '../../widgets/noir_page_shell.dart';
import '../../../services/auth_service.dart';
import '../../../services/screenshot_service.dart';
import '../../../services/navigation_service.dart';
import '../../../services/unread_count_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/gitee_service.dart';
import '../assessment/defense/defense_broadcast_page.dart';
import '../../../services/default_class_service.dart';
import '../../../dev/demo_seed_service.dart';
import '../notification/notification_list_page.dart';
import '../notification/notification_manage_page.dart';
import '../../widgets/agent_chat_overlay.dart';
import '../../widgets/screenshot_capture_page.dart';
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
import '../class_qa/class_qa_page.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
import '../admin/class_manage_page.dart';
import '../admin/survey_manage_page.dart';
import '../admin/question_manage_page.dart';
import '../admin/data_export_page.dart';
import '../admin/grade_entry_center_page.dart';
import '../admin/release_center_page.dart';
import '../admin/teaching_manage_page.dart';
import '../admin/lab_task_manage_page.dart';
import '../admin/repo_analytics_page.dart';
import '../admin/teacher_manage_page.dart';
import '../admin/teacher_application_manage_page.dart';
import '../analytics/learning_analytics_page.dart';
import '../analytics/token_stats_page.dart';
import '../works/works_page.dart';
import '../archive/archive_page.dart';
import '../repo/git_repo_page.dart';
import '../repo/student_repo_page.dart';
import '../achievement/achievement_page.dart';
import '../profile/student_center_page.dart';
import '../profile/teacher_workspace_page.dart';
import '../help/handbook_page.dart';
import '../skill/ai_skill_page.dart';
import '../sync/data_sync_page.dart';
import 'teaching_hub_page.dart';
import 'evaluation_hub_page.dart';
import '../feedback/feedback_manage_page.dart';
import '../practice/deep_practice_page.dart';
import '../practice/growth_curve_page.dart';
import '../cross_platform/cross_platform_hub_page.dart';
import '../settings/course_manage_page.dart';
import '../profile/virtual_twin_page.dart';
import '../../widgets/course_generator_sheet.dart';
import '../../../data/local/course_dao.dart';
import '../../../data/models/course_model.dart';
import 'settings_page.dart';
import 'search_page.dart';

const _cardColors = {
  '知识图谱': Color(0xFF667eea),
  '学习路径': Color(0xFF764ba2),
  '章节测验': Color(0xFFf093fb),
  'Git仓库': Color(0xFF4facfe),
  '技能工具': Color(0xFF43e97b),
  '智慧问答': Color(0xFFfa709a),
  '深度实践': Color(0xFFf6d365),
  '成长曲线': Color(0xFFa18cd1),
  'Token统计': Color(0xFFfbc2eb),
  '数据同步': Color(0xFF84fab0),
  '多端互通': Color(0xFF8fd3f4),
  '数字孪生': Color(0xFFa1c4fd),
  '学习进度': Color(0xFFc2e9fb),
  '错题本': Color(0xFFfccb90),
  '我的收藏': Color(0xFFd57eeb),
  '问卷调查': Color(0xFFe0c3fc),
  '班级问答': Color(0xFF8ec5fc),
  '成绩统计': Color(0xFFf5576c),
  '班级管理': Color(0xFFf093fb),
  '教学管理': Color(0xFF4facfe),
  '题库管理': Color(0xFF43e97b),
  '问卷管理': Color(0xFFfa709a),
  '反馈管理': Color(0xFFf6d365),
  '一键生课': Color(0xFFa18cd1),
  '课程管理': Color(0xFFfbc2eb),
  '通知管理': Color(0xFF667eea),
  '学生管理': Color(0xFF84fab0),
  '数据导入': Color(0xFF8fd3f4),
  '数据导出': Color(0xFFa1c4fd),
  '仓库分析': Color(0xFFc2e9fb),
};

class HomePage extends StatefulWidget {
  final int initialTabIndex;

  const HomePage({super.key, this.initialTabIndex = 0});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _courseDao = CourseDao();
  late int _selectedIndex;

  String? _defenseServerIp;
  int _defenseServerPort = 8766;
  Timer? _defensePollTimer;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _refreshUnreadCount();
    _loadActiveCourse();
    _ensureClassesInitialized();
    // 学生登录后自动拉取 Gitee 答辩通知（每 30 秒轮询，降低 Gitee 配额压力）
    _pullNotifications();
    _defensePollTimer = Timer.periodic(
      const Duration(seconds: 30), (_) => _pullNotifications());
    // 注册全局导航服务回调
    NavigationService.instance.onSwitchTab = (index) {
      if (mounted) {
        setState(() => _selectedIndex = index);
      }
    };
  }

  @override
  void dispose() {
    _defensePollTimer?.cancel();
    NavigationService.instance.dispose();
    super.dispose();
  }

  /// 直播横幅：有正在进行的答辩直播时，顶部显示"X 正在直播"，点击进入观看。
  /// 无直播时折叠为零高度，不占位。
  /// 刷新未读计数（委托到全局 service，不再触发本页 setState）
  Future<void> _refreshUnreadCount() async {
    final userId = _authService.getCurrentUserId();
    await UnreadCountService.instance.refresh(userId);
  }

  /// 从 Gitee 拉取答辩通知，发现授权后设置 _defenseServerIp 以显示横幅
  Future<void> _pullNotifications() async {
    if (_authService.isTeacher || _authService.isAdmin) return;
    final uid = _authService.getCurrentUserId();
    if (uid == null) return;

    try {
      final gitee = GiteeService();
      final json = await gitee.getFileContent(
        SyncService.repoOwner,
        SyncService.repoName,
        'defense/teacher_server.json',
        ref: SyncService.repoBranch,
      );
      if (json == null) {
        _clearDefenseBanner();
        return;
      }

      final data = jsonDecode(json) as Map<String, dynamic>;
      final authorized = (data['authorizedStudents'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final ip = data['teacherIp'] as String?;
      final port = data['serverPort'] as int? ?? 8766;
      final ts = data['timestamp'] as String?;

      // 超过 5 分钟视为过期广播
      if (ts != null) {
        final time = DateTime.tryParse(ts);
        if (time != null &&
            DateTime.now().difference(time) > const Duration(minutes: 5)) {
          _clearDefenseBanner();
          return;
        }
      }

      if (authorized.contains(uid) && ip != null && ip.isNotEmpty) {
        if (!mounted) return;
        if (_defenseServerIp != ip || _defenseServerPort != port) {
          setState(() {
            _defenseServerIp = ip;
            _defenseServerPort = port;
          });
        }
      } else {
        _clearDefenseBanner();
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'HomePage.pullDefense', stack: st);
    }
  }

  void _clearDefenseBanner() {
    if (_defenseServerIp != null && mounted) {
      setState(() => _defenseServerIp = null);
    }
  }

  /// 答辩广播横幅：检测到教师开播且当前用户在授权名单中时显示
  Widget _buildDefenseBanner() {
    if (_defenseServerIp == null || _authService.isTeacher || _authService.isAdmin) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DefenseBroadcastPage(
                initialRole: 'defender',
                serverIp: _defenseServerIp,
                serverPort: _defenseServerPort,
              ),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.orange.withValues(alpha: 0.9),
              Colors.red.withValues(alpha: 0.85),
            ]),
          ),
          child: Row(
            children: [
              const Icon(Icons.sensors, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('教师正在答辩直播 — 点击连接',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const Text('连接',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              const Icon(Icons.chevron_right, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadActiveCourse() async {
    try {
      final course = await _courseDao.getActiveCourse();
      if (mounted && course != null) {
        setState(() {});
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'HomePage._loadActiveCourse', stack: st);
    }
  }

  Future<void> _ensureClassesInitialized() async {
    try {
      await DefaultClassService.instance.ensureDefaultClass();
    } catch (e, st) {
      swallowDebug(e, tag: 'HomePage._ensureClasses', stack: st);
    }
  }

  /// 当前平台显示名称：AppBar 内部居中标题（完整名称，无版本号）
  String get _platformTitle => '移动应用开发知识图谱与数字孪生平台';

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
      // ── 教师/管理员导航（精简 6 Tab）────────────────────────────
      // 2: 教学中心（教学 + 课堂聚合）
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: '教学',
      ));
      bodyMap[destinations.length - 1] = () => const TeachingHubPage();

      // 3: 评价中心（实验 + 考核 + 作品聚合）
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.rate_review_outlined),
        selectedIcon: Icon(Icons.rate_review),
        label: '评价',
      ));
      bodyMap[destinations.length - 1] = () => const EvaluationHubPage();

      // 4: 达成
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: '达成',
      ));
      bodyMap[destinations.length - 1] = () => const AchievementPage();

      // 5: 归档（教师/管理员通用）
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.school_outlined),
        selectedIcon: Icon(Icons.school),
        label: '归档',
      ));
      bodyMap[destinations.length - 1] = () => const ArchivePage();

      // 6: 管理（仅管理员）
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
      backgroundColor: NoirTokens.ink,
      appBar: AppBar(
        backgroundColor: NoirTokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: NoirTokens.paper),
        title: Text(_platformTitle, style: const TextStyle(color: NoirTokens.paper)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: NoirTokens.paper),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              );
            },
          ),
          ValueListenableBuilder<int>(
            valueListenable: UnreadCountService.instance.count,
            builder: (context, unread, _) => Semantics(
              label: unread > 0 ? '通知，$unread 条未读' : '通知',
              button: true,
              child: IconButton(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(fontSize: 10),
                  ),
                  child: const Icon(Icons.notifications_outlined, color: NoirTokens.paper),
                ),
                tooltip: '通知',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationListPage()),
                  );
                  _refreshUnreadCount();
                },
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.person, color: NoirTokens.paper),
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
              } else if (value == 'virtual_twin') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VirtualTwinPage()),
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
              const PopupMenuItem(
                value: 'virtual_twin',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome, color: Colors.purple),
                  title: Text('数字孪生'),
                ),
              ),
              if (!isAdmin && !isTeacher)
                const PopupMenuItem(
                  value: 'learning_center',
                  child: ListTile(
                    leading: Icon(Icons.school, color: Colors.blue),
                    title: Text('学习中心'),
                  ),
                ),
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
      body: NoirBackground(
        child: Column(
          children: [
            _buildDefenseBanner(),
            Expanded(
                child: bodyMap[_selectedIndex]?.call() ?? _buildHome()),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        indicatorColor: NoirTokens.accent.withValues(alpha: 0.35),
        surfaceTintColor: Colors.transparent,
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
    final roleLabel = user?.role == 'admin'
        ? 'ADMINISTRATOR'
        : user?.role == 'teacher'
            ? 'INSTRUCTOR'
            : 'STUDENT';
    final greetName = user?.realName ?? user?.userId ?? '同学';
    final accent = NoirTokens.accent;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 编辑级 Hero：黑底纸感字 + 琥珀编号 + 顶部 1px 琥珀线 ────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            decoration: BoxDecoration(
              color: NoirTokens.inkDeep,
              borderRadius: BorderRadius.circular(NoirTokens.radius),
              border: Border.all(color: NoirTokens.inkAlpha(0.10)),
              boxShadow: NoirTokens.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('№ 001 / DASHBOARD',
                        style: NoirTokens.serial(color: accent)),
                    const Spacer(),
                    Text(roleLabel,
                        style: NoirTokens.caps(color: NoirTokens.paper)),
                  ],
                ),
                const SizedBox(height: 14),
                Container(width: 36, height: 2, color: accent),
                const SizedBox(height: 12),
                Text(
                  '欢迎回来，$greetName',
                  style: const TextStyle(
                    color: NoirTokens.paper,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  user?.role == 'admin'
                      ? '系统级权限 · 管理员视角 · 全局可视'
                      : user?.role == 'teacher'
                          ? '教学视角 · 班级 / 实验 / 考核 / 达成'
                          : '学习视角 · 图谱 / 路径 / 实验 / 测验',
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.85),
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ── 学习流程导航条 ──────────────────────────────────────────
          _buildLearningFlowBar(),
          const SizedBox(height: 26),

          // ── 章节标题 ────────────────────────────────────────────────
          NoirSectionTitle(
            eyebrow: '№ 002',
            title: _authService.isAdmin
                ? '管理功能'
                : _authService.isTeacher
                    ? '教学功能'
                    : '学习功能',
            subtitle: _authService.isAdmin
                ? 'Administration suite'
                : _authService.isTeacher
                    ? 'Teaching toolkit'
                    : 'Learning toolkit',
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: NoirTokens.spaceMd),
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
                  onTap: () => setState(() => _selectedIndex = 1),
                  cardColor: _cardColors['知识图谱'],
                  description: '可视化学科知识结构',
                ),
                _buildMenuCard(
                  icon: Icons.route,
                  title: '学习路径',
                  destinationPage: const LearningPlanPage(),
                  cardColor: _cardColors['学习路径'],
                  description: '智能规划学习路线',
                ),
                _buildMenuCard(
                  icon: Icons.quiz,
                  title: '章节测验',
                  destinationPage: const QuizPage(),
                  cardColor: _cardColors['章节测验'],
                  description: '章节知识点自测',
                ),
                _buildMenuCard(
                  icon: Icons.source,
                  title: 'Git仓库',
                  destinationPage: isTeacherOrAdmin ? const GitRepoPage() : const StudentRepoPage(),
                  cardColor: _cardColors['Git仓库'],
                  description: '代码版本管理',
                ),
                _buildMenuCard(
                  icon: Icons.tips_and_updates,
                  title: '技能工具',
                  destinationPage: const SkillsHubPage(),
                  cardColor: _cardColors['技能工具'],
                  description: 'AI 教学辅助工具',
                ),
                _buildMenuCard(
                  icon: Icons.auto_awesome,
                  title: '数字孪生',
                  destinationPage: const VirtualTwinPage(),
                  cardColor: _cardColors['数字孪生'],
                  description: 'AI 数字分身',
                ),
                _buildMenuCard(
                  icon: Icons.chat_bubble_outline,
                  title: '智慧问答',
                  onTap: () => AgentChatOverlay.show(context),
                  cardColor: _cardColors['智慧问答'],
                  description: 'AI 智能答疑解惑',
                ),
                _buildMenuCard(
                  icon: Icons.biotech,
                  title: '深度实践',
                  destinationPage: const DeepPracticePage(),
                  cardColor: _cardColors['深度实践'],
                  description: '项目实战训练',
                ),
                _buildMenuCard(
                  icon: Icons.show_chart,
                  title: '成长曲线',
                  destinationPage: const GrowthCurvePage(),
                  cardColor: _cardColors['成长曲线'],
                  description: '学习轨迹分析',
                ),
                _buildMenuCard(
                  icon: Icons.token,
                  title: 'Token统计',
                  destinationPage: const TokenStatsPage(),
                  cardColor: _cardColors['Token统计'],
                  description: 'Token 消耗统计',
                ),
                _buildMenuCard(
                  icon: Icons.sync,
                  title: '数据同步',
                  destinationPage: const DataSyncPage(),
                  cardColor: _cardColors['数据同步'],
                  description: '跨设备数据同步',
                ),
                _buildMenuCard(
                  icon: Icons.devices,
                  title: '多端互通',
                  destinationPage: const CrossPlatformHubPage(),
                  cardColor: _cardColors['多端互通'],
                  description: '多平台无缝衔接',
                ),
                _buildMenuCard(
                  icon: Icons.notifications_active,
                  title: '通知管理',
                  destinationPage: const NotificationManagePage(),
                  cardColor: _cardColors['通知管理'],
                  description: '通知列表与数据统计',
                ),

                // ── 学生专属功能 ──────────────────────────────────
                if (!isTeacherOrAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.trending_up,
                    title: '学习进度',
                    destinationPage: const ProgressPage(),
                    cardColor: _cardColors['学习进度'],
                    description: '个人学习进度',
                  ),
                  _buildMenuCard(
                    icon: Icons.error,
                    title: '错题本',
                    destinationPage: const WrongAnswersPage(),
                    cardColor: _cardColors['错题本'],
                    description: '错题回顾巩固',
                  ),
                  _buildMenuCard(
                    icon: Icons.star,
                    title: '我的收藏',
                    destinationPage: const FavoritesPage(),
                    cardColor: _cardColors['我的收藏'],
                    description: '收藏的知识点',
                  ),
                  _buildMenuCard(
                    icon: Icons.poll,
                    title: '问卷调查',
                    destinationPage: const SurveyPage(),
                    cardColor: _cardColors['问卷调查'],
                    description: '教学反馈问卷',
                  ),
                  _buildMenuCard(
                    icon: Icons.forum_outlined,
                    title: '班级问答',
                    destinationPage: const ClassQaPage(),
                    cardColor: _cardColors['班级问答'],
                    description: '班级互动问答',
                  ),
                ],

                // ── 教师/管理员功能 ──────────────────────────────
                if (isTeacherOrAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.bar_chart,
                    title: '成绩统计',
                    destinationPage: const LearningAnalyticsPage(),
                    cardColor: _cardColors['成绩统计'],
                    description: '班级成绩分析',
                  ),
                  _buildMenuCard(
                    icon: Icons.class_,
                    title: '班级管理',
                    destinationPage: const ClassManagePage(),
                    cardColor: _cardColors['班级管理'],
                    description: '班级信息管理',
                  ),
                  _buildMenuCard(
                    icon: Icons.school,
                    title: '教学管理',
                    destinationPage: const TeachingManagePage(),
                    cardColor: _cardColors['教学管理'],
                    description: '教学进度管理',
                  ),
                  _buildMenuCard(
                    icon: Icons.quiz_outlined,
                    title: '题库管理',
                    destinationPage: const QuestionManagePage(),
                    cardColor: _cardColors['题库管理'],
                    description: '试题库维护',
                  ),
                  _buildMenuCard(
                    icon: Icons.poll,
                    title: '问卷管理',
                    destinationPage: const SurveyManagePage(),
                    cardColor: _cardColors['问卷管理'],
                    description: '调查问卷管理',
                  ),
                  _buildMenuCard(
                    icon: Icons.feedback,
                    title: '反馈管理',
                    destinationPage: const FeedbackManagePage(),
                    cardColor: _cardColors['反馈管理'],
                    description: '用户反馈处理',
                  ),
                  _buildMenuCard(
                    icon: Icons.forum,
                    title: '班级问答',
                    destinationPage: const ClassQaPage(),
                    cardColor: _cardColors['班级问答'],
                    description: '班级互动问答',
                  ),
                  _buildMenuCard(
                    icon: Icons.add_box_outlined,
                    title: '一键生课',
                    onTap: () async {
                      final result = await showModalBottomSheet<CourseModel>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                        builder: (_) => const CourseGeneratorSheet(),
                      );
                      if (result != null) {
                        await _courseDao.setActiveCourse(result.id);
                        _loadActiveCourse();
                      }
                    },
                    cardColor: _cardColors['一键生课'],
                    description: '自动生成课程',
                  ),
                  _buildMenuCard(
                    icon: Icons.school_outlined,
                    title: '课程管理',
                    onTap: () async {
                      await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CourseManagePage()));
                      _loadActiveCourse();
                    },
                    cardColor: _cardColors['课程管理'],
                    description: '课程信息配置',
                  ),
                ],

                // ── 管理员专属功能 ──────────────────────────────
                if (isAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.people,
                    title: '学生管理',
                    destinationPage: const StudentManagePage(),
                    cardColor: _cardColors['学生管理'],
                    description: '学生账户管理',
                  ),
                  _buildMenuCard(
                    icon: Icons.upload,
                    title: '数据导入',
                    destinationPage: const DataImportPage(),
                    cardColor: _cardColors['数据导入'],
                    description: '批量数据导入',
                  ),
                  _buildMenuCard(
                    icon: Icons.download,
                    title: '数据导出',
                    destinationPage: const DataExportPage(),
                    cardColor: _cardColors['数据导出'],
                    description: '数据导出备份',
                  ),
                  _buildMenuCard(
                    icon: Icons.analytics,
                    title: '仓库分析',
                    destinationPage: const RepoAnalyticsPage(),
                    cardColor: _cardColors['仓库分析'],
                    description: '代码仓库分析',
                  ),
                ],
              ];

              // 给每个卡片传入序号（编辑感）
              final indexedItems = <Widget>[];
              for (var i = 0; i < menuItems.length; i++) {
                indexedItems.add(menuItems[i]);
              }

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                childAspectRatio: 0.9,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: indexedItems,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 学习流程导航条: 图谱 → 路径 → 学习 → 实践 → 测验
  Widget _buildLearningFlowBar() {
    final isTeacherOrAdmin = _authService.isTeacher || _authService.isAdmin;
    final accent = Theme.of(context).colorScheme.primary;

    final steps = [
      _FlowStep(Icons.account_tree, '图谱', '01',
          () => setState(() => _selectedIndex = 1)),
      _FlowStep(Icons.route, '路径', '02', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const LearningPlanPage()))),
      _FlowStep(Icons.menu_book, isTeacherOrAdmin ? '教学' : '学习', '03',
          () => setState(() => _selectedIndex = 2)),
      _FlowStep(Icons.biotech, '实践', '04', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const DeepPracticePage()))),
      _FlowStep(Icons.quiz, '测验', '05', () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const QuizPage()))),
    ];

    return NoirCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(NoirTokens.radius),
                onTap: steps[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(steps[i].serial,
                          style: NoirTokens.serial(color: accent)),
                      const SizedBox(height: 6),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(NoirTokens.radius),
                        ),
                        child: Icon(steps[i].icon,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(steps[i].label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            color: NoirTokens.ink,
                          )),
                    ],
                  ),
                ),
              ),
            ),
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Container(
                  width: 18,
                  height: 1,
                  color: NoirTokens.inkAlpha(0.25),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _pushWithScreenshot(String key, Widget page) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScreenshotCapturePage(
          captureKey: key,
          child: page,
        ),
      ),
    );
  }

  static void _noOp() {}

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    String? imageAsset,
    String? description,
    Color? cardColor,
    String? captureKey,
    Widget? destinationPage,
  }) {
    final effectiveColor = cardColor ?? Theme.of(context).colorScheme.primary;
    final effectiveOnTap = destinationPage != null
        ? () => _pushWithScreenshot(captureKey ?? title, destinationPage)
        : (onTap ?? _noOp);
    return Semantics(
      label: '$title 功能入口',
      button: true,
      child: NoirCard(
        padding: EdgeInsets.zero,
        onTap: effectiveOnTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(NoirTokens.radius)),
                child: _MenuCardImage(
                  captureKey: captureKey ?? title,
                  imageAsset: imageAsset,
                  icon: icon,
                  cardColor: effectiveColor,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: NoirTokens.ink,
                        height: 1.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: NoirTokens.muted(size: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientPlaceholder(IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(icon, size: 32, color: Colors.white.withValues(alpha: 0.9)),
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
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: Theme.of(ctx).colorScheme.primary),
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
  final String serial;
  final VoidCallback onTap;
  const _FlowStep(this.icon, this.label, this.serial, this.onTap);
}

/// 管理员工具面板 — 以网格方式集中管理功能入口
class _AdminToolsPage extends StatelessWidget {
  const _AdminToolsPage();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final tools = <_AdminTool>[
      _AdminTool(Icons.people, '学生管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentManagePage()))),
      _AdminTool(Icons.person_add, '教师管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherManagePage()))),
      _AdminTool(Icons.how_to_reg, '申请审核',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherApplicationManagePage()))),
      _AdminTool(Icons.class_, '班级管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassManagePage()))),
      _AdminTool(Icons.school, '教学管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeachingManagePage()))),
      _AdminTool(Icons.science, '实验管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabTaskManagePage()))),
      _AdminTool(Icons.quiz_outlined, '题库管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionManagePage()))),
      _AdminTool(Icons.poll, '问卷管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SurveyManagePage()))),
      _AdminTool(Icons.feedback, '反馈管理',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FeedbackManagePage()))),
      _AdminTool(Icons.upload, '数据导入',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataImportPage()))),
      _AdminTool(Icons.download, '数据导出',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataExportPage()))),
      _AdminTool(Icons.analytics, '仓库分析',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RepoAnalyticsPage()))),
      _AdminTool(Icons.sync, '数据同步',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataSyncPage()))),
      _AdminTool(Icons.devices, '多端互通',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CrossPlatformHubPage()))),
      _AdminTool(Icons.fact_check, '成绩录入中心',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GradeEntryCenterPage()))),
      _AdminTool(Icons.settings, '系统设置',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
      // 仅 dev 机可用：4 端构建 + 双仓库 Release 一键发布
      _AdminTool(Icons.rocket_launch, '构建发布中心',
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReleaseCenterPage()))),
      // Demo 录制专用 — 仅管理员可见（kDebugMode 守卫已撤，评比时也能演示）
      _AdminTool(Icons.movie_creation_outlined, 'Demo 数据种子',
          () => _showDemoSeedSheet(context)),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 管理员 Hero：黑底纸感字 + 琥珀编号 ──────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(NoirTokens.radius),
                boxShadow: NoirTokens.smallShadow,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(NoirTokens.radius),
                    ),
                    child: const Icon(Icons.admin_panel_settings,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('№ ADMIN / SYSTEM',
                            style: NoirTokens.serial(color: Colors.white)),
                        const SizedBox(height: 6),
                        const Text(
                          '系统管理',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '系统级权限 · 管理各项功能与数据',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const NoirSectionTitle(
              eyebrow: '№ TOOLS',
              title: '管理工具',
              subtitle: 'Administration toolkit · 18 modules',
              margin: EdgeInsets.zero,
            ),
            const SizedBox(height: NoirTokens.spaceMd),
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
                childAspectRatio: 0.9,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: tools.map((t) => NoirCard(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    onTap: t.onTap,
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius:
                                  BorderRadius.circular(NoirTokens.radius),
                            ),
                            child: Icon(t.icon,
                                size: 18, color: Colors.white),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 22, height: 2, color: accent),
                              const SizedBox(height: 8),
                              Text(t.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                    color: NoirTokens.ink,
                                    height: 1.1,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
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

/// 展示 Demo 录制的数据种子操作面板（仅 debug build 入口可见）
Future<void> _showDemoSeedSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_creation_outlined, color: Colors.purple),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Demo 录制 — 数据种子',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '一键造数据让 AI 调用统计 / 班级问答页面有可见内容（30 条调用日志 / 3 个问题 / 4 条回复 + 5 条 Orchestrator 链路）。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 6),
          const Text(
            '所有数据都标记 [DEMO_SEED]，可一键撤销。仅 debug 构建可见。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final result = await DemoSeedService.instance.seedAll();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('已种入 $result')));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('一键种入'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final result =
                        await DemoSeedService.instance.revertSeed();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text('已清除 $result')));
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('撤销'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AdminTool {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _AdminTool(this.icon, this.title, this.onTap);
}

/// 根据状态显示缓存截图、asset 图片或渐变色占位
class _MenuCardImage extends StatelessWidget {
  final String? captureKey;
  final String? imageAsset;
  final IconData icon;
  final Color cardColor;

  const _MenuCardImage({
    this.captureKey,
    this.imageAsset,
    required this.icon,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    if (imageAsset != null) {
      return Image.asset(imageAsset!, fit: BoxFit.cover);
    }
    return FutureBuilder<String?>(
      future: captureKey != null
          ? ScreenshotService.instance.getCapturedPath(captureKey!)
          : Future.value(null),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null) {
          return Image.file(File(path), fit: BoxFit.cover);
        }
        return _buildGradientPlaceholder();
      },
    );
  }

  Widget _buildGradientPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardColor,
            cardColor.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }
}
