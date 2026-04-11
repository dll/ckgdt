import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/gitee_service.dart';
import '../../../services/course_resource_service.dart';

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
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.folder_copy, size: 18), text: '仓库列表'),
              Tab(icon: Icon(Icons.person_search, size: 18), text: '学生详情'),
              Tab(icon: Icon(Icons.rule_folder, size: 18), text: '提交规范'),
              Tab(icon: Icon(Icons.settings, size: 18), text: 'Gitee设置'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RepoListTab(
                gitee: _gitee,
                resource: _resource,
                onRepoSelected: (owner, repo, repoName) {
                  _tabController.animateTo(1);
                  // 通过 key 刷新学生详情 Tab
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
              const _SubmissionGuidelinesTab(),
              _GiteeSettingsTab(gitee: _gitee),
            ],
          ),
        ),
      ],
    );
  }

  String? _selectedOwner;
  String? _selectedRepo;
  String? _selectedRepoName;
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1: 仓库列表
// ══════════════════════════════════════════════════════════════════════════════

class _RepoListTab extends StatefulWidget {
  final GiteeService gitee;
  final CourseResourceService resource;
  final void Function(String owner, String repo, String repoName) onRepoSelected;

  const _RepoListTab({
    required this.gitee,
    required this.resource,
    required this.onRepoSelected,
  });

  @override
  State<_RepoListTab> createState() => _RepoListTabState();
}

