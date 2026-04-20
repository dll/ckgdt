import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/gitee_service.dart';

/// 仓库详情页（参照 毕设进度管家 /student/:id 页面）
/// 显示：仓库基本信息 / 4个统计卡片 / 分支列表 / 发布版本 / 提交记录表格
class RepoDetailPage extends StatefulWidget {
  final String owner;
  final String repoName;
  final String? description;
  final String? htmlUrl;

  const RepoDetailPage({
    super.key,
    required this.owner,
    required this.repoName,
    this.description,
    this.htmlUrl,
  });

  @override
  State<RepoDetailPage> createState() => _RepoDetailPageState();
}

class _RepoDetailPageState extends State<RepoDetailPage> {
  final _giteeService = GiteeService();

  bool _isLoading = true;
  String? _errorMessage;

  // 仓库详情
  Map<String, dynamic>? _repoDetail;

  // 统计
  int _totalCommits = 0;
  int _totalAdditions = 0;
  int _totalDeletions = 0;
  int _totalFilesChanged = 0;

  // 数据列表
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _releases = [];
  List<Map<String, dynamic>> _collaborators = [];
  List<_CommitRow> _commitRows = [];

  // 分支筛选
  String? _selectedBranch; // null = 全部(默认分支)
  bool _loadingBranchCommits = false;

  // 加载详情进度
  bool _loadingStats = false;
  double _statsProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 并行获取仓库详情、分支、提交、协作者、releases（每个独立容错）
      final results = await Future.wait([
        _giteeService.getRepoDetail(widget.owner, widget.repoName)
            .catchError((_) => <String, dynamic>{}),
        _giteeService.getBranches(widget.owner, widget.repoName)
            .catchError((_) => <Map<String, dynamic>>[]),
        _giteeService.getAllCommits(widget.owner, widget.repoName)
            .catchError((_) => <Map<String, dynamic>>[]),
        _giteeService.getCollaborators(widget.owner, widget.repoName)
            .catchError((_) => <Map<String, dynamic>>[]),
        _giteeService.getReleases(widget.owner, widget.repoName)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final repoDetail = results[0] as Map<String, dynamic>;
      final branches = results[1] as List<Map<String, dynamic>>;
      final commits = results[2] as List<Map<String, dynamic>>;
      final collaborators = results[3] as List<Map<String, dynamic>>;
      final releases = results[4] as List<Map<String, dynamic>>;

      // 如果仓库详情获取失败，尝试用 namespace 中的 path 重试
      if (repoDetail.isEmpty) {
        // 尝试直接用仓库名和 owner 组合，可能 owner 不对
        debugPrint('RepoDetailPage: repoDetail empty for ${widget.owner}/${widget.repoName}');
      }

      // 构建简易 commit 行（无 additions/deletions）
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
        return _CommitRow(
          sha: sha,
          message: message.split('\n').first,
          date: date,
          authorName: authorMap['name']?.toString() ?? '',
        );
      }).toList();

      setState(() {
        _repoDetail = repoDetail;
        _branches = branches;
        _releases = releases;
        _collaborators = collaborators;
        _commitRows = commitRows;
        _totalCommits = commits.length;
        _isLoading = false;
      });

