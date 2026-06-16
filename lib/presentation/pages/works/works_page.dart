import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/grading_result_dao.dart';
import '../../../data/local/score_audit_dao.dart';
import '../../../data/local/works_dao.dart';
import '../../widgets/score_history_dialog.dart';
import '../../../services/auth_service.dart';
import '../../../services/auto_grading_service.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/gitee_service.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/score_export_service.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import '../../widgets/score_preview_dialog.dart';
import 'ai_grading_tab.dart';

// ── Tab 实现拆分到 tabs/ 子目录（part / part of 模式）──────────────
part 'tabs/gallery_tab.dart';
part 'tabs/work_detail_sheet.dart';
part 'tabs/records_tab.dart';
part 'tabs/leaderboard_tab.dart';
part 'tabs/my_works_tab.dart';

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  作品视角维度（多维过滤，复用考核页的 _GroupDimension 模式）                ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

/// 作品过滤维度定义
enum _WorkDimension {
  all('全部', '', Icons.apps, Colors.blueGrey),
  repo('仓库', 'repo', Icons.folder_copy, Colors.blue),
  classGroup('班组', 'class_group', Icons.class_, Colors.teal),
  project('项目', 'project', Icons.science, Colors.purple),
  role('角色', 'student_role', Icons.engineering, Colors.orange),
  techStack('技术栈', 'tech_stack', Icons.code, Colors.indigo);

  final String label;
  final String dbKey; // 对应 student_works 表中的列名
  final IconData icon;
  final Color color;
  const _WorkDimension(this.label, this.dbKey, this.icon, this.color);
}

/// 获取学生显示名称：管理员/教师可见真名，学生端匿名
String _studentDisplayName(Map<String, dynamic> work, bool showReal) {
  if (showReal) {
    return work['student_name'] as String? ?? '未知同学';
  }
  return '匿名同学';
}

