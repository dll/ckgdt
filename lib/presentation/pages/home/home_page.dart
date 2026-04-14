import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/auth_service.dart';
import '../login/login_page.dart';
import '../graph/knowledge_graph_page.dart';
import '../graph/favorites_page.dart';
import '../quiz/quiz_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../learning/progress_page.dart';
import '../learning/learning_hub_page.dart';
import '../learning/learning_plan_page.dart';
import '../assessment/assessment_page.dart';
import '../survey/survey_page.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
import '../admin/teacher_manage_page.dart';
import '../admin/class_manage_page.dart';
import '../admin/survey_manage_page.dart';
import '../admin/question_manage_page.dart';
import '../admin/data_export_page.dart';
import '../admin/teaching_manage_page.dart';
import '../admin/lab_task_manage_page.dart';
import '../admin/repo_analytics_page.dart';
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
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isAdmin = _authService.isAdmin;
    final isTeacher = _authService.isTeacher;

    return Scaffold(
      appBar: AppBar(
        title: const Text('移动应用开发知识图谱'),

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
          PopupMenuButton<String>(
            icon: const Icon(Icons.person),
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
              // 教师/管理员：教师工作台
              if (isTeacher || isAdmin)
                const PopupMenuItem(
                  value: 'teacher_workspace',
                  child: ListTile(
                    leading: Icon(Icons.dashboard, color: Colors.indigo),
                    title: Text('教师工作台'),
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
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: [
          // 0: 首页
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          // 1: 图谱
          const NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: '图谱',
          ),
          // 2: 路径
          const NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: '路径',
          ),
          // 3: 学习（合并原"视频"+"课件"，含4个Tab：视频/PPT/PDF/AI助手）
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '学习',
          ),
          // 4: 测验
          const NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '测验',
          ),
          // 5: 实验
          const NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: '实验',
          ),
          // 6: 考核
          const NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment),
            label: '考核',
          ),
          // 7: 作品
          const NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: '作品',
          ),
          // 8: 仓库（Git仓库总览）
          const NavigationDestination(
            icon: Icon(Icons.source_outlined),
            selectedIcon: Icon(Icons.source),
            label: '仓库',
          ),
          // 9: 技能（AI 教学技能）
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '技能',
          ),
          // 10: 课堂（教师/管理员）
          if (isTeacher || isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.cast_for_education_outlined),
              selectedIcon: Icon(Icons.cast_for_education),
              label: '课堂',
            ),
          // 11: 达成（教师/管理员）
          if (isTeacher || isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: '达成',
            ),
          // 12: 管理（仅管理员）
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: '管理',
            ),
        ],
      ),
    );
  }

  /// Tab 索引映射（动态，取决于角色）:
  /// 0=首页 1=图谱 2=路径 3=学习(视频/PPT/PDF/AI助手) 4=测验 5=实验 6=考核 7=作品 8=仓库 9=技能
  /// 教师/管理员: 10=课堂 11=达成
  /// 管理员: 12=管理
  /// 学生: 无10/11/12
  Widget _buildBody() {
    final isAdmin = _authService.isAdmin;
    final isTeacher = _authService.isTeacher;
    final isTeacherOrAdmin = isTeacher || isAdmin;

    // 固定索引 0-9 映射
    switch (_selectedIndex) {
      case 0:
        return _buildHome();
      case 1:
        return const KnowledgeGraphPage();
      case 2:
        return const LearningPlanPage();
      case 3:
        return const LearningHubPage();
      case 4:
        return const QuizPage();
      case 5:
        return const LabTasksPage();
      case 6:
        return const AssessmentPage();
      case 7:
        return const WorksPage();
      case 8:
        // 教师/管理员 → 完整仓库管理; 学生 → 简化的个人仓库视图
        if (isTeacherOrAdmin) return const GitRepoPage();
        return const StudentRepoPage();
      case 9:
        return const SkillsHubPage();
      case 10:
        // 教师/管理员: 课堂管理; 其他角色不会有 index 10
        if (isTeacherOrAdmin) return const ClassroomPage();
        return _buildHome();
      case 11:
        // 教师/管理员: 达成; 其他角色不会有 index 11
        if (isTeacherOrAdmin) return const AchievementPage();
        return _buildHome();
      case 12:
        // 管理员: 管理
        if (isAdmin) return const _AdminToolsPage();
        return _buildHome();
      default:
        return _buildHome();
    }
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
                // ── 通用功能（所有角色） ──────────────────────────
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
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
                _buildMenuCard(
                  icon: Icons.menu_book,
                  title: '学习中心',
                  color: Colors.teal,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
                _buildMenuCard(
                  icon: Icons.quiz,
                  title: '章节测验',
                  color: Colors.orange,
                  onTap: () => setState(() => _selectedIndex = 4),
                ),
                _buildMenuCard(
                  icon: Icons.assessment,
                  title: '课程考核',
                  color: Colors.purple,
                  onTap: () => setState(() => _selectedIndex = 6),
                ),
                _buildMenuCard(
                  icon: Icons.workspace_premium,
                  title: '作品管理',
                  color: Colors.cyan,
                  onTap: () => setState(() => _selectedIndex = 7),
                ),
                _buildMenuCard(
                  icon: Icons.science,
                  title: '实验任务',
                  color: Colors.deepPurple,
                  onTap: () => setState(() => _selectedIndex = 5),
                ),
                _buildMenuCard(
                  icon: Icons.source,
                  title: 'Git仓库',
                  color: Colors.blueGrey,
                  onTap: () => setState(() => _selectedIndex = 8),
                ),
                _buildMenuCard(
                  icon: Icons.auto_awesome,
                  title: 'AI 技能',
                  color: Colors.deepPurple[400]!,
                  onTap: () => setState(() => _selectedIndex = 9),
                ),
                _buildMenuCard(
                  icon: Icons.sync,
                  title: '数据同步',
                  color: Colors.teal[600]!,
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DataSyncPage())),
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
                    icon: Icons.cast_for_education,
                    title: '课堂管理',
                    color: Colors.lightBlue,
                    onTap: () => setState(() => _selectedIndex = 10),
                  ),
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
                    icon: Icons.emoji_events,
                    title: '课程达成',
                    color: Colors.deepOrange[400]!,
                    onTap: () => setState(() => _selectedIndex = 11),
                  ),
                ],

                // ── 管理员专属功能 ──────────────────────────────
                if (isAdmin) ...[
                  _buildMenuCard(
                    icon: Icons.people,
                    title: '学生管理',
                    color: Colors.brown,
                    onTap: () => setState(() => _selectedIndex = 12),
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
}

class _AdminToolsPage extends StatelessWidget {
  const _AdminToolsPage();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 10,
      child: Scaffold(
        appBar: TabBar(
          isScrollable: true,
          tabs: const [
            Tab(text: '学生管理', icon: Icon(Icons.people)),
            Tab(text: '教师管理', icon: Icon(Icons.school)),
            Tab(text: '班级管理', icon: Icon(Icons.class_)),
            Tab(text: '题库管理', icon: Icon(Icons.quiz)),
            Tab(text: '问卷管理', icon: Icon(Icons.poll)),
            Tab(text: '教学管理', icon: Icon(Icons.menu_book)),
            Tab(text: '实验管理', icon: Icon(Icons.science)),
            Tab(text: '数据导入', icon: Icon(Icons.upload)),
            Tab(text: '数据导出', icon: Icon(Icons.download)),
            Tab(text: '仓库分析', icon: Icon(Icons.analytics)),
          ],
          labelColor: Theme.of(context).colorScheme.primary,
        ),
        body: const TabBarView(
          children: [
            StudentManagePage(),
            TeacherManagePage(),
            ClassManagePage(),
            QuestionManagePage(),
            SurveyManagePage(),
            TeachingManagePage(),
            LabTaskManagePage(),
            DataImportPage(),
            DataExportPage(),
            RepoAnalyticsPage(),
          ],
        ),
      ),
    );
  }
}
