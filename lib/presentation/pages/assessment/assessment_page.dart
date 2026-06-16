import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/auto_grading_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/sync_service.dart';
import '../../../data/local/assessment_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/grading_result_dao.dart';
import '../../../data/local/score_audit_dao.dart';
import '../../../services/agent/agents/grading_agent.dart';
import '../../../services/score_export_service.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import '../../widgets/score_preview_dialog.dart';
import '../learning/pdf_viewer_page.dart';
import 'ai_grading_tab.dart';
import 'assessment_materials_tab.dart';
import 'audit_print_panel.dart';

import '../../../core/design/noir_tokens.dart';
import '../../../services/pdf_text_service.dart';
import '../../../core/error_handler.dart';
import 'defense/defense_broadcast_page.dart';

// ── Tab 实现拆分到 tabs/ 子目录（part / part of 模式）──────────────
part 'tabs/group_tab.dart';
part 'tabs/project_tab.dart';
part 'tabs/contribution_tab.dart';
part 'tabs/defense_tab.dart';
part 'tabs/report_tab.dart';
part 'tabs/score_tab.dart';

/// 考核页面 — 参考 Python 版 assessment_tab.py
/// 五大子页: 分组管理 / 项目立项 / 贡献评分 / 答辩安排 / 成绩统计
class AssessmentPage extends StatefulWidget {
  const AssessmentPage({super.key});

  @override
  State<AssessmentPage> createState() => _AssessmentPageState();
}

class _AssessmentPageState extends State<AssessmentPage>
    with SingleTickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _assessmentDao = AssessmentDao();
  bool _initialized = false;

  bool get _isStudent => !_authService.isTeacher && !_authService.isAdmin;

  @override
  String get innerTabPageKey => 'assessment';
  @override
  String get innerTabSpeakLabel => '考核';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() => _isStudent
      ? const ['分组', '项目', '贡献', '材料', '答辩', '报告', '成绩']
      : const ['分组', '项目', '贡献', '材料', '答辩', '报告', '成绩', 'AI批阅'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isStudent ? 7 : 8, vsync: this);
    _initDemoData();
    bindInnerTabRequest();
  }

  Future<void> _initDemoData() async {
    // 学生端：先拉取自己的最新同步数据（含教师评分）
    if (_isStudent) {
      try {
        final userId = _authService.getCurrentUserId();
        if (userId != null) await SyncService().downloadOwnData(userId);
      } catch (e) {
        swallow(e, tag: 'AssessmentPage.downloadOwnData');
      }
    }
    try {
      final jsonStr =
          await rootBundle.loadString('assets/student_group_data.json');
      final List<dynamic> decoded = jsonDecode(jsonStr);
      final students =
          decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      await _assessmentDao.syncGroupsFromStudentData(students);
    } catch (e) {
      swallow(e, tag: 'AssessmentPage.syncGroups');
    }
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showAssessmentScorePreview() async {
    final data =
        await ScoreExportService.instance.getAssessmentScoresForPreview();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => ScorePreviewDialog.assessment(
        data,
        onExport: data.isNotEmpty
            ? () async {
                Navigator.pop(context);
                await _exportAssessmentScores();
              }
            : null,
      ),
    );
  }

  Future<void> _exportAssessmentScores() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('正在导出考核成绩…'),
      duration: Duration(seconds: 1),
    ));
    final path = await ScoreExportService.instance.exportAssessmentScores();
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
      tooltip: '考核成绩',
      onSelected: (v) {
        if (v == 'view') _showAssessmentScorePreview();
        if (v == 'export') _exportAssessmentScores();
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
    final primary = Theme.of(context).colorScheme.primary;
    final gradient = AppGradientTheme.of(context);

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: gradient.linearGradient,
            boxShadow: [
              BoxShadow(
                color: gradient.gradientStart.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.assessment,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '课程考核工作台',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _isStudent
                                ? '聚焦项目、贡献、报告与答辩，完成课程考核闭环。'
                                : '统一管理分组、评分、答辩、报告与成绩，形成完整考核流程。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const AgentEntryButton(
                        agentId: 'assessment', color: Colors.white),
                    _buildHeaderRoleBadge(),
                    if (!_isStudent) _buildScoreActions(),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: const [
                    _AssessmentTopStat(
                        label: '分组', value: '5类', icon: Icons.groups),
                    _AssessmentTopStat(
                        label: '项目', value: '多视图', icon: Icons.assignment),
                    _AssessmentTopStat(
                        label: '贡献', value: '3维度', icon: Icons.star_rate),
                    _AssessmentTopStat(
                        label: '答辩',
                        value: '流程化',
                        icon: Icons.record_voice_over),
                    _AssessmentTopStat(
                        label: '报告', value: '4份', icon: Icons.summarize),
                    _AssessmentTopStat(
                        label: '成绩', value: '排行', icon: Icons.leaderboard),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: primary.withValues(alpha: 0.12)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            dividerColor: Colors.transparent,
            labelColor: primary,
            unselectedLabelColor: Colors.grey,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: [
              const Tab(icon: Icon(Icons.groups, size: 20), text: '分组'),
              const Tab(icon: Icon(Icons.assignment, size: 20), text: '项目'),
              const Tab(icon: Icon(Icons.star_rate, size: 20), text: '贡献'),
              const Tab(icon: Icon(Icons.menu_book, size: 20), text: '材料'),
              const Tab(
                  icon: Icon(Icons.record_voice_over, size: 20), text: '答辩'),
              const Tab(icon: Icon(Icons.summarize, size: 20), text: '报告'),
              const Tab(icon: Icon(Icons.leaderboard, size: 20), text: '成绩'),
              if (!_isStudent)
                const Tab(
                    icon: Icon(Icons.auto_awesome, size: 20), text: 'AI批阅'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GroupTab(authService: _authService),
              _ProjectTab(authService: _authService),
              _ContributionTab(authService: _authService),
              const AssessmentMaterialsTab(),
              _DefenseTab(authService: _authService),
              _AssessmentReportTab(authService: _authService),
              _ScoreTab(authService: _authService),
              if (!_isStudent)
                AssessmentAiGradingTab(authService: _authService),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRoleBadge() {
    final label = _authService.isAdmin
        ? '管理员视角'
        : _authService.isTeacher
            ? '教师视角'
            : '学生视角';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 顶部统计小组件
// ══════════════════════════════════════════════════════════════════════════════

class _AssessmentTopStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _AssessmentTopStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 分组管理 Tab — 支持5种维度分组：仓库/班组/项目/角色/技术栈
// ══════════════════════════════════════════════════════════════════════════════

/// 分组维度定义
