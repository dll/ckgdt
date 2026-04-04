import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/user_model.dart';
import '../../../services/gitee_service.dart';

/// 学生详情页 — 展示学生 Gitee 仓库信息、提交记录等
class StudentDetailPage extends StatefulWidget {
  final UserModel student;

  const StudentDetailPage({super.key, required this.student});

  @override
  State<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<StudentDetailPage> {
  final GiteeService _giteeService = GiteeService();

  bool _isLoading = true;
  String? _errorMessage;

  // 仓库信息
  Map<String, dynamic>? _repoDetail;
  List<Map<String, dynamic>> _commits = [];
  List<Map<String, dynamic>> _branches = [];

  // 解析后的 owner / repo
  String? _owner;
  String? _repo;

  @override
  void initState() {
    super.initState();
    _parseAndLoad();
  }

  void _parseAndLoad() {
    final url = widget.student.repositoryUrl;
    if (url == null || url.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '该学生未配置 Gitee 仓库地址';
      });
      return;
    }

    final parsed = GiteeService.parseRepoUrl(url);
    if (parsed == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = '无法解析仓库地址: $url';
      });
      return;
    }

    _owner = parsed.owner;
    _repo = parsed.repo;
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 并行加载仓库详情、提交和分支
      final results = await Future.wait([
        _giteeService.getRepoDetail(_owner!, _repo!),
        _giteeService.getCommits(_owner!, _repo!, perPage: 30),
        _giteeService.getBranches(_owner!, _repo!),
      ]);

      if (mounted) {
        setState(() {
          _repoDetail = results[0] as Map<String, dynamic>;
          _commits =
              results[1] as List<Map<String, dynamic>>;
          _branches =
              results[2] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '加载仓库数据失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final studentName = widget.student.realName ?? widget.student.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text('$studentName 的仓库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _loadAllData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStudentInfoCard(theme),
                      const SizedBox(height: 16),
                      if (_repoDetail != null) _buildRepoCard(theme),
                      const SizedBox(height: 16),
                      _buildStatsRow(theme),
                      const SizedBox(height: 16),
                      _buildBranchesCard(theme),
                      const SizedBox(height: 16),
                      _buildCommitsCard(theme),
                    ],
                  ),
                ),
    );
  }

  // ── 错误视图 ──────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700], fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAllData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 学生信息卡 ──────────────────────────────────────────────────────

  Widget _buildStudentInfoCard(ThemeData theme) {
    final student = widget.student;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.purple,
              child: Text(
                (student.realName ?? student.userId).substring(0, 1),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.realName ?? student.userId,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '学号: ${student.userId}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  if (student.repositoryUrl != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.link, size: 14, color: Colors.blue[700]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            student.repositoryUrl!,
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue[700]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 仓库信息卡 ──────────────────────────────────────────────────────

  Widget _buildRepoCard(ThemeData theme) {
    final repo = _repoDetail!;
    final language = repo['language'] ?? '未知';
    final description = repo['description'] ?? '暂无描述';
    final createdAt = _formatDate(repo['created_at']);
    final updatedAt = _formatDate(repo['updated_at']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, color: Colors.green[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    repo['full_name'] ?? '$_owner/$_repo',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _infoChip(Icons.code, '语言', language, Colors.blue),
                _infoChip(Icons.star_outline, 'Stars',
                    '${repo['stargazers_count'] ?? 0}', Colors.amber),
                _infoChip(Icons.call_split, 'Forks',
                    '${repo['forks_count'] ?? 0}', Colors.green),
                _infoChip(Icons.visibility_outlined, 'Watches',
                    '${repo['watchers_count'] ?? 0}', Colors.purple),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _dateInfo('创建时间', createdAt),
                ),
                Expanded(
                  child: _dateInfo('最后更新', updatedAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text('$label: ',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _dateInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ── 统计行 ──────────────────────────────────────────────────────────

  Widget _buildStatsRow(ThemeData theme) {
    // 统计近 7 天和近 30 天的提交
    final now = DateTime.now();
    int last7 = 0;
    int last30 = 0;

    for (final commit in _commits) {
      final dateStr = commit['commit']?['committer']?['date'] ??
          commit['commit']?['author']?['date'];
      if (dateStr != null) {
        try {
          final date = DateTime.parse(dateStr);
          final diff = now.difference(date).inDays;
          if (diff <= 7) last7++;
          if (diff <= 30) last30++;
        } catch (_) {}
      }
    }

    return Row(
      children: [
        Expanded(
          child: _statCard(
            '总提交数',
            '${_commits.length}${_commits.length >= 30 ? '+' : ''}',
            Icons.commit,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            '近7天提交',
            '$last7',
            Icons.trending_up,
            last7 > 0 ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            '分支数',
            '${_branches.length}',
            Icons.account_tree,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // ── 分支卡 ──────────────────────────────────────────────────────────

  Widget _buildBranchesCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree, color: Colors.purple[700]),
                const SizedBox(width: 8),
                Text(
                  '分支 (${_branches.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_branches.isEmpty)
              const Text('暂无分支信息', style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _branches.map((branch) {
                  final name = branch['name'] ?? '';
                  final isDefault = name == 'master' || name == 'main';
                  return Chip(
                    avatar: Icon(
                      isDefault ? Icons.star : Icons.account_tree_outlined,
                      size: 16,
                      color: isDefault ? Colors.amber : Colors.grey[600],
                    ),
                    label: Text(name),
                    backgroundColor: isDefault
                        ? Colors.amber.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    side: BorderSide(
                      color: isDefault
                          ? Colors.amber.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ── 提交列表卡 ──────────────────────────────────────────────────────

  Widget _buildCommitsCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '最近提交 (${_commits.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_commits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child:
                    Center(child: Text('暂无提交记录', style: TextStyle(color: Colors.grey))),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _commits.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final commit = _commits[index];
                  return _buildCommitItem(commit);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommitItem(Map<String, dynamic> commit) {
    final commitData = commit['commit'] as Map<String, dynamic>? ?? {};
    final message = commitData['message'] ?? '无提交信息';
    final author = commitData['author'] as Map<String, dynamic>? ?? {};
    final authorName = author['name'] ?? '未知';
    final dateStr = author['date'];
    final sha = (commit['sha'] as String?)?.substring(0, 7) ?? '';

    String formattedDate = '';
    String relativeDate = '';
    if (dateStr != null) {
      try {
        final date = DateTime.parse(dateStr);
        formattedDate = DateFormat('MM-dd HH:mm').format(date);
        relativeDate = _relativeTime(date);
      } catch (_) {
        formattedDate = dateStr;
      }
    }

    // 取提交信息的第一行
    final firstLine = message.toString().split('\n').first;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 提交点标记
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.blue[700],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstLine,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // SHA
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sha,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 作者
                    Icon(Icons.person_outline,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 2),
                    Text(
                      authorName,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const Spacer(),
                    // 时间
                    Text(
                      relativeDate.isNotEmpty ? relativeDate : formattedDate,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 工具方法 ──────────────────────────────────────────────────────

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '未知';
    try {
      final date = DateTime.parse(dateStr.toString());
      return DateFormat('yyyy-MM-dd HH:mm').format(date);
    } catch (_) {
      return dateStr.toString();
    }
  }

  String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}个月前';
    return '${diff.inDays ~/ 365}年前';
  }
}
