part of '../git_repo_page.dart';

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
// Tab 3: 统计概览（仓库统计 + 数据流审计）
// ══════════════════════════════════════════════════════════════════════════════
