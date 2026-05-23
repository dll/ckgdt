part of '../lab_tasks_page.dart';

class _StudentRepoTab extends StatefulWidget {
  final AuthService authService;
  const _StudentRepoTab({required this.authService});

  @override
  State<_StudentRepoTab> createState() => _StudentRepoTabState();
}

class _StudentRepoTabState extends State<_StudentRepoTab>
    with AutomaticKeepAliveClientMixin {
  final _giteeService = GiteeService();
  final _resource = CourseResourceService();

  bool _isLoading = true;
  String? _errorMessage;

  // 仓库详情
  Map<String, dynamic>? _repoDetail;
  String _owner = '';
  String _repoName = '';

  // 统计
  int _totalCommits = 0;
  int _totalAdditions = 0;
  int _totalDeletions = 0;
  int _totalFilesChanged = 0;

  // 数据
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _collaborators = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _releases = [];
  List<_StudentCommitRow> _commitRows = [];

  // 分支筛选
  String? _selectedBranch;
  bool _loadingBranch = false;

  // 加载统计进度
  bool _loadingStats = false;
  double _statsProgress = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRepoData();
  }

  Future<void> _loadRepoData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = widget.authService.currentUser;
    String? repoUrl = user?.repositoryUrl;

    // 如果 repositoryUrl 指向非 chzuczldl 命名空间，自动纠正
    if (repoUrl != null && repoUrl.isNotEmpty) {
      final parsed = GiteeService.parseRepoUrl(repoUrl);
      if (parsed != null &&
          parsed.owner.toLowerCase() !=
              CourseResourceService.enterprise.toLowerCase()) {
        // 替换为 chzuczldl 命名空间下的同名仓库
        repoUrl =
            'https://gitee.com/${CourseResourceService.enterprise}/${parsed.repo}';
        debugPrint(
            'StudentRepoTab: 纠正仓库 URL → $repoUrl (原: ${user?.repositoryUrl})');
      }
    }

    // 如果 repositoryUrl 未配置，尝试通过学号/姓名自动匹配
    if (repoUrl == null || repoUrl.isEmpty) {
      final userId = user?.userId ?? '';
      final realName = user?.realName ?? '';

      try {
        final myRepos = await _resource.getStudentOwnRepos(
          userId: userId,
          realName: realName,
        );

        if (myRepos.isNotEmpty) {
          // 自动使用匹配到的第一个仓库
          repoUrl = myRepos.first['html_url']?.toString();
        }
      } catch (_) {}

      if (repoUrl == null || repoUrl.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '尚未配置 Gitee 仓库地址，且无法自动识别所属仓库。\n'
              '请联系教师在「学生管理」中设置你的仓库 URL。';
        });
        return;
      }
    }

    // 解析仓库 URL
    final parsed = GiteeService.parseRepoUrl(repoUrl);
    if (parsed == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '仓库 URL 格式无效: $repoUrl';
      });
      return;
    }

    _owner = parsed.owner;
    _repoName = parsed.repo;

    try {
      final token = await _giteeService.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Gitee Token 未配置，请联系教师配置。';
        });
        return;
      }

      // 先并行获取详情、分支、提交、releases
      final results = await Future.wait([
        _giteeService.getRepoDetail(_owner, _repoName),
        _giteeService.getBranches(_owner, _repoName),
        _giteeService.getAllCommits(_owner, _repoName),
        _giteeService
            .getReleases(_owner, _repoName)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final repoDetail = results[0] as Map<String, dynamic>;
      final branches = results[1] as List<Map<String, dynamic>>;
      final commits = results[2] as List<Map<String, dynamic>>;
      final releases = results[3] as List<Map<String, dynamic>>;

      // 获取成员（多策略容错，传入 commits 作为兜底数据源）
      final collaborators = await _giteeService
          .getRepoMembers(_owner, _repoName, commits: commits)
          .catchError((_) => <Map<String, dynamic>>[]);

      final commitRows = commits.map((c) {
        final sha = c['sha']?.toString() ?? '';
        final commitMap = c['commit'] as Map<String, dynamic>? ?? {};
        final authorMap = commitMap['author'] as Map<String, dynamic>? ?? {};
        final message = commitMap['message']?.toString() ?? '';
        final dateStr = authorMap['date']?.toString();
        DateTime? date;
        if (dateStr != null) {
          try {
            date = DateTime.parse(dateStr).toLocal();
          } catch (_) {}
        }
        return _StudentCommitRow(
          sha: sha,
          message: message.split('\n').first,
          date: date,
          authorName: authorMap['name']?.toString() ?? '',
        );
      }).toList();

      setState(() {
        _repoDetail = repoDetail;
        _branches = branches;
        _collaborators = collaborators;
        _releases = releases;
        _commitRows = commitRows;
        _totalCommits = commits.length;
        _isLoading = false;
      });

      _loadCommitStats(commits);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载仓库数据失败: $e';
      });
    }
  }

  Future<void> _loadCommitStats(List<Map<String, dynamic>> commits) async {
    if (commits.isEmpty) return;
    setState(() => _loadingStats = true);

    int totalAdd = 0, totalDel = 0, totalFiles = 0;
    final maxLoad = commits.length > 50 ? 50 : commits.length;

    for (int i = 0; i < maxLoad; i++) {
      final sha = commits[i]['sha']?.toString() ?? '';
      if (sha.isEmpty) continue;
      try {
        final detail =
            await _giteeService.getCommitDetail(_owner, _repoName, sha);
        final stats = detail['stats'] as Map<String, dynamic>? ?? {};
        final add = (stats['additions'] as int?) ?? 0;
        final del = (stats['deletions'] as int?) ?? 0;
        final files = detail['files'] as List?;
        totalAdd += add;
        totalDel += del;
        totalFiles += (files?.length ?? 0);

        if (i < _commitRows.length) {
          _commitRows[i] = _commitRows[i].copyWith(
            additions: add,
            deletions: del,
            filesChanged: files?.length ?? 0,
          );
        }
        if (i % 5 == 0 || i == maxLoad - 1) {
          setState(() {
            _totalAdditions = totalAdd;
            _totalDeletions = totalDel;
            _totalFilesChanged = totalFiles;
            _statsProgress = (i + 1) / maxLoad;
          });
        }
      } catch (_) {}
    }
    setState(() => _loadingStats = false);
  }

  Future<void> _switchBranch(String? branchName) async {
    if (branchName == _selectedBranch) return;
    setState(() {
      _selectedBranch = branchName;
      _loadingBranch = true;
      _totalAdditions = 0;
      _totalDeletions = 0;
      _totalFilesChanged = 0;
    });

    try {
      final commits =
          await _giteeService.getAllCommits(_owner, _repoName, sha: branchName);
      final commitRows = commits.map((c) {
        final sha = c['sha']?.toString() ?? '';
        final commitMap = c['commit'] as Map<String, dynamic>? ?? {};
        final authorMap = commitMap['author'] as Map<String, dynamic>? ?? {};
        final message = commitMap['message']?.toString() ?? '';
        final dateStr = authorMap['date']?.toString();
        DateTime? date;
        if (dateStr != null) {
          try {
            date = DateTime.parse(dateStr).toLocal();
          } catch (_) {}
        }
        return _StudentCommitRow(
          sha: sha,
          message: message.split('\n').first,
          date: date,
          authorName: authorMap['name']?.toString() ?? '',
        );
      }).toList();
      setState(() {
        _commitRows = commitRows;
        _totalCommits = commits.length;
        _loadingBranch = false;
      });
      _loadCommitStats(commits);
    } catch (e) {
      setState(() => _loadingBranch = false);
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
            Text('正在加载仓库数据...', style: TextStyle(color: Colors.grey)),
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
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRepoData,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final repo = _repoDetail;
    final fullName = repo?['full_name']?.toString() ?? '$_owner/$_repoName';
    final desc = repo?['description']?.toString() ?? '';
    final language = repo?['language']?.toString();
    final stars = repo?['stargazers_count'] ?? 0;
    final forks = repo?['forks_count'] ?? 0;
    final htmlUrl = repo?['html_url']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: _loadRepoData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 仓库头部 ──
          Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.indigo.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_special,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(fullName,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(desc,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (language != null) _chipWhite(Icons.code, language),
                      _chipWhite(Icons.star_border, '$stars'),
                      _chipWhite(Icons.call_split, '$forks'),
                      _chipWhite(
                          Icons.people_outline, '${_collaborators.length} 成员'),
                    ],
                  ),
                  if (htmlUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(htmlUrl,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                            decoration: TextDecoration.underline)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 4 统计卡片 ──
          Row(
            children: [
              _statCard('提交次数', '$_totalCommits', Colors.blue, Icons.commit),
              const SizedBox(width: 8),
              _statCard(
                  '新增行数',
                  _loadingStats ? '...' : _fmtNum(_totalAdditions),
                  Colors.green,
                  Icons.add_circle_outline),
              const SizedBox(width: 8),
              _statCard(
                  '删除行数',
                  _loadingStats ? '...' : _fmtNum(_totalDeletions),
                  Colors.red,
                  Icons.remove_circle_outline),
              const SizedBox(width: 8),
              _statCard(
                  '修改文件',
                  _loadingStats ? '...' : _fmtNum(_totalFilesChanged),
                  Colors.cyan,
                  Icons.description_outlined),
            ],
          ),
          if (_loadingStats) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _statsProgress),
            const SizedBox(height: 4),
            Text('正在加载提交统计... ${(_statsProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),

          // ── 成员列表 ──
          _buildMembersCard(),
          const SizedBox(height: 16),

          // ── 分支列表 ──
          _buildBranchCard(),
          const SizedBox(height: 16),

          // ── 提交记录 (带分支切换) ──
          _buildCommitSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _chipWhite(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white60),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  Widget _statCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 2,
        color: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: Colors.white70, size: 22),
              const SizedBox(height: 6),
              Text(title,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembersCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.people, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text('仓库成员 (${_collaborators.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (_collaborators.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无成员数据', style: TextStyle(color: Colors.grey)))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _collaborators.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final m = _collaborators[i];
                final login = m['login']?.toString() ?? '';
                final name = m['name']?.toString() ?? login;
                final avatar = m['avatar_url']?.toString();
                final isAdmin = m['permissions']?['admin'] == true;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null
                        ? Text(name.isNotEmpty ? name[0] : '?')
                        : null,
                  ),
                  title: Text(name),
                  subtitle: Text(login, style: const TextStyle(fontSize: 12)),
                  trailing: isAdmin
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('管理员',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.orange)),
                        )
                      : const Text('成员',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBranchCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 18, color: Colors.teal),
                const SizedBox(width: 8),
                Text('分支列表 (${_branches.length})',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (_branches.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无分支数据', style: TextStyle(color: Colors.grey)))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _branches.map((b) {
                final name = b['name']?.toString() ?? '';
                final isSelected = _selectedBranch == name;
                final isDefault = name == 'master' || name == 'main';
                Color color = Colors.grey;
                if (isDefault)
                  color = Colors.blue;
                else if (name == 'develop')
                  color = Colors.cyan;
                else if (name.startsWith('feature'))
                  color = Colors.orange;
                else if (name == 'release') color = Colors.green;

                return Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: ActionChip(
                    label: Text(name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        )),
                    backgroundColor:
                        isSelected ? color : color.withValues(alpha: 0.1),
                    side: BorderSide(color: color.withValues(alpha: 0.3)),
                    onPressed: () => _switchBranch(isSelected ? null : name),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCommitSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Text('提交记录 ($_totalCommits)',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                if (_loadingBranch) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
                const Spacer(),
                if (_selectedBranch != null)
                  Chip(
                    label: Text(_selectedBranch!,
                        style: const TextStyle(fontSize: 11)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _switchBranch(null),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          if (_commitRows.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无提交记录', style: TextStyle(color: Colors.grey)))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 52,
                columns: const [
                  DataColumn(
                      label: Text('SHA',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('日期',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('作者',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('消息',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                      label: Text('新增',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('删除',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                  DataColumn(
                      label: Text('文件',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: true),
                ],
                rows: _commitRows.map((c) {
                  final shortSha =
                      c.sha.length > 7 ? c.sha.substring(0, 7) : c.sha;
                  final dateStr = c.date != null
                      ? DateFormat('MM-dd HH:mm').format(c.date!)
                      : '-';
                  return DataRow(cells: [
                    DataCell(Text(shortSha,
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.blue))),
                    DataCell(
                        Text(dateStr, style: const TextStyle(fontSize: 12))),
                    DataCell(Text(c.authorName,
                        style: const TextStyle(fontSize: 12))),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(c.message,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(c.additions != null
                        ? Text('+${c.additions}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green))
                        : const Text('-',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey))),
                    DataCell(c.deletions != null
                        ? Text('-${c.deletions}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red))
                        : const Text('-',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey))),
                    DataCell(Text(
                        c.filesChanged != null ? '${c.filesChanged}' : '-',
                        style: const TextStyle(fontSize: 12))),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtNum(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _StudentCommitRow {
  final String sha;
  final String message;
  final DateTime? date;
  final String authorName;
  final int? additions;
  final int? deletions;
  final int? filesChanged;

  const _StudentCommitRow({
    required this.sha,
    required this.message,
    this.date,
    required this.authorName,
    this.additions,
    this.deletions,
    this.filesChanged,
  });

  _StudentCommitRow copyWith(
      {int? additions, int? deletions, int? filesChanged}) {
    return _StudentCommitRow(
      sha: sha,
      message: message,
      date: date,
      authorName: authorName,
      additions: additions ?? this.additions,
      deletions: deletions ?? this.deletions,
      filesChanged: filesChanged ?? this.filesChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 5: 仓库报表（教师/管理员）
// ═══════════════════════════════════════════════════════════════════════════════

