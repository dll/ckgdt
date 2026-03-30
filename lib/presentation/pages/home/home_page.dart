import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../login/login_page.dart';
import '../graph/graph_list_page.dart';
import '../graph/favorites_page.dart';
import '../quiz/quiz_page.dart';
import '../quiz/wrong_answers_page.dart';
import '../learning/progress_page.dart';
import '../learning/video_page.dart';
import '../learning/document_page.dart';
import '../learning/learning_plan_page.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('移动应用开发知识图谱'),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
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
                await _authService.logout();
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                }
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
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: '图谱',
          ),
          const NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '测验',
          ),
          const NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: '视频',
          ),
          const NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: '资料',
          ),
          const NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up),
            label: '进度',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '计划',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
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

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildHome();
      case 1:
        return const GraphListPage();
      case 2:
        return const QuizPage();
      case 3:
        return const VideoListPage();
      case 4:
        return const DocumentListPage();
      case 5:
        return const ProgressPage();
      case 6:
        return const LearningPlanPage();
      case 7:
        return const SettingsPage();
      case 8:
        return const _AdminToolsPage();
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
                gradient: const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
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
                icon: Icons.quiz,
                title: '章节测验',
                color: Colors.orange,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              _buildMenuCard(
                icon: Icons.play_circle,
                title: '视频教程',
                color: Colors.red,
                onTap: () => setState(() => _selectedIndex = 4),
              ),
              _buildMenuCard(
                icon: Icons.description,
                title: '课程资料',
                color: Colors.teal,
                onTap: () => setState(() => _selectedIndex = 3),
              ),
              _buildMenuCard(
                icon: Icons.trending_up,
                title: '学习进度',
                color: Colors.green,
                onTap: () => setState(() => _selectedIndex = 5),
              ),
              _buildMenuCard(
                icon: Icons.event_note,
                title: '学习计划',
                color: Colors.indigo,
                onTap: () => setState(() => _selectedIndex = 6),
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
              if (_authService.isAdmin)
                _buildMenuCard(
                  icon: Icons.people,
                  title: '学生管理',
                  color: Colors.purple,
                  onTap: () => setState(() => _selectedIndex = 8),
                ),
              _buildMenuCard(
                icon: Icons.settings,
                title: '设置',
                color: Colors.grey,
                onTap: () => setState(() => _selectedIndex = 7),
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
      length: 2,
      child: Scaffold(
        appBar: const TabBar(
          tabs: [
            Tab(text: '学生管理', icon: Icon(Icons.people)),
            Tab(text: '数据管理', icon: Icon(Icons.storage)),
          ],
          labelColor: Color(0xFF667eea),
        ),
        body: const TabBarView(
          children: [
            StudentManagePage(),
            DataImportPage(),
          ],
        ),
      ),
    );
  }
}
