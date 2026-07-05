part of '../lab_tasks_page.dart';

class _RepoReportTab extends StatefulWidget {
  const _RepoReportTab();

  @override
  State<_RepoReportTab> createState() => _RepoReportTabState();
}

class _RepoReportTabState extends State<_RepoReportTab>
    with AutomaticKeepAliveClientMixin {
  final _giteeService = GiteeService();

  bool _isLoading = true;
  String? _errorMessage;
  List<_RepoReportItem> _repoItems = [];

  // 汇总
  int _totalStudents = 0;
  int _totalCommits = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRepoReport();
  }

  Future<void> _loadRepoReport() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _giteeService.getToken();
      final owner = await _giteeService.getDefaultOwner();
      final prefix = await _giteeService.getRepoPrefix();
      // 默认只显示实验班组仓库
      final effectivePrefix =
          (prefix == null || prefix.isEmpty) ? 'cg1-,cg2-,cg3-' : prefix;

      if (token == null || token.isEmpty || owner == null || owner.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '请先在「仓库分析」页面配置 Gitee Token 和用户名';
        });
        return;
      }

      // 获取仓库列表
      final allRepos = await _giteeService.getMyRepos(perPage: 100);
      final filteredRepos =
          _giteeService.filterReposByPrefix(allRepos, effectivePrefix);

      if (filteredRepos.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '没有匹配前缀 "$effectivePrefix" 的仓库';
        });
        return;
      }

      final items = <_RepoReportItem>[];
      int totalStudents = 0;
      int totalCommits = 0;

      for (final repo in filteredRepos) {
        final repoName = repo['name']?.toString() ?? '';
        // Gitee API 路径需要 path（URL 安全的小写名称），而非 name（显示名）
        final repoPath = repo['path']?.toString() ?? repoName;
        final fullName = repo['full_name']?.toString() ?? '';
        // 从 full_name 解析 owner（full_name 格式: owner_path/repo_path）
        final repoOwner = fullName.contains('/')
            ? fullName.split('/').first
            : ((repo['owner'] as Map?)?['login']?.toString() ?? owner);

        debugPrint(
            '_RepoReportTab: loading $repoName path=$repoPath owner=$repoOwner (full=$fullName)');

        try {
          // 并行获取提交和分支，每个调用单独容错
          final results = await Future.wait([
            _giteeService
                .getCommits(repoOwner, repoPath, perPage: 100)
                .catchError((_) => <Map<String, dynamic>>[]),
            _giteeService
                .getBranches(repoOwner, repoPath)
                .catchError((_) => <Map<String, dynamic>>[]),
          ]);

          var commits = results[0];
          var branches = results[1];

          // 用于 getRepoMembers 的 effectiveOwner
          var effectiveOwner = repoOwner;

          // 如果全部返回空且 owner 可能不对，尝试用 namespace.path 重试
          if (commits.isEmpty && branches.isEmpty) {
            final nsPath = (repo['namespace'] as Map?)?['path']?.toString();
            final ownerLogin = (repo['owner'] as Map?)?['login']?.toString();
            final altOwner = nsPath != null && nsPath != repoOwner
                ? nsPath
                : (ownerLogin != null && ownerLogin != repoOwner
                    ? ownerLogin
                    : null);
            if (altOwner != null) {
              debugPrint(
                  '_RepoReportTab: retrying $repoPath with altOwner=$altOwner');
              effectiveOwner = altOwner;
              final retryResults = await Future.wait([
                _giteeService
                    .getCommits(altOwner, repoPath, perPage: 100)
                    .catchError((_) => <Map<String, dynamic>>[]),
                _giteeService
                    .getBranches(altOwner, repoPath)
                    .catchError((_) => <Map<String, dynamic>>[]),
              ]);
              commits = retryResults[0];
              branches = retryResults[1];
            }
          }

          // 获取成员（多策略容错，传入 commits 作为兜底数据源）
          final collaborators = await _giteeService
              .getRepoMembers(effectiveOwner, repoPath, commits: commits)
              .catchError((_) => <Map<String, dynamic>>[]);

          // 从提交记录中提取 unique 作者
          final authorSet = <String>{};
          for (final c in commits) {
            final authorName =
                (c['commit'] as Map?)?['author']?['name']?.toString();
            if (authorName != null && authorName.isNotEmpty) {
              authorSet.add(authorName);
            }
          }

          // 最近一次提交时间
          String? lastCommitDate;
          if (commits.isNotEmpty) {
            final dateStr = (commits.first['commit'] as Map?)?['committer']
                    ?['date']
                ?.toString();
            if (dateStr != null) {
              try {
                final dt = DateTime.parse(dateStr);
                lastCommitDate =
                    DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
              } catch (e, st) {
                swallowDebug(e, tag: 'RepoReportTab.parseDate', stack: st);
                lastCommitDate = dateStr;
              }
            }
          }

          // 最近 7 天提交数
          final now = DateTime.now();
          final weekAgo = now.subtract(const Duration(days: 7));
          int recentCommits = 0;
          for (final c in commits) {
            final dateStr =
                (c['commit'] as Map?)?['committer']?['date']?.toString();
            if (dateStr != null) {
              try {
                final dt = DateTime.parse(dateStr);
                if (dt.isAfter(weekAgo)) recentCommits++;
              } catch (e, st) {
                swallowDebug(e, tag: 'RepoReportTab.parseWeekAgo', stack: st);
              }
            }
          }

          final memberCount = collaborators.length;
          final commitCount = commits.length;

          totalStudents += memberCount;
          totalCommits += commitCount;

          // 如果全部为空，标记为部分加载失败
          final partialError =
              commits.isEmpty && branches.isEmpty ? '无法获取提交/分支数据（可能无权限）' : null;

          items.add(_RepoReportItem(
            repoName: repoName,
            repoPath: repoPath,
            fullName: fullName,
            memberCount: memberCount,
            commitCount: commitCount,
            branchCount: branches.length,
            authorCount: authorSet.length,
            recentCommits: recentCommits,
            lastCommitDate: lastCommitDate,
            description: repo['description']?.toString(),
            htmlUrl: repo['html_url']?.toString(),
            error: partialError,
          ));
        } catch (e) {
          debugPrint('_RepoReportTab: error loading $repoName: $e');
          items.add(_RepoReportItem(
            repoName: repoName,
            repoPath: repoPath,
            fullName: fullName,
            memberCount: 0,
            commitCount: 0,
            branchCount: 0,
            authorCount: 0,
            recentCommits: 0,
            lastCommitDate: null,
            description: repo['description']?.toString(),
            htmlUrl: repo['html_url']?.toString(),
            error: e.toString(),
          ));
        }
      }

      // 按提交数降序排列
      items.sort((a, b) => b.commitCount.compareTo(a.commitCount));

      if (!mounted) return;
      setState(() {
        _repoItems = items;
        _totalStudents = totalStudents;
        _totalCommits = totalCommits;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '加载仓库报表失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载仓库报表...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRepoReport,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRepoReport,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 汇总卡片 ──
          _buildSummaryCard(),
          const SizedBox(height: 16),

          // ── 各仓库列表 ──
          ..._repoItems.map(_buildRepoCard),
        ],
      ),
    );
  }

  // ── 汇总卡片 ──────────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    final avgCommits =
        _repoItems.isEmpty ? 0.0 : _totalCommits / _repoItems.length;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [Colors.indigo.shade400, Colors.indigo.shade700],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '仓库报表总览',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildSummaryItem(
                  Icons.folder,
                  '${_repoItems.length}',
                  '仓库数',
                ),
                _buildSummaryItem(
                  Icons.people,
                  '$_totalStudents',
                  '总成员',
                ),
                _buildSummaryItem(
                  Icons.commit,
                  '$_totalCommits',
                  '总提交',
                ),
                _buildSummaryItem(
                  Icons.trending_up,
                  avgCommits.toStringAsFixed(1),
                  '平均提交',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  // ── 仓库卡片 ──────────────────────────────────────────────────────────────

  Widget _buildRepoCard(_RepoReportItem item) {
    final hasError = item.error != null;
    // 区分：是完全加载失败(404)还是部分数据缺失(无权限)
    final isFatalError = hasError &&
        item.commitCount == 0 &&
        item.branchCount == 0 &&
        item.memberCount == 0 &&
        item.error!.contains('GiteeApiException');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final owner =
              item.fullName.contains('/') ? item.fullName.split('/').first : '';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RepoDetailPage(
                owner: owner,
                repoName: item.repoPath,
                description: item.description,
                htmlUrl: item.htmlUrl,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 仓库名 + 描述
              Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: isFatalError
                        ? Colors.red
                        : (hasError ? Colors.orange : Colors.indigo),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.repoName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isFatalError ? Colors.red : null,
                      ),
                    ),
                  ),
                  if (item.recentCommits > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '近7天 ${item.recentCommits} 提交',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (!hasError)
                    Icon(Icons.chevron_right,
                        color: Colors.grey[400], size: 20),
                  if (hasError)
                    Icon(Icons.chevron_right,
                        color: Colors.grey[400], size: 20),
                ],
              ),

              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.description!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              if (hasError) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                        isFatalError
                            ? Icons.error_outline
                            : Icons.warning_amber,
                        size: 14,
                        color: isFatalError ? Colors.red : Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.error!,
                        style: TextStyle(
                            fontSize: 11,
                            color: isFatalError ? Colors.red : Colors.orange),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              // 统计行 — 始终显示
              Row(
                children: [
                  _buildRepoStatChip(
                    Icons.people_outline,
                    '${item.memberCount}',
                    '成员',
                    Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  _buildRepoStatChip(
                    Icons.commit,
                    '${item.commitCount}',
                    '提交',
                    Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  _buildRepoStatChip(
                    Icons.call_split,
                    '${item.branchCount}',
                    '分支',
                    Colors.teal,
                  ),
                  const SizedBox(width: 12),
                  _buildRepoStatChip(
                    Icons.person_outline,
                    '${item.authorCount}',
                    '贡献者',
                    Colors.purple,
                  ),
                ],
              ),

              if (item.lastCommitDate != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '最近提交: ${item.lastCommitDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepoStatChip(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 仓库报表数据模型 ────────────────────────────────────────────────────────

class _RepoReportItem {
  final String repoName; // 显示名称 (e.g. CG1-CIFMS)
  final String repoPath; // API 路径 (e.g. cg1cifms)
  final String fullName;
  final int memberCount;
  final int commitCount;
  final int branchCount;
  final int authorCount;
  final int recentCommits;
  final String? lastCommitDate;
  final String? description;
  final String? htmlUrl;
  final String? error;

  const _RepoReportItem({
    required this.repoName,
    required this.repoPath,
    required this.fullName,
    required this.memberCount,
    required this.commitCount,
    required this.branchCount,
    required this.authorCount,
    required this.recentCommits,
    this.lastCommitDate,
    this.description,
    this.htmlUrl,
    this.error,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab: 实验材料（4 类材料浏览 + 下载 + 预览 + AI 智能体）
// ══════════════════════════════════════════════════════════════════════════════

/// 实验材料的 4 个分类及其 asset 路径