class _RepoListTabState extends State<_RepoListTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _repos = [];
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  Future<void> _loadRepos({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await widget.gitee.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _isLoading = false;
          _error = '请先在「Gitee设置」中配置访问令牌';
        });
        return;
      }

      final repos = await widget.resource.getStudentRepos(forceRefresh: force);
      if (mounted) {
        setState(() {
          _repos = repos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadRepos(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_repos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('未找到学生项目仓库', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('请确认企业(chzuczldl)下存在 cg1-/cg2-/cg3- 前缀仓库',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      );
    }

    // 按 CG1/CG2/CG3 分组
    final grouped = widget.resource.groupByPrefix(_repos);

    return RefreshIndicator(
      onRefresh: () => _loadRepos(force: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 统计卡片
          _buildStatsCard(),
          const SizedBox(height: 12),
          // 分组仓库列表
          ...grouped.entries.map((entry) => _buildGroupSection(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final gradient = AppGradientTheme.of(context);
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: gradient.linearGradient,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text('${_repos.length}',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Text('仓库总数', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            ...['1', '2', '3'].map((groupNum) {
              final count = _repos
                  .where((r) => CourseResourceService.extractGroupNumber(
                        (r['path']?.toString() ?? '').toLowerCase()) == groupNum)
                  .length;
              return Expanded(
                child: Column(
                  children: [
                    Text('$count',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('CG$groupNum',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSection(String group, List<Map<String, dynamic>> repos) {
    final groupColors = {
      'CG1': Colors.blue,
      'CG2': Colors.green,
      'CG3': Colors.orange,
    };
    final color = groupColors[group] ?? Colors.grey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$group · ${repos.length}个仓库',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: color, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        ...repos.map((repo) => _buildRepoCard(repo, color)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildRepoCard(Map<String, dynamic> repo, Color groupColor) {
    final name = repo['name']?.toString() ?? repo['path']?.toString() ?? '未知';
    final humanName = repo['human_name']?.toString() ?? '';
    final desc = repo['description']?.toString() ?? '';
    final updatedAt = repo['updated_at']?.toString() ?? '';
    final forksCount = repo['forks_count'] ?? 0;
    final watchersCount = repo['watchers_count'] ?? 0;
    final repoPath = repo['path']?.toString() ?? name;

    // 解析更新时间
    String timeAgo = '';
    if (updatedAt.isNotEmpty) {
      final dt = DateTime.tryParse(updatedAt);
      if (dt != null) {
        final diff = DateTime.now().difference(dt);
        if (diff.inDays > 0) {
          timeAgo = '${diff.inDays}天前';
        } else if (diff.inHours > 0) {
          timeAgo = '${diff.inHours}小时前';
        } else {
          timeAgo = '${diff.inMinutes}分钟前';
        }
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => widget.onRepoSelected(
            CourseResourceService.enterprise, repoPath, name),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_special, color: groupColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                  if (timeAgo.isNotEmpty)
                    Text(timeAgo,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
              if (humanName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(humanName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildMetaBadge(Icons.fork_right, '$forksCount', Colors.blue),
                  const SizedBox(width: 12),
                  _buildMetaBadge(
                      Icons.visibility, '$watchersCount', Colors.green),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios,
                      size: 14, color: Colors.grey[400]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaBadge(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2: 学生详情（仓库分支 + 提交记录）
// ══════════════════════════════════════════════════════════════════════════════

class _StudentDetailTab extends StatefulWidget {
  final GiteeService gitee;
  final CourseResourceService resource;
  final String? owner;
  final String? repo;
  final String? repoName;

  const _StudentDetailTab({
    required this.gitee,
    required this.resource,
    this.owner,
    this.repo,
    this.repoName,
  });

  @override
  State<_StudentDetailTab> createState() => _StudentDetailTabState();
}

class _StudentDetailTabState extends State<_StudentDetailTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _commits = [];
  String? _selectedBranch;
  bool _isLoadingBranches = false;
  bool _isLoadingCommits = false;
  int _commitPage = 1;
  bool _hasMoreCommits = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _StudentDetailTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repo != oldWidget.repo || widget.owner != oldWidget.owner) {
      _loadBranches();
    }
  }

  Future<void> _loadBranches() async {
    if (widget.owner == null || widget.repo == null) return;
    setState(() {
      _isLoadingBranches = true;
      _branches = [];
      _commits = [];
      _selectedBranch = null;
    });

    try {
      final branches =
          await widget.gitee.getBranches(widget.owner!, widget.repo!);
      if (mounted) {
        setState(() {
          _branches = branches;
          _isLoadingBranches = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _loadCommits(String branch, {bool reset = true}) async {
    if (widget.owner == null || widget.repo == null) return;
    if (reset) {
      setState(() {
        _commits = [];
        _commitPage = 1;
        _hasMoreCommits = true;
      });
    }
    setState(() => _isLoadingCommits = true);

    try {
      final commits = await widget.gitee.getCommits(
        widget.owner!,
        widget.repo!,
        sha: branch,
        page: _commitPage,
        perPage: 20,
      );
      if (mounted) {
        setState(() {
          if (reset) {
            _commits = commits;
          } else {
            _commits.addAll(commits);
          }
          _hasMoreCommits = commits.length >= 20;
          _isLoadingCommits = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCommits = false);
    }
  }

  void _loadMoreCommits() {
    if (_selectedBranch == null || !_hasMoreCommits || _isLoadingCommits) return;
    _commitPage++;
    _loadCommits(_selectedBranch!, reset: false);
  }

  List<Map<String, dynamic>> get _studentBranches =>
      _branches.where((b) => CourseResourceService.studentBranchPattern
          .hasMatch(b['name'].toString())).toList();

  List<Map<String, dynamic>> get _systemBranches =>
      _branches.where((b) => !CourseResourceService.studentBranchPattern
          .hasMatch(b['name'].toString())).toList();

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.repo == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('请在「仓库列表」中选择一个仓库',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    // 根据屏幕宽度决定布局
    final isWide = MediaQuery.of(context).size.width > 600;

    return Column(
      children: [
        // 仓库信息头 + 统计卡片
        _buildRepoHeader(),
        const Divider(height: 1),
        // 分支 + 提交
        Expanded(
          child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
        ),
      ],
    );
  }

  /// 宽屏布局：左右分栏
  Widget _buildWideLayout() {
    return Row(
      children: [
        SizedBox(width: 200, child: _buildBranchList()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildCommitList()),
      ],
    );
  }

  /// 窄屏布局：上方分支选择器 + 下方提交列表
  Widget _buildNarrowLayout() {
    return Column(
      children: [
        // 分支横向滚动选择器
        _buildBranchSelector(),
        const Divider(height: 1),
        // 提交列表
        Expanded(child: _buildCommitList()),
      ],
    );
  }

  Widget _buildRepoHeader() {
    final gradient = AppGradientTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gradient.gradientStart.withValues(alpha: 0.08),
            gradient.gradientEnd.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.folder_special, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.repoName ?? widget.repo ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${widget.owner}/${widget.repo}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadBranches,
                tooltip: '刷新分支',
              ),
            ],
          ),
          if (_branches.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _buildStatChip(Icons.alt_route, '${_branches.length}',
                    '总分支', Colors.blue),
                const SizedBox(width: 8),
                _buildStatChip(Icons.person, '${_studentBranches.length}',
                    '学生', Colors.green),
                const SizedBox(width: 8),
                _buildStatChip(Icons.commit, '${_commits.length}',
                    '提交', Colors.orange),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color)),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  /// 窄屏：横向分支选择器
  Widget _buildBranchSelector() {
    if (_isLoadingBranches) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          ..._studentBranches.map((b) => _buildBranchChip(b, true)),
          if (_systemBranches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: VerticalDivider(width: 1, color: Colors.grey[300]),
            ),
            ..._systemBranches.map((b) => _buildBranchChip(b, false)),
          ],
        ],
      ),
    );
  }

  Widget _buildBranchChip(Map<String, dynamic> branch, bool isStudent) {
    final name = branch['name']?.toString() ?? '';
    final isSelected = _selectedBranch == name;
    final displayName = isStudent ? name.substring(5) : name;
    final color = isStudent ? Colors.teal : Colors.blue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isStudent ? Icons.person : Icons.alt_route,
                size: 12, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(displayName, style: const TextStyle(fontSize: 12)),
          ],
        ),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedBranch = name);
          _loadCommits(name);
        },
        selectedColor: color,
        labelStyle: TextStyle(
            color: isSelected ? Colors.white : null, fontSize: 12),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildBranchList() {
    if (_isLoadingBranches) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_branches.isEmpty) {
      return Center(
          child: Text('暂无分支', style: TextStyle(color: Colors.grey[500])));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_studentBranches.isNotEmpty) ...[
          _buildSectionHeader(
              '学生分支 (${_studentBranches.length})', Colors.green),
          ..._studentBranches.map((b) => _buildBranchTile(b, true)),
        ],
        if (_systemBranches.isNotEmpty) ...[
          _buildSectionHeader(
              '系统分支 (${_systemBranches.length})', Colors.blue),
          ..._systemBranches.map((b) => _buildBranchTile(b, false)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildBranchTile(Map<String, dynamic> branch, bool isStudent) {
    final name = branch['name']?.toString() ?? '';
    final isSelected = _selectedBranch == name;
    final displayName = isStudent ? name.substring(5) : name;
    final color = isStudent ? Colors.teal : Colors.blue;

    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: color.withValues(alpha: 0.1),
      leading: Icon(isStudent ? Icons.person : Icons.alt_route,
          size: 16, color: isSelected ? color : Colors.grey),
      title: Text(displayName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : null,
          )),
      onTap: () {
        setState(() => _selectedBranch = name);
        _loadCommits(name);
      },
    );
  }

  Widget _buildCommitList() {
    if (_selectedBranch == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('选择分支查看提交记录',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    if (_isLoadingCommits && _commits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_commits.isEmpty) {
      return Center(
          child:
              Text('该分支暂无提交', style: TextStyle(color: Colors.grey[500])));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              const Icon(Icons.alt_route, size: 16, color: Colors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_selectedBranch!,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_commits.length} 提交',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.teal)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 50) {
                _loadMoreCommits();
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _commits.length + (_hasMoreCommits ? 1 : 0),
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 56),
              itemBuilder: (context, index) {
                if (index >= _commits.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return _buildCommitTile(_commits[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommitTile(Map<String, dynamic> commit) {
    final commitData = commit['commit'] as Map<String, dynamic>? ?? {};
    final message = commitData['message']?.toString() ?? '(无提交信息)';
    final authorData = commitData['author'] as Map<String, dynamic>? ??
        commitData['committer'] as Map<String, dynamic>? ??
        {};
    final authorName = authorData['name']?.toString() ?? '未知';
    final dateStr = authorData['date']?.toString() ?? '';
    final sha = commit['sha']?.toString() ?? '';
    final shortSha = sha.length > 7 ? sha.substring(0, 7) : sha;
    final avatarUrl = commit['author']?['avatar_url']?.toString();
    final firstLine = message.split('\n').first.trim();

    String timeDisplay = '';
    if (dateStr.isNotEmpty) {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        final local = dt.toLocal();
        final diff = DateTime.now().difference(local);
        if (diff.inDays > 7) {
          timeDisplay =
              '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        } else if (diff.inDays > 0) {
          timeDisplay = '${diff.inDays}天前';
        } else if (diff.inHours > 0) {
          timeDisplay = '${diff.inHours}小时前';
        } else {
          timeDisplay = '${diff.inMinutes}分钟前';
        }
      }
    }

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 12, 12),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[200],
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
        child: avatarUrl == null
            ? Text(
                authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 12))
            : null,
      ),
      title: Text(firstLine,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: Row(
        children: [
          Text(authorName,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(width: 8),
          if (timeDisplay.isNotEmpty)
            Text(timeDisplay,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(shortSha,
                style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.grey[700])),
          ),
        ],
      ),
      children: [
        // 展开显示完整提交信息
        if (message.contains('\n'))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(message,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.fingerprint, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            SelectableText(sha,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 3: 提交规范（学生指南）
// ══════════════════════════════════════════════════════════════════════════════

class _SubmissionGuidelinesTab extends StatelessWidget {
  const _SubmissionGuidelinesTab();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 重要提示横幅 ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.withValues(alpha: 0.15), Colors.red.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️ 命名规范必须严格遵守',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('不符合规范的仓库和分支将不会被系统识别和读取，'
                        '请在首次提交前仔细确认命名是否正确。',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 1. 仓库命名规范 ──
        _buildGuideCard(
          context,
          icon: Icons.folder_outlined,
          color: Colors.blue,
          title: '1. 仓库命名规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('仓库前缀', '必须以 cg1-、cg2- 或 cg3- 开头',
                Icons.check_circle, Colors.green),
            _buildRuleItem('命名格式', 'cg{组号}-{项目简称}',
                Icons.format_shapes, primary),
            const Divider(height: 20),
            const Text('✅ 正确示例：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeExample('cg1-sclspdi   (第1组-xxx项目)'),
            _buildCodeExample('cg2-sclspdi   (第2组-xxx项目)'),
            _buildCodeExample('cg3-ihftpdi   (第3组-xxx项目)'),
            const SizedBox(height: 8),
            const Text('❌ 错误示例（不会被读取）：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
            const SizedBox(height: 6),
            _buildCodeExample('cg1sclspdi    (缺少连字符 -)'),
            _buildCodeExample('CG1-project   (前缀必须小写)'),
            _buildCodeExample('project-cg1   (前缀位置不对)'),
            _buildCodeExample('my-project    (缺少 cg 前缀)'),
          ],
        ),

        const SizedBox(height: 16),

        // ── 2. 分支命名规范 ──
        _buildGuideCard(
          context,
          icon: Icons.account_tree_outlined,
          color: Colors.green,
          title: '2. 分支命名规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('分支格式', 'feat-{姓名拼音首字母小写}',
                Icons.check_circle, Colors.green),
            _buildRuleItem('字母数量', '2~5 个小写字母',
                Icons.text_fields, primary),
            _buildRuleItem('用途', '每个学生在小组仓库中创建自己的分支',
                Icons.person, Colors.orange),
            const Divider(height: 20),
            const Text('✅ 正确示例：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeExample('feat-cjn     (陈佳宁 → cjn)'),
            _buildCodeExample('feat-ldl     (刘东良 → ldl)'),
            _buildCodeExample('feat-zwq     (张伟强 → zwq)'),
            _buildCodeExample('feat-cs      (陈帅 → cs)'),
            const SizedBox(height: 8),
            const Text('❌ 错误示例（不会被读取）：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
            const SizedBox(height: 6),
            _buildCodeExample('feat-CJN        (必须全小写)'),
            _buildCodeExample('feat-陈佳宁     (必须用拼音首字母)'),
            _buildCodeExample('feature-cjn     (前缀必须是 feat-)'),
            _buildCodeExample('cjn             (缺少 feat- 前缀)'),
            _buildCodeExample('feat-abcdef     (最多5个字母)'),
            _buildCodeExample('feat-a          (至少2个字母)'),
          ],
        ),

        const SizedBox(height: 16),

        // ── 3. 提交（Commit）规范 ──
        _buildGuideCard(
          context,
          icon: Icons.commit,
          color: Colors.purple,
          title: '3. 提交消息规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('消息格式', '<类型>: <简短描述>',
                Icons.format_shapes, primary),
            const Divider(height: 20),
            const Text('提交类型：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildTypeChip('feat', '新功能 / 新增内容', Colors.green),
            _buildTypeChip('fix', '修复问题', Colors.red),
            _buildTypeChip('docs', '文档变更', Colors.blue),
            _buildTypeChip('style', '格式调整（不影响逻辑）', Colors.orange),
            _buildTypeChip('refactor', '代码重构', Colors.purple),
            _buildTypeChip('test', '测试相关', Colors.teal),
            const SizedBox(height: 10),
            const Text('✅ 正确示例：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeExample('feat: 完成实验一开发环境搭建'),
            _buildCodeExample('docs: 提交实验二实验报告'),
            _buildCodeExample('fix: 修复登录页面闪退'),
          ],
        ),

        const SizedBox(height: 16),

        // ── 4. 实验提交规范 ──
        _buildGuideCard(
          context,
          icon: Icons.science_outlined,
          color: Colors.teal,
          title: '4. 实验提交规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('代码提交', '实验代码推送到个人分支（feat-xxx）',
                Icons.code, primary),
            _buildRuleItem('实验报告', '报告放在项目根目录 /docs/reports/ 下',
                Icons.description, Colors.blue),
            _buildRuleItem('文件命名', '实验报告命名为 实验X_姓名.md 或 .docx',
                Icons.drive_file_rename_outline, Colors.orange),
            const Divider(height: 20),
            const Text('目录结构参考：', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeBlock(
              'cg1-sclspdi/         ← 小组仓库\n'
              '├── docs/\n'
              '│   └── reports/\n'
              '│       ├── 实验一_姓名.md\n'
              '│       ├── 实验二_姓名.md\n'
              '│       └── ...\n'
              '├── src/              ← 项目源代码\n'
              '└── README.md'
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── 5. 考核项目规范 ──
        _buildGuideCard(
          context,
          icon: Icons.assignment_outlined,
          color: Colors.orange,
          title: '5. 考核项目提交规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('项目代码', '推送到个人分支',
                Icons.code, primary),
            _buildRuleItem('项目文档', '项目报告放在 /docs/ 目录下',
                Icons.folder_open, Colors.blue),
            _buildRuleItem('答辩材料', 'PPT 放在 /docs/defense/ 目录下',
                Icons.slideshow, Colors.green),
            _buildRuleItem('截止时间', '考核截止前必须完成所有推送',
                Icons.access_time, Colors.red),
          ],
        ),

        const SizedBox(height: 16),

        // ── 6. 作品提交规范 ──
        _buildGuideCard(
          context,
          icon: Icons.palette_outlined,
          color: Colors.indigo,
          title: '6. 作品提交规范',
          cardColor: cardColor,
          children: [
            _buildRuleItem('提交位置', '作品推送到个人分支的 /works/ 目录',
                Icons.folder_special, primary),
            _buildRuleItem('必须包含', 'README.md 说明文档（作品名称/截图/技术栈）',
                Icons.description, Colors.blue),
            _buildRuleItem('可选附件', '演示视频或截图放在 /works/assets/ 下',
                Icons.image, Colors.green),
          ],
        ),

        const SizedBox(height: 16),

        // ── 快速操作命令 ──
        _buildGuideCard(
          context,
          icon: Icons.terminal,
          color: Colors.grey,
          title: '常用 Git 命令',
          cardColor: cardColor,
          children: [
            const Text('首次克隆仓库并创建个人分支：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeBlock(
              'git clone https://gitee.com/chzuczldl/cg1-sclspdi.git\n'
              'cd cg1-sclspdi\n'
              'git checkout -b feat-cjn\n'
              'git push -u origin feat-cjn'
            ),
            const SizedBox(height: 12),
            const Text('日常提交流程：',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _buildCodeBlock(
              'git add .\n'
              'git commit -m "feat: 完成实验一开发环境搭建"\n'
              'git push'
            ),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ── 辅助构建方法 ────────────────────────────────────────────────────────

  static Widget _buildGuideCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required Color cardColor,
    required List<Widget> children,
  }) {
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  static Widget _buildRuleItem(
      String label, String desc, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label  ',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: color),
                  ),
                  TextSpan(
                    text: desc,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildCodeExample(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 12, height: 1.4)),
      ),
    );
  }

  static Widget _buildCodeBlock(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        code,
        style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Color(0xFF89DDFF),
            height: 1.5),
      ),
    );
  }

  static Widget _buildTypeChip(String type, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(type,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 10),
          Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4: Gitee 设置
// ══════════════════════════════════════════════════════════════════════════════

class _GiteeSettingsTab extends StatefulWidget {
  final GiteeService gitee;
  const _GiteeSettingsTab({required this.gitee});

  @override
  State<_GiteeSettingsTab> createState() => _GiteeSettingsTabState();
}

class _GiteeSettingsTabState extends State<_GiteeSettingsTab> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;
  DateTime? _lastSyncTime;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final token = await widget.gitee.getToken();
    if (token != null) {
      _tokenController.text = token;
    }
    // 加载同步时间
    final syncTime = await CourseResourceService().getLastSyncTime();
    if (mounted) {
      setState(() => _lastSyncTime = syncTime);
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    await widget.gitee.saveToken(token);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('令牌已保存'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // 先保存
      await _saveToken();
      final user = await widget.gitee.testConnection();
      final name = user['name'] ?? user['login'] ?? '未知';
      setState(() {
        _isTesting = false;
        _testSuccess = true;
        _testResult = '连接成功！用户: $name';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = '连接失败: $e';
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _clearCacheAndReload() async {
    setState(() => _isClearing = true);
    try {
      await CourseResourceService().clearCache();
      if (mounted) {
        setState(() {
          _isClearing = false;
          _lastSyncTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('缓存已清除，下次访问将重新同步'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradient = AppGradientTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 说明卡片
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: gradient.linearGradient,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Gitee 配置说明',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    '• 系统资源从 mad-data 仓库读取（实验/课件/考核配置）\n'
                    '• 学生仓库从 chzuczldl 企业读取（cg1-/cg2-/cg3- 前缀）\n'
                    '• 每个仓库使用 feat-姓名拼音首字母小写 标识学生\n'
                    '• 需要有企业仓库的读取权限\n'
                    '• 详见「提交规范」Tab',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Token 输入
          const Text('Gitee 私人令牌 (Personal Access Token)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            decoration: InputDecoration(
              hintText: '请输入 Gitee 私人令牌',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                        _obscureToken ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                  IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _saveToken,
                    tooltip: '保存',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '获取方式：Gitee → 设置 → 私人令牌 → 生成新令牌（勾选 projects 权限）',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // 测试连接
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(_isTesting ? '测试中...' : '测试连接'),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testSuccess ? Colors.green : Colors.red)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (_testSuccess ? Colors.green : Colors.red)
                        .withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess ? Icons.check_circle : Icons.error,
                    color: _testSuccess ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_testResult!,
                        style: TextStyle(
                            color: _testSuccess ? Colors.green[700] : Colors.red[700],
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // 仓库配置信息
          const Text('仓库配置', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildConfigItem('系统资源仓库', 'osgisOne/mad-data'),
          _buildConfigItem('企业命名空间', 'chzuczldl (滁州学院-刘东良)'),
          _buildConfigItem('学生仓库前缀', 'cg1-, cg2-, cg3-'),
          _buildConfigItem('分支命名规范', 'feat-{姓名拼音首字母小写}'),

          const SizedBox(height: 24),

          // 同步状态
          const Text('数据同步', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _lastSyncTime != null
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        size: 18,
                        color: _lastSyncTime != null
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastSyncTime != null
                              ? '上次同步: ${_formatSyncTime(_lastSyncTime!)}'
                              : '尚未同步远程数据',
                          style: TextStyle(
                            fontSize: 13,
                            color: _lastSyncTime != null
                                ? Colors.green[700]
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '系统启动时自动从 Gitee 同步课程配置（实验/章节/考核方案），'
                    '缓存有效期1小时。如需立即刷新，可清除缓存。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isClearing ? null : _clearCacheAndReload,
                      icon: _isClearing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_sweep, size: 18),
                      label: Text(_isClearing ? '清除中...' : '清除所有缓存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSyncTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildConfigItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