      // 异步加载每条提交的 additions/deletions
      _loadCommitStats(commits);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载仓库详情失败: $e';
      });
    }
  }

  /// 后台逐条获取 commit 的 stats（additions/deletions/files_changed）
  Future<void> _loadCommitStats(List<Map<String, dynamic>> commits) async {
    if (commits.isEmpty) return;
    setState(() => _loadingStats = true);

    int totalAdd = 0, totalDel = 0, totalFiles = 0;
    final maxLoad = commits.length > 100 ? 100 : commits.length;

    for (int i = 0; i < maxLoad; i++) {
      final sha = commits[i]['sha']?.toString() ?? '';
      if (sha.isEmpty) continue;

      try {
        final detail = await _giteeService.getCommitDetail(
          widget.owner, widget.repoName, sha,
        );
        final stats = detail['stats'] as Map<String, dynamic>? ?? {};
        final add = (stats['additions'] as int?) ?? 0;
        final del = (stats['deletions'] as int?) ?? 0;
        final files = detail['files'] as List?;
        final fileCount = files?.length ?? 0;

        totalAdd += add;
        totalDel += del;
        totalFiles += fileCount;

        // 更新对应行
        if (i < _commitRows.length) {
          _commitRows[i] = _commitRows[i].copyWith(
            additions: add,
            deletions: del,
            filesChanged: fileCount,
          );
        }

        // 每5条或最后一条刷新 UI
        if (i % 5 == 0 || i == maxLoad - 1) {
          setState(() {
            _totalAdditions = totalAdd;
            _totalDeletions = totalDel;
            _totalFilesChanged = totalFiles;
            _statsProgress = (i + 1) / maxLoad;
          });
        }
      } catch (e) {
        debugPrint('RepoDetailPage: stat $sha error: $e');
      }
    }

    setState(() => _loadingStats = false);
  }

  /// 切换分支并重新加载该分支的提交记录
  Future<void> _switchBranch(String? branchName) async {
    if (branchName == _selectedBranch) return;
    setState(() {
      _selectedBranch = branchName;
      _loadingBranchCommits = true;
      _totalAdditions = 0;
      _totalDeletions = 0;
      _totalFilesChanged = 0;
    });

    try {
      final commits = await _giteeService.getAllCommits(
        widget.owner, widget.repoName,
        sha: branchName,
      );

      final commitRows = commits.map((c) {
        final sha = c['sha']?.toString() ?? '';
        final commitMap = c['commit'] as Map<String, dynamic>? ?? {};
        final authorMap = commitMap['author'] as Map<String, dynamic>? ?? {};
        final message = commitMap['message']?.toString() ?? '';
        final dateStr = authorMap['date']?.toString();
        DateTime? date;
        if (dateStr != null) {
          try { date = DateTime.parse(dateStr).toLocal(); } catch (_) {}
        }
        return _CommitRow(
          sha: sha,
          message: message.split('\n').first,
          date: date,
          authorName: authorMap['name']?.toString() ?? '',
        );
      }).toList();

      setState(() {
        _commitRows = commitRows;
        _totalCommits = commits.length;
        _loadingBranchCommits = false;
      });

      _loadCommitStats(commits);
    } catch (e) {
      setState(() => _loadingBranchCommits = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载分支提交失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repoName),
        actions: [
          if (widget.htmlUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: '在浏览器中查看',
              onPressed: () => _openUrl(widget.htmlUrl!),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 仓库头部 ──
          _buildRepoHeader(),
          const SizedBox(height: 16),

          // ── 4 统计卡片 ──
          _buildStatCards(),
          if (_loadingStats) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _statsProgress),
            const SizedBox(height: 4),
            Text(
              '正在加载提交统计... ${(_statsProgress * 100).toInt()}%',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),

          // ── 成员列表 ──
          _buildMembersSection(),
          const SizedBox(height: 16),

          // ── 分支列表 + 发布版本（横向排列） ──
          _buildBranchAndReleaseRow(),
          const SizedBox(height: 16),

          // ── 分支切换器 + 提交记录表格 ──
          _buildCommitTable(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 仓库头部
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRepoHeader() {
    final repo = _repoDetail;
    final fullName = repo?['full_name']?.toString() ?? widget.repoName;
    final desc = repo?['description']?.toString() ?? widget.description ?? '';
    final language = repo?['language']?.toString();
    final stars = repo?['stargazers_count'] ?? 0;
    final forks = repo?['forks_count'] ?? 0;
    final watches = repo?['watchers_count'] ?? 0;
    final htmlUrl = repo?['html_url']?.toString() ?? widget.htmlUrl ?? '';
    final createdAt = repo?['created_at']?.toString();
    final updatedAt = repo?['updated_at']?.toString();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            // 仓库名
            Row(
              children: [
                const Icon(Icons.folder_special, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                desc,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 12),

            // 元信息行
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (language != null)
                  _headerChip(Icons.code, language),
                _headerChip(Icons.star_border, '$stars'),
                _headerChip(Icons.call_split, '$forks'),
                _headerChip(Icons.visibility_outlined, '$watches'),
                if (createdAt != null)
                  _headerChip(Icons.calendar_today,
                      '创建: ${_formatDateShort(createdAt)}'),
                if (updatedAt != null)
                  _headerChip(Icons.update,
                      '更新: ${_formatDateShort(updatedAt)}'),
              ],
            ),

            if (htmlUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _openUrl(htmlUrl),
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: htmlUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('仓库链接已复制')),
                  );
                },
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        htmlUrl,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white60),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4 统计卡片
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatCards() {
    return Row(
      children: [
        _statCard('提交次数', '$_totalCommits', Colors.blue, Icons.commit),
        const SizedBox(width: 8),
        _statCard(
          '新增行数',
          _loadingStats ? '...' : _formatNumber(_totalAdditions),
          Colors.green,
          Icons.add_circle_outline,
        ),
        const SizedBox(width: 8),
        _statCard(
          '删除行数',
          _loadingStats ? '...' : _formatNumber(_totalDeletions),
          Colors.red,
          Icons.remove_circle_outline,
        ),
        const SizedBox(width: 8),
        _statCard(
          '修改文件',
          _loadingStats ? '...' : _formatNumber(_totalFilesChanged),
          Colors.cyan,
          Icons.description_outlined,
        ),
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 成员/协作者
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMembersSection() {
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
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.people, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '仓库成员 (${_collaborators.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_collaborators.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无协作者',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _collaborators.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final m = _collaborators[i];
                final login = m['login']?.toString() ?? '';
                final name = m['name']?.toString() ?? login;
                final avatar = m['avatar_url']?.toString();
                final isAdmin =
                    m['permissions']?['admin'] == true;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                    child: avatar == null
                        ? Text(name.isNotEmpty ? name[0] : '?')
                        : null,
                  ),
                  title: Text(name),
                  subtitle: Text(login,
                      style: const TextStyle(fontSize: 12)),
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
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey)),
                );
              },
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 分支列表 + 发布版本
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBranchAndReleaseRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          // 宽屏: 横向排列
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBranchCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildReleaseCard()),
            ],
          );
        }
        // 窄屏: 纵向
        return Column(
          children: [
            _buildBranchCard(),
            const SizedBox(height: 12),
            _buildReleaseCard(),
          ],
        );
      },
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.call_split,
                    size: 18, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  '🌿 分支列表 (${_branches.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (_branches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无分支数据',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _branches.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final b = _branches[i];
                final name = b['name']?.toString() ?? '';
                final isDefault =
                    name == 'master' || name == 'main';
                final commitInfo =
                    b['commit'] as Map<String, dynamic>? ?? {};
                final commitSha =
                    commitInfo['sha']?.toString() ?? '';

                Color badgeColor = Colors.grey;
                if (isDefault) {
                  badgeColor = Colors.blue;
                } else if (name == 'release') {
                  badgeColor = Colors.green;
                } else if (name == 'develop') {
                  badgeColor = Colors.cyan;
                } else if (name.startsWith('feature')) {
                  badgeColor = Colors.orange;
                }

                return ListTile(
                  dense: true,
                  onTap: () => _switchBranch(name),
                  leading: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  title: isDefault
                      ? Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('默认',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        )
                      : null,
                  subtitle: Text(
                    commitSha.length > 7
                        ? commitSha.substring(0, 7)
                        : commitSha,
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReleaseCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.new_releases_outlined,
                    size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  '📦 发布版本 (${_releases.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (_releases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无发布版本',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _releases.length,
              itemBuilder: (_, i) {
                final r = _releases[i];
                final tag = r['tag_name']?.toString() ?? '';
                final name = r['name']?.toString() ?? tag;
                final body = r['body']?.toString() ?? '';
                final createdAt = r['created_at']?.toString();

                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                          color: Colors.green.shade600, width: 4),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                    title: Text(name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (body.isNotEmpty)
                          Text(
                            body.length > 80
                                ? '${body.substring(0, 80)}...'
                                : body,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                        if (createdAt != null)
                          Text(
                            _formatDateShort(createdAt),
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[400]),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 提交记录表格
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCommitTable() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  '提交记录 ($_totalCommits)',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // ── 分支切换下拉 ──
                if (_branches.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBranch ?? '',
                        icon: _loadingBranchCommits
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_drop_down, size: 20),
                        isDense: true,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('全部分支'),
                          ),
                          ..._branches.map((b) {
                            final name = b['name']?.toString() ?? '';
                            return DropdownMenuItem(
                              value: name,
                              child: Text(name),
                            );
                          }),
                        ],
                        onChanged: _loadingBranchCommits
                            ? null
                            : (val) => _switchBranch(
                                val == null || val.isEmpty ? null : val),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_commitRows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无提交记录',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowHeight: 40,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 52,
                columns: const [
                  DataColumn(label: Text('提交哈希',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('日期',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('作者',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('消息',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(
                    label: Text('新增',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('删除',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('文件数',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true,
                  ),
                ],
                rows: _commitRows.map((c) {
                  final shortSha = c.sha.length > 7
                      ? c.sha.substring(0, 7)
                      : c.sha;
                  final dateStr = c.date != null
                      ? DateFormat('yyyy-MM-dd HH:mm').format(c.date!)
                      : '-';

                  return DataRow(cells: [
                    DataCell(
                      GestureDetector(
                        onTap: () {
                          final url =
                              '${widget.htmlUrl ?? "https://gitee.com/${widget.owner}/${widget.repoName}"}/commit/${c.sha}';
                          _openUrl(url);
                        },
                        child: Text(
                          shortSha,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontFamily: 'monospace',
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(dateStr,
                        style: const TextStyle(fontSize: 12))),
                    DataCell(Text(c.authorName,
                        style: const TextStyle(fontSize: 12))),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          c.message,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      c.additions != null
                          ? Text(
                              '+${c.additions}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.green),
                            )
                          : const Text('-',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                    ),
                    DataCell(
                      c.deletions != null
                          ? Text(
                              '-${c.deletions}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.red),
                            )
                          : const Text('-',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                    ),
                    DataCell(
                      Text(
                        c.filesChanged != null ? '${c.filesChanged}' : '-',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 辅助
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatDateShort(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatNumber(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── 提交行数据模型 ────────────────────────────────────────────────────────────

class _CommitRow {
  final String sha;
  final String message;
  final DateTime? date;
  final String authorName;
  final int? additions;
  final int? deletions;
  final int? filesChanged;

  const _CommitRow({
    required this.sha,
    required this.message,
    this.date,
    required this.authorName,
    this.additions,
    this.deletions,
    this.filesChanged,
  });

  _CommitRow copyWith({
    int? additions,
    int? deletions,
    int? filesChanged,
  }) {
    return _CommitRow(
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
