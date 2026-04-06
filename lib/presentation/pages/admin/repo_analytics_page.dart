import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../../services/gitee_service.dart';

/// 仓库成员分析 & 学生进度排行
/// 直接从教师 Gitee 账号拉取仓库，仓库协作者 = 学生
class RepoAnalyticsPage extends StatefulWidget {
  const RepoAnalyticsPage({super.key});

  @override
  State<RepoAnalyticsPage> createState() => _RepoAnalyticsPageState();
}

class _RepoAnalyticsPageState extends State<RepoAnalyticsPage>
    with SingleTickerProviderStateMixin {
  final _giteeService = GiteeService();

  late TabController _tabController;

  bool _isLoading = false;
  bool _isConfigured = false;
  String? _errorMessage;
  double _progress = 0.0;
  String _progressText = '';

  // Gitee 配置
  String _owner = '';
  String _token = '';
  String _repoPrefix = '';

  // 数据
  List<_RepoData> _repos = []; // 所有仓库
  List<_RepoMembersData> _repoMembersList = []; // 每仓库的成员
  List<_AggregatedMember> _allMembers = []; // 汇总去重成员
  List<_StudentProgress> _studentRankings = []; // 学生进度排行

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gitee 配置检查
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkConfig() async {
    final token = await _giteeService.getToken();
    final owner = await _giteeService.getDefaultOwner();
    final prefix = await _giteeService.getRepoPrefix();

    if (token != null && token.isNotEmpty && owner != null && owner.isNotEmpty) {
      setState(() {
        _token = token;
        _owner = owner;
        _repoPrefix = (prefix == null || prefix.isEmpty) ? 'cg1-,cg2-,cg3-' : prefix;
        _isConfigured = true;
      });
      _loadAllData();
    } else {
      setState(() => _isConfigured = false);
      // 自动弹出配置对话框
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showConfigDialog();
      });
    }
  }

  Future<void> _showConfigDialog() async {
    final tokenCtrl = TextEditingController(text: _token);
    final ownerCtrl = TextEditingController(text: _owner);
    final prefixCtrl = TextEditingController(text: _repoPrefix);
    bool testing = false;
    String? testResult;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: _isConfigured,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Gitee 配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '请配置 Gitee 私人令牌和用户名，用于获取仓库和成员信息。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ownerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gitee 用户名/组织名',
                    hintText: '例如: chzuczldl',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gitee 私人令牌',
                    hintText: '在 gitee.com/personal_access_tokens 创建',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prefixCtrl,
                  decoration: const InputDecoration(
                    labelText: '仓库前缀过滤（可选）',
                    hintText: '例如: cg1-,cg2-,cg3-（逗号分隔，留空显示全部）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.filter_list),
                    helperText: '只显示名称以指定前缀开头的仓库',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                if (testResult != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: testResult!.startsWith('✅')
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      testResult!,
                      style: TextStyle(
                        fontSize: 13,
                        color: testResult!.startsWith('✅')
                            ? Colors.green[700]
                            : Colors.red[700],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: testing
                        ? null
                        : () async {
                            if (tokenCtrl.text.trim().isEmpty) {
                              setDialogState(() =>
                                  testResult = '❌ 请输入令牌');
                              return;
                            }
                            setDialogState(() {
                              testing = true;
                              testResult = null;
                            });
                            try {
                              await _giteeService
                                  .saveToken(tokenCtrl.text.trim());
                              final user =
                                  await _giteeService.testConnection();
                              final name = user['name'] ?? user['login'] ?? '';
                              setDialogState(() {
                                testing = false;
                                testResult = '✅ 连接成功! 用户: $name';
                              });
                            } catch (e) {
                              setDialogState(() {
                                testing = false;
                                testResult = '❌ 连接失败: $e';
                              });
                            }
                          },
                    icon: testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering),
                    label: Text(testing ? '测试中...' : '测试连接'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_isConfigured)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
            ElevatedButton(
              onPressed: () {
                if (ownerCtrl.text.trim().isEmpty ||
                    tokenCtrl.text.trim().isEmpty) {
                  setDialogState(
                      () => testResult = '❌ 请填写用户名和令牌');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存并加载'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final newToken = tokenCtrl.text.trim();
      final newOwner = ownerCtrl.text.trim();
      final newPrefix = prefixCtrl.text.trim();
      await _giteeService.saveToken(newToken);
      await _giteeService.saveDefaultOwner(newOwner);
      await _giteeService.saveRepoPrefix(newPrefix);
      setState(() {
        _token = newToken;
        _owner = newOwner;
        _repoPrefix = newPrefix;
        _isConfigured = true;
      });
      _loadAllData();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 加载数据
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progress = 0;
      _progressText = '正在获取仓库列表...';
    });

    try {
      // 1. 获取教师账号的所有仓库（使用认证用户接口，避免限流）
      final allRepos = <Map<String, dynamic>>[];
      int page = 1;
      while (true) {
        final batch = await _giteeService.getMyRepos(
          page: page,
          perPage: 100,
          sort: 'full_name',
          direction: 'asc',
        );
        allRepos.addAll(batch);
        if (batch.length < 100) break;
        page++;
      }

      if (allRepos.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '该账号下没有仓库';
        });
        return;
      }

      // 根据前缀过滤仓库（只保留实验班组仓库）
      final filteredRepos = _giteeService.filterReposByPrefix(allRepos, _repoPrefix);

      if (filteredRepos.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = _repoPrefix.isNotEmpty
              ? '没有匹配前缀 "$_repoPrefix" 的仓库（共 ${allRepos.length} 个仓库）'
              : '该账号下没有仓库';
        });
        return;
      }

      // 存储仓库基础数据
      final repos = filteredRepos.map((r) => _RepoData(
            name: r['name']?.toString() ?? '',
            fullName: r['full_name']?.toString() ?? '',
            description: r['description']?.toString() ?? '',
            language: r['language']?.toString() ?? '',
            htmlUrl: r['html_url']?.toString() ?? '',
            starsCount: r['stargazers_count'] as int? ?? 0,
            forksCount: r['forks_count'] as int? ?? 0,
            updatedAt: r['updated_at']?.toString() ?? '',
          )).toList();

      setState(() {
        _repos = repos;
        _progressText = '正在加载仓库成员和提交数据...';
      });

      // 2. 逐个加载每个仓库的成员和提交
      final repoMembersList = <_RepoMembersData>[];
      final memberMap = <String, _AggregatedMember>{};
      final progressMap = <String, _StudentProgress>{};

      for (int i = 0; i < repos.length; i++) {
        final repo = repos[i];
        setState(() {
          _progress = (i + 1) / repos.length;
          _progressText = '正在加载 ${repo.name} (${i + 1}/${repos.length})...';
        });

        try {
          // 并行加载成员和提交
          final results = await Future.wait([
            _giteeService.getCollaborators(_owner, repo.name),
            _giteeService.getAllCommits(_owner, repo.name),
          ]);

          final members = results[0] as List<Map<String, dynamic>>;
          final commits = results[1] as List<Map<String, dynamic>>;

          // 每仓库成员数据
          repoMembersList.add(_RepoMembersData(
            repoName: repo.name,
            repoFullName: repo.fullName,
            members: members,
            commitCount: commits.length,
          ));

          // 聚合所有成员（去重）
          for (final m in members) {
            final login = m['login'] as String? ?? '';
            if (login.isEmpty) continue;
            if (memberMap.containsKey(login)) {
              memberMap[login]!.repos.add(repo.name);
            } else {
              memberMap[login] = _AggregatedMember(
                login: login,
                name: m['name'] as String? ?? login,
                avatarUrl: m['avatar_url'] as String? ?? '',
                repos: [repo.name],
                permissions: m['permissions'] as Map<String, dynamic>? ?? {},
              );
            }
          }

          // 按提交者统计进度（提交者 = 学生）
          final now = DateTime.now();
          // 按 author 聚合
          final authorStats = <String, _AuthorStats>{};

          for (final commit in commits) {
            final commitData =
                commit['commit'] as Map<String, dynamic>? ?? {};
            final authorInfo =
                commitData['author'] as Map<String, dynamic>? ?? {};
            final committerInfo =
                commitData['committer'] as Map<String, dynamic>? ?? {};
            final authorName =
                authorInfo['name']?.toString() ?? '';
            final authorEmail =
                authorInfo['email']?.toString() ?? '';
            final dateStr =
                committerInfo['date'] ?? authorInfo['date'];

            // 用 Gitee login 作 key（来自 commit.author，非 commit.commit.author）
            final commitAuthor =
                commit['author'] as Map<String, dynamic>?;
            final login =
                commitAuthor?['login']?.toString() ?? authorEmail;
            if (login.isEmpty) continue;

            authorStats.putIfAbsent(
              login,
              () => _AuthorStats(
                login: login,
                name: commitAuthor?['name']?.toString() ??
                    authorName,
                avatarUrl:
                    commitAuthor?['avatar_url']?.toString() ?? '',
              ),
            );
            final stats = authorStats[login]!;
            stats.totalCommits++;

            if (dateStr != null) {
              try {
                final date = DateTime.parse(dateStr);
                if (stats.lastCommitDate == null ||
                    date.isAfter(stats.lastCommitDate!)) {
                  stats.lastCommitDate = date;
                }
                final diff = now.difference(date).inDays;
                if (diff <= 7) stats.last7Days++;
                if (diff <= 30) stats.last30Days++;
              } catch (_) {}
            }
            stats.repoNames.add(repo.name);
          }

          // 合并到全局 progressMap
          for (final entry in authorStats.entries) {
            final key = entry.key;
            final stats = entry.value;
            if (progressMap.containsKey(key)) {
              final existing = progressMap[key]!;
              existing.totalCommits += stats.totalCommits;
              existing.last7DaysCommits += stats.last7Days;
              existing.last30DaysCommits += stats.last30Days;
              existing.repoNames.addAll(stats.repoNames);
              if (stats.lastCommitDate != null &&
                  (existing.lastCommitDate == null ||
                      stats.lastCommitDate!
                          .isAfter(existing.lastCommitDate!))) {
                existing.lastCommitDate = stats.lastCommitDate;
              }
            } else {
              progressMap[key] = _StudentProgress(
                login: key,
                name: stats.name,
                avatarUrl: stats.avatarUrl,
                totalCommits: stats.totalCommits,
                last7DaysCommits: stats.last7Days,
                last30DaysCommits: stats.last30Days,
                lastCommitDate: stats.lastCommitDate,
                repoNames: stats.repoNames,
              );
            }
          }
        } catch (e) {
          debugPrint('加载仓库 ${repo.name} 失败: $e');
          repoMembersList.add(_RepoMembersData(
            repoName: repo.name,
            repoFullName: repo.fullName,
            members: [],
            commitCount: 0,
            error: '$e',
          ));
        }
      }

      // 3. 排行排序（按总提交数降序）
      final rankings = progressMap.values.toList()
        ..sort((a, b) => b.totalCommits.compareTo(a.totalCommits));

      setState(() {
        _repoMembersList = repoMembersList;
        _allMembers = memberMap.values.toList()
          ..sort((a, b) => b.repos.length.compareTo(a.repos.length));
        _studentRankings = rankings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载失败: $e';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isConfigured
            ? '仓库分析 ($_owner${_repoPrefix.isNotEmpty ? ' · $_repoPrefix' : ''})'
            : '仓库分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Gitee 配置',
            onPressed: _showConfigDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || !_isConfigured ? null : _loadAllData,
          ),
          if (!_isLoading && _repoMembersList.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.file_download),
              tooltip: '导出',
              onSelected: _onExport,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'members_excel',
                  child: ListTile(
                    leading: Icon(Icons.table_chart, color: Colors.green),
                    title: Text('导出成员Excel'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'ranking_excel',
                  child: ListTile(
                    leading: Icon(Icons.leaderboard, color: Colors.blue),
                    title: Text('导出排行Excel'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy_text',
                  child: ListTile(
                    leading: Icon(Icons.copy, color: Colors.orange),
                    title: Text('复制排行文本'),
                  ),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: '仓库成员',
              icon: Badge(
                label: Text('${_repoMembersList.length}'),
                isLabelVisible: _repoMembersList.isNotEmpty,
                child: const Icon(Icons.folder_shared),
              ),
            ),
            Tab(
              text: '成员汇总',
              icon: Badge(
                label: Text('${_allMembers.length}'),
                isLabelVisible: _allMembers.isNotEmpty,
                child: const Icon(Icons.people),
              ),
            ),
            Tab(
              text: '进度排行',
              icon: Badge(
                label: Text('${_studentRankings.length}'),
                isLabelVisible: _studentRankings.isNotEmpty,
                child: const Icon(Icons.leaderboard),
              ),
            ),
          ],
        ),
      ),
      body: !_isConfigured
          ? _buildNotConfiguredView()
          : _isLoading
              ? _buildLoadingView()
              : _errorMessage != null
                  ? _buildErrorView()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRepoMembersTab(),
                        _buildAllMembersTab(),
                        _buildRankingTab(),
                      ],
                    ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 状态视图
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNotConfiguredView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              '请先配置 Gitee 账号',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '需要 Gitee 私人令牌和用户名才能获取仓库和成员信息',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showConfigDialog,
              icon: const Icon(Icons.settings),
              label: const Text('配置 Gitee'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 24),
            Text(
              _progressText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            if (_progress > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadAllData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showConfigDialog,
                  icon: const Icon(Icons.settings),
                  label: const Text('重新配置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 1: 每仓库成员列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRepoMembersTab() {
    if (_repoMembersList.isEmpty) {
      return const Center(child: Text('暂无仓库数据'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _repoMembersList.length,
      itemBuilder: (context, index) {
        final data = _repoMembersList[index];
        return _buildRepoMemberCard(data);
      },
    );
  }

  Widget _buildRepoMemberCard(_RepoMembersData data) {
    final hasError = data.error != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(
          hasError ? Icons.error : Icons.folder,
          color: hasError ? Colors.red : Colors.blue[700],
          size: 28,
        ),
        title: Text(
          data.repoName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: hasError
            ? Text('加载失败: ${data.error}',
                style: const TextStyle(fontSize: 12, color: Colors.red))
            : Row(
                children: [
                  _miniChip(
                      Icons.people, '${data.members.length}人', Colors.blue),
                  const SizedBox(width: 10),
                  _miniChip(Icons.commit, '${data.commitCount}次提交',
                      Colors.green),
                ],
              ),
        children: [
          if (data.members.isEmpty && !hasError)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无成员', style: TextStyle(color: Colors.grey)),
            )
          else
            ...data.members.map(_buildMemberTile),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final login = member['login']?.toString() ?? '';
    final name = member['name']?.toString() ?? login;
    final avatarUrl = member['avatar_url']?.toString() ?? '';
    final permissions = member['permissions'] as Map<String, dynamic>? ?? {};
    final isAdmin = permissions['admin'] == true;
    final isPush = permissions['push'] == true;

    String role = '只读';
    Color roleColor = Colors.grey;
    if (isAdmin) {
      role = '管理员';
      roleColor = Colors.amber[800]!;
    } else if (isPush) {
      role = '开发者';
      roleColor = Colors.green;
    }

    return ListTile(
      dense: true,
      leading: _avatar(avatarUrl, login, 18),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text('@$login',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: roleColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: roleColor.withValues(alpha: 0.3)),
        ),
        child: Text(role,
            style: TextStyle(
                fontSize: 11, color: roleColor, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 2: 全部成员汇总
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAllMembersTab() {
    if (_allMembers.isEmpty) {
      return const Center(child: Text('暂无成员数据'));
    }

    return Column(
      children: [
        // 统计头
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(
                  '总成员', '${_allMembers.length}', Icons.people, Colors.blue),
              _statItem('总仓库', '${_repos.length}', Icons.folder, Colors.teal),
              _statItem(
                '人均仓库',
                _allMembers.isNotEmpty
                    ? (_allMembers.fold<int>(
                                0, (s, m) => s + m.repos.length) /
                            _allMembers.length)
                        .toStringAsFixed(1)
                    : '0',
                Icons.analytics,
                Colors.orange,
              ),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _allMembers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final member = _allMembers[index];
              final isAdmin =
                  member.permissions['admin'] == true;
              return ListTile(
                leading: _avatar(member.avatarUrl, member.login, 22),
                title: Row(
                  children: [
                    Text(member.name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('管理员',
                            style: TextStyle(
                                fontSize: 10, color: Colors.amber[800])),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${member.login}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                    Text(
                      '参与 ${member.repos.length} 个仓库: ${member.repos.join(', ')}',
                      style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${member.repos.length}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 3: 学生进度排行
  // ─────────────────────────────────────────────────────────────────────────

  String _sortMode = 'total';

  Widget _buildRankingTab() {
    if (_studentRankings.isEmpty) {
      return const Center(child: Text('暂无提交数据'));
    }

    return Column(
      children: [
        // 排序
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'total', label: Text('总提交')),
                    ButtonSegment(value: 'recent', label: Text('近7天')),
                    ButtonSegment(value: 'monthly', label: Text('近30天')),
                  ],
                  selected: {_sortMode},
                  onSelectionChanged: (s) => _changeSortMode(s.first),
                ),
              ),
            ],
          ),
        ),
        // 排行
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _studentRankings.length,
            itemBuilder: (context, index) =>
                _buildRankingCard(_studentRankings[index], index + 1),
          ),
        ),
      ],
    );
  }

  void _changeSortMode(String mode) {
    setState(() {
      _sortMode = mode;
      switch (mode) {
        case 'recent':
          _studentRankings
              .sort((a, b) => b.last7DaysCommits.compareTo(a.last7DaysCommits));
          break;
        case 'monthly':
          _studentRankings.sort(
              (a, b) => b.last30DaysCommits.compareTo(a.last30DaysCommits));
          break;
        default:
          _studentRankings
              .sort((a, b) => b.totalCommits.compareTo(a.totalCommits));
      }
    });
  }

  Widget _buildRankingCard(_StudentProgress p, int rank) {
    // 排名奖杯
    Color rankColor;
    IconData? rankIcon;
    if (rank == 1) {
      rankColor = Colors.amber;
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = Colors.blueGrey;
      rankIcon = Icons.emoji_events;
    } else if (rank == 3) {
      rankColor = Colors.brown;
      rankIcon = Icons.emoji_events;
    } else {
      rankColor = Colors.grey[400]!;
      rankIcon = null;
    }

    // 活跃度
    String activityLevel;
    Color activityColor;
    if (p.last7DaysCommits >= 5) {
      activityLevel = '非常活跃';
      activityColor = Colors.green;
    } else if (p.last7DaysCommits >= 2) {
      activityLevel = '较为活跃';
      activityColor = Colors.blue;
    } else if (p.last30DaysCommits >= 3) {
      activityLevel = '一般';
      activityColor = Colors.orange;
    } else if (p.totalCommits > 0) {
      activityLevel = '低活跃';
      activityColor = Colors.orange[800]!;
    } else {
      activityLevel = '无提交';
      activityColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 排名
            SizedBox(
              width: 44,
              child: rankIcon != null
                  ? Icon(rankIcon, color: rankColor, size: 30)
                  : Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rankColor.withValues(alpha: 0.2),
                      ),
                      child: Center(
                        child: Text('$rank',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: rankColor,
                                fontSize: 14)),
                      ),
                    ),
            ),
            // 头像
            _avatar(p.avatarUrl, p.login, 20),
            const SizedBox(width: 10),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name.isNotEmpty ? p.name : p.login,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: activityColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: activityColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(activityLevel,
                            style: TextStyle(
                                fontSize: 11,
                                color: activityColor,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${p.login}  |  参与 ${p.repoNames.length} 个仓库',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 6),
                  // 统计
                  Row(
                    children: [
                      _rankStat('总提交', '${p.totalCommits}', Colors.blue),
                      _rankStat(
                          '近7天',
                          '${p.last7DaysCommits}',
                          p.last7DaysCommits > 0
                              ? Colors.green
                              : Colors.grey),
                      _rankStat(
                          '近30天',
                          '${p.last30DaysCommits}',
                          p.last30DaysCommits > 0
                              ? Colors.teal
                              : Colors.grey),
                      _rankStat(
                          '仓库', '${p.repoNames.length}', Colors.purple),
                    ],
                  ),
                  if (p.lastCommitDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '最近: ${DateFormat('yyyy-MM-dd HH:mm').format(p.lastCommitDate!)}  |  仓库: ${p.repoNames.join(', ')}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _rankStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 导出功能
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onExport(String type) async {
    switch (type) {
      case 'members_excel':
        await _exportMembersExcel();
        break;
      case 'ranking_excel':
        await _exportRankingExcel();
        break;
      case 'copy_text':
        _copyRankingText();
        break;
    }
  }

  Future<void> _exportMembersExcel() async {
    try {
      final excel = xl.Excel.createExcel();

      // Sheet 1: 每仓库成员
      final sheet1 = excel['仓库成员'];
      sheet1.appendRow([
        xl.TextCellValue('仓库名称'),
        xl.TextCellValue('成员账号'),
        xl.TextCellValue('成员名称'),
        xl.TextCellValue('角色'),
        xl.TextCellValue('仓库提交数'),
      ]);

      for (final data in _repoMembersList) {
        if (data.members.isEmpty) {
          sheet1.appendRow([
            xl.TextCellValue(data.repoName),
            xl.TextCellValue(''),
            xl.TextCellValue('（无成员）'),
            xl.TextCellValue(''),
            xl.IntCellValue(data.commitCount),
          ]);
        }
        for (final m in data.members) {
          final perms = m['permissions'] as Map<String, dynamic>? ?? {};
          String role = '只读';
          if (perms['admin'] == true) {
            role = '管理员';
          } else if (perms['push'] == true) {
            role = '开发者';
          }
          sheet1.appendRow([
            xl.TextCellValue(data.repoName),
            xl.TextCellValue(m['login']?.toString() ?? ''),
            xl.TextCellValue(m['name']?.toString() ?? ''),
            xl.TextCellValue(role),
            xl.IntCellValue(data.commitCount),
          ]);
        }
      }

      // Sheet 2: 成员汇总
      final sheet2 = excel['成员汇总'];
      sheet2.appendRow([
        xl.TextCellValue('成员账号'),
        xl.TextCellValue('成员名称'),
        xl.TextCellValue('参与仓库数'),
        xl.TextCellValue('参与仓库列表'),
      ]);
      for (final m in _allMembers) {
        sheet2.appendRow([
          xl.TextCellValue(m.login),
          xl.TextCellValue(m.name),
          xl.IntCellValue(m.repos.length),
          xl.TextCellValue(m.repos.join('; ')),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      await _saveExcel(excel, '仓库成员分析_$_owner');
    } catch (e) {
      _showError('导出失败: $e');
    }
  }

  Future<void> _exportRankingExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['进度排行'];

      sheet.appendRow([
        xl.TextCellValue('排名'),
        xl.TextCellValue('Gitee账号'),
        xl.TextCellValue('姓名'),
        xl.TextCellValue('总提交数'),
        xl.TextCellValue('近7天提交'),
        xl.TextCellValue('近30天提交'),
        xl.TextCellValue('参与仓库数'),
        xl.TextCellValue('参与仓库'),
        xl.TextCellValue('最近提交时间'),
        xl.TextCellValue('活跃度'),
      ]);

      for (int i = 0; i < _studentRankings.length; i++) {
        final p = _studentRankings[i];
        String level;
        if (p.last7DaysCommits >= 5) {
          level = '非常活跃';
        } else if (p.last7DaysCommits >= 2) {
          level = '较为活跃';
        } else if (p.last30DaysCommits >= 3) {
          level = '一般';
        } else if (p.totalCommits > 0) {
          level = '低活跃';
        } else {
          level = '无提交';
        }

        sheet.appendRow([
          xl.IntCellValue(i + 1),
          xl.TextCellValue(p.login),
          xl.TextCellValue(p.name),
          xl.IntCellValue(p.totalCommits),
          xl.IntCellValue(p.last7DaysCommits),
          xl.IntCellValue(p.last30DaysCommits),
          xl.IntCellValue(p.repoNames.length),
          xl.TextCellValue(p.repoNames.join('; ')),
          xl.TextCellValue(p.lastCommitDate != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(p.lastCommitDate!)
              : ''),
          xl.TextCellValue(level),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      await _saveExcel(excel, '学生进度排行_$_owner');
    } catch (e) {
      _showError('导出失败: $e');
    }
  }

  Future<void> _saveExcel(xl.Excel excel, String name) async {
    final bytes = excel.save();
    if (bytes == null) throw Exception('生成 Excel 失败');

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/${name}_$ts.xlsx');
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存: ${file.path}'),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => OpenFilex.open(file.path),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _copyRankingText() {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════');
    buf.writeln('       学生仓库进度排行榜 ($_owner)');
    buf.writeln('   ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buf.writeln('═══════════════════════════════════════════\n');

    for (int i = 0; i < _studentRankings.length; i++) {
      final p = _studentRankings[i];
      final name = p.name.isNotEmpty ? p.name : p.login;
      buf.writeln('第${i + 1}名  $name (@${p.login})');
      buf.writeln(
          '  总提交: ${p.totalCommits}  近7天: ${p.last7DaysCommits}  近30天: ${p.last30DaysCommits}');
      buf.writeln('  参与仓库: ${p.repoNames.join(', ')}');
      if (p.lastCommitDate != null) {
        buf.writeln(
            '  最近提交: ${DateFormat('yyyy-MM-dd HH:mm').format(p.lastCommitDate!)}');
      }
      buf.writeln();
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('排行榜已复制到剪贴板')));
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助 Widgets
  // ─────────────────────────────────────────────────────────────────────────

  Widget _avatar(String url, String fallback, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[300],
      child: url.isNotEmpty
          ? ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  fallback.isNotEmpty
                      ? fallback.substring(0, 1).toUpperCase()
                      : '?',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: radius * 0.8),
                ),
              ),
            )
          : Text(
              fallback.isNotEmpty
                  ? fallback.substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: radius * 0.8),
            ),
    );
  }

  Widget _miniChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  Widget _statItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────────────────────────────────────

class _RepoData {
  final String name;
  final String fullName;
  final String description;
  final String language;
  final String htmlUrl;
  final int starsCount;
  final int forksCount;
  final String updatedAt;

  _RepoData({
    required this.name,
    required this.fullName,
    required this.description,
    required this.language,
    required this.htmlUrl,
    required this.starsCount,
    required this.forksCount,
    required this.updatedAt,
  });
}

class _RepoMembersData {
  final String repoName;
  final String repoFullName;
  final List<Map<String, dynamic>> members;
  final int commitCount;
  final String? error;

  _RepoMembersData({
    required this.repoName,
    required this.repoFullName,
    required this.members,
    required this.commitCount,
    this.error,
  });
}

class _AggregatedMember {
  final String login;
  final String name;
  final String avatarUrl;
  final List<String> repos;
  final Map<String, dynamic> permissions;

  _AggregatedMember({
    required this.login,
    required this.name,
    required this.avatarUrl,
    required this.repos,
    required this.permissions,
  });
}

class _AuthorStats {
  final String login;
  final String name;
  final String avatarUrl;
  int totalCommits = 0;
  int last7Days = 0;
  int last30Days = 0;
  DateTime? lastCommitDate;
  final Set<String> repoNames = {};

  _AuthorStats({
    required this.login,
    required this.name,
    required this.avatarUrl,
  });
}

class _StudentProgress {
  final String login;
  final String name;
  final String avatarUrl;
  int totalCommits;
  int last7DaysCommits;
  int last30DaysCommits;
  DateTime? lastCommitDate;
  final Set<String> repoNames;

  _StudentProgress({
    required this.login,
    required this.name,
    required this.avatarUrl,
    required this.totalCommits,
    required this.last7DaysCommits,
    required this.last30DaysCommits,
    required this.lastCommitDate,
    required Set<String> repoNames,
  }) : repoNames = repoNames;
}
