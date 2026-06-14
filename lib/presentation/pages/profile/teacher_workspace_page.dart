import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../core/constants/app_theme.dart';
import '../admin/student_manage_page.dart';
import '../admin/data_import_page.dart';
import '../admin/question_manage_page.dart';
import '../admin/data_export_page.dart';
import '../admin/class_manage_page.dart';
import '../admin/survey_manage_page.dart';
import '../analytics/learning_analytics_page.dart';
import '../analytics/agent_calls_dashboard_page.dart';
import '../graph/knowledge_graph_page.dart';
import '../admin/teaching_manage_page.dart';
import '../admin/lab_task_manage_page.dart';
import '../achievement/achievement_page.dart';
import '../materials/slide_generator_page.dart';
import '../materials/puml_manager_page.dart';
import '../materials/materials_hub_page.dart';
import '../admin/repo_analytics_page.dart';
import '../materials/courseware_workshop_page.dart';
import '../classroom/classroom_page.dart';
import '../sync/data_sync_page.dart';

import '../../../core/constants/role_guard.dart';

import '../../widgets/back_button_bar.dart';

class TeacherWorkspacePage extends StatefulWidget {
  const TeacherWorkspacePage({super.key});

  @override
  State<TeacherWorkspacePage> createState() => _TeacherWorkspacePageState();
}

class _TeacherWorkspacePageState extends State<TeacherWorkspacePage> {
  final _authService = AuthService();
  final _courseContext = CourseContextService();

  bool _isLoading = true;

  // 教学概览数据
  int _studentCount = 0;
  int _graphCount = 0;
  int _questionCount = 0;
  int _resourceCount = 0;

  // ── 教师工作量数据 ─────────────────────────────────────────────────
  /// 我已批阅的实验/作业总数（含 lab_submissions、project_scores 中我打过分的）
  int _myGradedCount = 0;

  /// 待批阅总数（lab_submissions 已提交但 score 为空 + project_scores 待评）
  int _myPendingCount = 0;

  /// 平均批阅耗时（按 lab_submissions.feedback_at - submitted_at 估算，分钟）
  int _avgGradingMinutes = 0;

