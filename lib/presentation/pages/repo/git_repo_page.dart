import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/gitee_service.dart';
import '../../../services/course_resource_service.dart';
import '../../widgets/agent_entry_button.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';


// ── Tab 实现拆分到 tabs/ 子目录（part / part of 模式）──────────────
part 'tabs/repo_list_tab.dart';
part 'tabs/student_detail_tab.dart';
part 'tabs/repo_stats_tab.dart';
part 'tabs/submission_guidelines_tab.dart';
part 'tabs/gitee_settings_tab.dart';

/// Git 仓库总览页面
/// 功能：
/// 1. 仓库列表 Tab — 显示 cg1-*/cg2-*/cg3-* 学生项目仓库
/// 2. 学生详情 Tab — 选中仓库后显示 feat-{拼音首字母} 分支和提交记录
/// 3. 提交规范 Tab — 仓库/分支/提交命名规范说明
/// 4. Gitee 设置 Tab — Token 配置
class GitRepoPage extends StatefulWidget {
  const GitRepoPage({super.key});

  @override
  State<GitRepoPage> createState() => _GitRepoPageState();
}

class _GitRepoPageState extends State<GitRepoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _gitee = GiteeService();
  final _resource = CourseResourceService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git 仓库'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [AgentEntryButton(agentId: 'repo')],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.folder_copy, size: 18), text: '仓库列表'),
            Tab(icon: Icon(Icons.person_search, size: 18), text: '学生详情'),
            Tab(icon: Icon(Icons.analytics, size: 18), text: '统计概览'),
            Tab(icon: Icon(Icons.rule_folder, size: 18), text: '提交规范'),
            Tab(icon: Icon(Icons.settings, size: 18), text: 'Gitee设置'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RepoListTab(
            gitee: _gitee,
            resource: _resource,
            onRepoSelected: (owner, repo, repoName) {
              _tabController.animateTo(1);
              setState(() {
                _selectedOwner = owner;
                _selectedRepo = repo;
                _selectedRepoName = repoName;
              });
            },
          ),
          _StudentDetailTab(
            gitee: _gitee,
            resource: _resource,
            owner: _selectedOwner,
            repo: _selectedRepo,
            repoName: _selectedRepoName,
          ),
          _RepoStatsTab(gitee: _gitee, resource: _resource),
          const _SubmissionGuidelinesTab(),
          _GiteeSettingsTab(gitee: _gitee),
        ],
      ),
    );
  }

  String? _selectedOwner;
  String? _selectedRepo;
  String? _selectedRepoName;
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1: 仓库列表
// ══════════════════════════════════════════════════════════════════════════════

