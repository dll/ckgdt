import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/auth_service.dart';
import '../login/login_page.dart';
import '../graph/knowledge_graph_page.dart';
import '../graph/favorites_page.dart';
import '../quiz/quiz_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../learning/progress_page.dart';
import '../learning/video_page.dart';
import '../materials/materials_hub_page.dart';
import '../learning/learning_plan_page.dart';
import '../assessment/assessment_page.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
import '../admin/teacher_manage_page.dart';
import '../admin/class_manage_page.dart';
import '../admin/survey_manage_page.dart';
import '../works/works_page.dart';
import '../lab/lab_tasks_page.dart';
import '../achievement/achievement_page.dart';
import '../profile/student_center_page.dart';
import '../profile/teacher_workspace_page.dart';
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
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user?.userId ?? '用户'),
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
                  title: Text('设置'),
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
          // 3: 视频
          const NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: '视频',
          ),
          // 4: 课件
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '课件',
          ),
          // 5: 测验
          const NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '测验',
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
          // 8: 实验
          const NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: '实验',
          ),
          // 9: 达成（教师/管理员）
          if (isTeacher || isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: '达成',
            ),
          // 10: 管理（仅管理员）— 教师时为 9+1=10，非教师管理员时为 9
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
  /// 0=首页 1=图谱 2=路径 3=视频 4=课件 5=测验 6=考核 7=作品 8=实验
  /// 教师/管理员: 9=达成
  /// 管理员: 10=管理（教师时无此项）
  /// 学生: 无9/10
  Widget _buildBody() {
    final isAdmin = _authService.isAdmin;
    final isTeacher = _authService.isTeacher;
    final isTeacherOrAdmin = isTeacher || isAdmin;

    // 固定索引 0-8 映射
    switch (_selectedIndex) {
      case 0:
        return _buildHome();
      case 1:
        return const KnowledgeGraphPage();
      case 2:
        return const LearningPlanPage();
      case 3:
        return const VideoListPage();
      case 4:
        return const MaterialsHubPage();
      case 5:
        return const QuizPage();
      case 6:
        return const AssessmentPage();
      case 7:
        return const WorksPage();
      case 8:
        return const LabTasksPage();
      case 9:
        // 教师/管理员: 达成; 其他角色不会有 index 9
        if (isTeacherOrAdmin) return const AchievementPage();
        return _buildHome();
      case 10:
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
                    '欢迎回来，${user?.userId ?? '同学'}！',
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
          const SizedBox(height: 24),

          // 功能菜单
          const Text(
            '功能菜单',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
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
                icon: Icons.play_circle,
                title: '视频教程',
                color: Colors.red,
                onTap: () => setState(() => _selectedIndex = 3),
              ),
              _buildMenuCard(
                icon: Icons.menu_book,
                title: '课件资料',
                color: Colors.teal,
                onTap: () => setState(() => _selectedIndex = 4),
              ),
              _buildMenuCard(
                icon: Icons.quiz,
                title: '章节测验',
                color: Colors.orange,
                onTap: () => setState(() => _selectedIndex = 5),
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
                onTap: () => setState(() => _selectedIndex = 8),
              ),
              _buildMenuCard(
                icon: Icons.trending_up,
                title: '学习进度',
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProgressPage()),
                  );
                },
              ),
              _buildMenuCard(
                icon: Icons.error,
                title: '错题本',
                color: Colors.red[400]!,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WrongAnswersPage()),
                  );
                },
              ),
              _buildMenuCard(
                icon: Icons.star,
                title: '我的收藏',
                color: Colors.amber,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavoritesPage()),
                  );
                },
              ),
              if (_authService.isTeacher || _authService.isAdmin)
                _buildMenuCard(
                  icon: Icons.emoji_events,
                  title: '课程达成',
                  color: Colors.deepOrange,
                  onTap: () => setState(() => _selectedIndex = 9),
                ),
              if (_authService.isAdmin)
                _buildMenuCard(
                  icon: Icons.people,
                  title: '学生管理',
                  color: Colors.brown,
                  onTap: () => setState(() => _selectedIndex = 10),
                ),
            ],
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
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
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
      length: 5,
      child: Scaffold(
        appBar: TabBar(
          isScrollable: true,
          tabs: const [
            Tab(text: '学生管理', icon: Icon(Icons.people)),
            Tab(text: '教师管理', icon: Icon(Icons.school)),
            Tab(text: '班级管理', icon: Icon(Icons.class_)),
            Tab(text: '问卷管理', icon: Icon(Icons.poll)),
            Tab(text: '数据管理', icon: Icon(Icons.storage)),
          ],
          labelColor: Theme.of(context).colorScheme.primary,
        ),
        body: const TabBarView(
          children: [
            StudentManagePage(),
            TeacherManagePage(),
            ClassManagePage(),
            SurveyManagePage(),
            DataImportPage(),
          ],
        ),
      ),
    );
  }
}