/// 获取头像首字符
String _avatarChar(Map<String, dynamic> work, bool showReal) {
  if (showReal) {
    final name = work['student_name'] as String? ?? '';
    return name.isNotEmpty ? name.characters.first : '?';
  }
  return '匿';
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  作品展评页面 — 每位同学一个作品 / 多维过滤 / 互评互赞                     ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

class WorksPage extends StatefulWidget {
  const WorksPage({super.key});

  @override
  State<WorksPage> createState() => _WorksPageState();
}

class _WorksPageState extends State<WorksPage>
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _worksDao = WorksDao();
  Map<String, dynamic> _overview = {};
  List<Map<String, dynamic>> _allStudents = [];
  bool _initialized = false;

  bool get _isTeacherOrAdmin => _authService.isTeacher || _authService.isAdmin;

  bool get _isStudent => !_isTeacherOrAdmin;

  /// 学生在第 0 个 tab 看到 "我的作品"；教师没有这个 tab 但多 "AI批阅"。
  /// length = 3 公共 + 学生(+1 我的) + 教师(+1 AI批阅)。
  int get _tabCount => 3 + (_isStudent ? 1 : 0) + (_isTeacherOrAdmin ? 1 : 0);

  @override
  String get innerTabPageKey => 'works';
  @override
  String get innerTabSpeakLabel => '作品';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() => _isStudent
      ? const ['我的作品', '作品展示', '作品记录', '排行榜']
      : const ['作品展示', '作品记录', '排行榜', 'AI批阅'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
    );
    _initData();
    bindInnerTabRequest();
  }

  Future<void> _initData() async {
    // 学生端：先拉取自己的最新同步数据（含教师评分、同学互评）
    if (!_authService.isTeacher && !_authService.isAdmin) {
      try {
        final userId = _authService.getCurrentUserId();
        if (userId != null) await SyncService().downloadOwnData(userId);
      } catch (e, st) {
        swallowDebug(e, tag: 'WorksPage.downloadOwnData', stack: st);
      }
    }
    // 一次性清理旧版虚假互动数据
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('works_fake_data_cleaned') ?? false)) {
        await _worksDao.cleanupFakeData();
        await prefs.setBool('works_fake_data_cleaned', true);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksPage.cleanupFakeData', stack: st);
    }
    // 1. 从 JSON 加载学生数据
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _allStudents = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      // 2. 同步到数据库（每人一个作品，幂等）
      await _worksDao.syncStudentWorks(_allStudents);
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksPage.loadStudents', stack: st);
    }
    // 3. 加载统计概览
    await _loadOverview();
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _loadOverview() async {
    try {
      final ov = await _worksDao.getOverview();
      if (mounted) setState(() => _overview = ov);
    } catch (e, st) {
      swallowDebug(e, tag: 'WorksPage.loadOverview', stack: st);
    }
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showWorkScorePreview() async {
    final data = await ScoreExportService.instance.getWorkScoresForPreview();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => ScorePreviewDialog.works(
        data,
        onExport: data.isNotEmpty
            ? () async {
                Navigator.pop(context);
                await _exportWorkScores();
              }
            : null,
      ),
    );
  }

  Future<void> _exportWorkScores() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('正在导出作品成绩…'),
      duration: Duration(seconds: 1),
    ));
    final path = await ScoreExportService.instance.exportWorkScores();
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (path != null) {
      messenger.showSnackBar(SnackBar(
        content: Text('导出成功！\n$path'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '确定',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: const Text('暂无成绩数据可导出'),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: '确定',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ));
    }
  }

  Widget _buildScoreActions() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.assessment, size: 20, color: Colors.white),
      tooltip: '作品成绩',
      onSelected: (v) {
        if (v == 'view') _showWorkScorePreview();
        if (v == 'export') _exportWorkScores();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(children: [
            Icon(Icons.table_chart, size: 18),
            SizedBox(width: 8),
            Text('查看成绩'),
          ]),
        ),
        const PopupMenuItem(
          value: 'export',
          child: Row(children: [
            Icon(Icons.file_download, size: 18),
            SizedBox(width: 8),
            Text('导出成绩'),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradTheme = AppGradientTheme.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final isTeacher = _authService.isTeacher || _authService.isAdmin;

    return Column(
      children: [
        // ── 渐变页头（紧凑）────────────────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: gradTheme.linearGradient),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.play_circle_filled,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('作品展评中心',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  const AgentEntryButton(agentId: 'works', color: Colors.white),
                  _buildRoleBadge(isTeacher),
                  if (_isTeacherOrAdmin) _buildScoreActions(),
                ],
              ),
              if (_initialized) ...[
                const SizedBox(height: 8),
                _buildHeaderStats(),
              ],
            ],
          ),
        ),
        // ── 圆角 TabBar ──────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(10),
            ),
            splashBorderRadius: BorderRadius.circular(10),
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              if (_isStudent) const Tab(text: '我的作品'),
              const Tab(text: '作品展示'),
              const Tab(text: '作品记录'),
              const Tab(text: '排行榜'),
              if (_isTeacherOrAdmin) const Tab(text: 'AI批阅'),
            ],
          ),
        ),
        // ── TabBarView ───────────────────────────────────
        Expanded(
          child: _initialized
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    if (_isStudent)
                      _MyWorksTab(
                        authService: _authService,
                        onDataChanged: _loadOverview,
                      ),
                    _GalleryTab(
                      authService: _authService,
                      allStudents: _allStudents,
                      onDataChanged: _loadOverview,
                    ),
                    _RecordsTab(authService: _authService),
                    _LeaderboardTab(authService: _authService),
                    if (_isTeacherOrAdmin)
                      WorksAiGradingTab(authService: _authService),
                  ],
                )
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在加载作品数据...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRoleBadge(bool isTeacher) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(
        isTeacher ? '教师端' : '学生端',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildHeaderStats() {
    final stats = [
      {
        'icon': Icons.videocam,
        'label': '作品',
        'value': '${_overview['total_works'] ?? 0}'
      },
      {
        'icon': Icons.visibility,
        'label': '播放',
        'value': '${_overview['total_views'] ?? 0}'
      },
      {
        'icon': Icons.favorite,
        'label': '点赞',
        'value': '${_overview['total_likes'] ?? 0}'
      },
      {
        'icon': Icons.comment,
        'label': '评论',
        'value': '${_overview['total_comments'] ?? 0}'
      },
    ];
    return Row(
      children: stats
          .map((s) => Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s['icon'] as IconData,
                        color: Colors.white.withValues(alpha: 0.8), size: 14),
                    const SizedBox(width: 3),
                    Text('${s['value']}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(width: 2),
                    Text(s['label'] as String,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 10)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  公共 UI 辅助                                                              ║
// ╚══════════════════════════════════════════════════════════════════════════════╝

Widget _sectionHeader(String title, {IconData? icon, Color? color}) {
  final c = color ?? Colors.blue;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        if (icon != null) ...[
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 6),
        ],
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

Widget _emptyHint(String message, IconData icon) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey[200]!),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
      ],
    ),
  );
}

Widget _statChip(IconData icon, String value, String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    ),
  );
}

String _timeAgo(String? isoTime) {
  if (isoTime == null || isoTime.isEmpty) return '';
  try {
    final dt = DateTime.parse(isoTime);
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}月前';
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  } catch (e) {
    swallow(e, tag: 'WorksPage._fmtTime');
    return isoTime;
  }
}

/// 截取角色名关键词：'HarmonyOS开发工程师' → 'HarmonyOS'
String _shortRole(String? role) {
  if (role == null || role.isEmpty) return '';
  final idx = role.indexOf('开发');
  if (idx > 0) return role.substring(0, idx);
  return role.length > 10 ? '${role.substring(0, 10)}…' : role;
}

// ╔══════════════════════════════════════════════════════════════════════════════╗
// ║  Tab 0: 作品展示 (Gallery) — 多维度过滤 + 搜索 + 排序                       ║
// ╚══════════════════════════════════════════════════════════════════════════════╝