  /// 学生满意度（学生作品收到的我评分中的平均分占百分比）
  int _avgScorePercent = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      final studentResult = await db.rawQuery(
        "SELECT COUNT(*) as count FROM users WHERE role='student'",
      );
      final graphScope = await _courseContext.scopedWhere();
      final questionScope = await _courseContext.scopedWhere();
      final resourceScope = await _courseContext.scopedWhere();
      final graphResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM graphs WHERE ${graphScope.where}',
        graphScope.args,
      );
      final questionResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM questions WHERE ${questionScope.where}',
        questionScope.args,
      );
      final resourceResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM resource_files WHERE ${resourceScope.where}',
        resourceScope.args,
      );

      setState(() {
        _studentCount = (studentResult.first['count'] as int?) ?? 0;
        _graphCount = (graphResult.first['count'] as int?) ?? 0;
        _questionCount = (questionResult.first['count'] as int?) ?? 0;
        _resourceCount = (resourceResult.first['count'] as int?) ?? 0;
        _isLoading = false;
      });

      // ── 工作量统计（异步加载，失败不影响顶部） ───────────────
      _loadTeacherWorkload();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTeacherWorkload() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      final db = await DatabaseHelper.instance.database;

      // 4 个独立查询并行执行
      final results = await Future.wait([
        db.rawQuery(
          "SELECT COUNT(*) as c FROM lab_submissions "
          "WHERE (score IS NOT NULL OR feedback IS NOT NULL) "
          "AND (graded_by = ? OR graded_by IS NULL)",
          [user.userId],
        ),
        db.rawQuery(
          "SELECT COUNT(*) as c FROM lab_submissions "
          "WHERE score IS NULL AND feedback IS NULL "
          "AND status = 'submitted'",
        ),
        db.rawQuery(
          "SELECT AVG((julianday(feedback_at) - julianday(submitted_at)) * 24 * 60) as m "
          "FROM lab_submissions "
          "WHERE feedback_at IS NOT NULL AND submitted_at IS NOT NULL",
        ),
        db.rawQuery("SELECT AVG(score) as s FROM work_scores"),
      ]);

      if (!mounted) return;
      setState(() {
        _myGradedCount = (results[0].first['c'] as int?) ?? 0;
        _myPendingCount = (results[1].first['c'] as int?) ?? 0;
        _avgGradingMinutes = ((results[2].first['m'] as num?)?.toInt()) ?? 0;
        final s = (results[3].first['s'] as num?)?.toDouble() ?? 0;
        _avgScorePercent = s.clamp(0, 100).toInt();
      });
    } catch (_) {
      // 表可能不存在 / 字段缺失 — 静默
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    // 权限守卫：仅教师/管理员可访问
    final role = user?.role ?? 'student';
    if (!RoleGuard.isTeacherOrAdmin(role)) {
      return Scaffold(
        appBar: BackButtonBar(title: '教师工作台'),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('无权限访问', style: TextStyle(fontSize: 18, color: Colors.grey)),
              SizedBox(height: 8),
              Text('仅教师和管理员可访问工作台', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final gradient = AppGradientTheme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: BackButtonBar(
        title: '教师工作台',
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 欢迎头部 ──────────────────────────────────────────────
              _buildWelcomeHeader(user, gradient),
              const SizedBox(height: 16),

              // ── 教学概览 ──────────────────────────────────────────────
              const Text(
                '教学概览',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildOverviewStats(),
              const SizedBox(height: 16),

              // ── 工作量仪表板 ──────────────────────────────────────────
              const Text(
                '我的工作量',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildWorkloadStats(),
              const SizedBox(height: 16),

              // ── 快捷工具 ──────────────────────────────────────────────
              const Text(
                '快捷工具',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildToolGrid(),
              const SizedBox(height: 16),

              // ── 最近动态 ──────────────────────────────────────────────
              const Text(
                '最近动态',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildRecentActivities(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 欢迎头部
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWelcomeHeader(dynamic user, AppGradientTheme gradient) {
    final displayName = user?.realName ?? user?.userId ?? '老师';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: gradient.linearGradient,
        ),
        child: Row(
          children: [
            // 头像
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 12),
            // 文字信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '欢迎回来，$displayName！',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '教师工作台',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '工号：${user?.userId ?? ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 教学概览 — 4 个统计卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOverviewStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            '学生人数',
            '$_studentCount',
            Icons.people,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '图谱数量',
            '$_graphCount',
            Icons.account_tree,
            Colors.teal,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '题库数量',
            '$_questionCount',
            Icons.quiz,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '资源数量',
            '$_resourceCount',
            Icons.folder,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 我的工作量 — 4 个 KPI 卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWorkloadStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            '已批阅',
            '$_myGradedCount',
            Icons.fact_check,
            Colors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '待批阅',
            '$_myPendingCount',
            Icons.pending_actions,
            _myPendingCount > 0 ? Colors.deepOrange : Colors.grey,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '平均耗时',
            _avgGradingMinutes > 0 ? '$_avgGradingMinutes分' : '—',
            Icons.timer_outlined,
            Colors.indigo,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            '平均给分',
            _avgScorePercent > 0 ? '$_avgScorePercent%' : '—',
            Icons.star_outline,
            Colors.amber[700]!,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 快捷工具 — 6 个工具卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildToolGrid() {
    final isAdmin = _authService.isAdmin;

    final tools = [
      // 管理员专属：学生管理
      if (isAdmin)
        _ToolItem(
          icon: Icons.people,
          label: '学生管理',
          color: Colors.blue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StudentManagePage()),
          ),
        ),
      _ToolItem(
        icon: Icons.quiz,
        label: '题库管理',
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuestionManagePage()),
        ),
      ),
      // 管理员专属：资源管理（数据导入）
      if (isAdmin)
        _ToolItem(
          icon: Icons.folder_open,
          label: '资源管理',
          color: Colors.purple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DataImportPage()),
          ),
        ),
      _ToolItem(
        icon: Icons.assessment,
        label: '成绩统计',
        color: Colors.green,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LearningAnalyticsPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.insights,
        label: 'AI 调用统计',
        color: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AgentCallsDashboardPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.hub,
        label: '知识图谱',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const KnowledgeGraphPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.download,
        label: '数据导出',
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataExportPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.class_,
        label: '班级管理',
        color: Colors.cyan,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClassManagePage()),
        ),
      ),
      _ToolItem(
        icon: Icons.poll,
        label: '问卷管理',
        color: Colors.pink,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SurveyManagePage()),
        ),
      ),
      _ToolItem(
        icon: Icons.cast_for_education,
        label: '课堂管理',
        color: Colors.lightBlue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClassroomPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.sync,
        label: '数据同步',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataSyncPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.school,
        label: '教学管理',
        color: Colors.deepOrange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeachingManagePage()),
        ),
      ),
      _ToolItem(
        icon: Icons.science,
        label: '实验管理',
        color: Colors.brown,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LabTaskManagePage()),
        ),
      ),
      _ToolItem(
        icon: Icons.emoji_events,
        label: '课程达成',
        color: Colors.deepOrange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AchievementPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.auto_awesome,
        label: 'AI生成',
        color: Colors.amber[800]!,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SlideGeneratorPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.movie_creation,
        label: '课件工坊',
        color: Colors.deepOrange[600]!,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CoursewareWorkshopPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.account_tree_outlined,
        label: 'UML图谱',
        color: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PumlManagerPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.inventory_2,
        label: '素材中心',
        color: Colors.teal[700]!,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MaterialsHubPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.analytics,
        label: '仓库分析',
        color: Colors.indigo[600]!,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RepoAnalyticsPage()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        final tool = tools[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: tool.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tool.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    tool.icon,
                    color: tool.color,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tool.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tool.color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 最近动态 — 模拟数据列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRecentActivities() {
    final activities = [
      _ActivityItem(
        icon: Icons.person_add,
        title: '新学生注册',
        subtitle: '共 $_studentCount 名学生已加入课程',
        time: '系统统计',
        color: Colors.blue,
      ),
      _ActivityItem(
        icon: Icons.quiz,
        title: '题库已就绪',
        subtitle: '共 $_questionCount 道题目覆盖 6 个章节',
        time: '系统统计',
        color: Colors.orange,
      ),
      _ActivityItem(
        icon: Icons.account_tree,
        title: '知识图谱',
        subtitle: '已创建 $_graphCount 个知识图谱',
        time: '系统统计',
        color: Colors.teal,
      ),
      _ActivityItem(
        icon: Icons.folder,
        title: '课程资源',
        subtitle: '已上传 $_resourceCount 个课程资源文件',
        time: '系统统计',
        color: Colors.purple,
      ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final activity = activities[index];
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: activity.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                activity.icon,
                color: activity.color,
                size: 22,
              ),
            ),
            title: Text(
              activity.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              activity.subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: Text(
              activity.time,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助数据类
// ─────────────────────────────────────────────────────────────────────────────

class _ToolItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _ActivityItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color color;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
  });
}
