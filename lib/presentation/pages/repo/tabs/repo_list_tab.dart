part of '../git_repo_page.dart';

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
                  color: color.withOpacity(0.15),
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
          padding: const EdgeInsets.all(10),
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
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
              if (humanName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(humanName,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ],
              const SizedBox(height: 6),
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
        Icon(icon, size: 14, color: color.withOpacity(0.7)),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2: 学生详情（仓库分支 + 提交记录）
// ══════════════════════════════════════════════════════════════════════════════

