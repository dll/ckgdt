import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../../services/auth_service.dart';
import '../../../services/gitee_service.dart';
import '../../../data/models/user_model.dart';

/// 仓库成员分析 & 学生进度排行
class RepoAnalyticsPage extends StatefulWidget {
  const RepoAnalyticsPage({super.key});

  @override
  State<RepoAnalyticsPage> createState() => _RepoAnalyticsPageState();
}

class _RepoAnalyticsPageState extends State<RepoAnalyticsPage>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _giteeService = GiteeService();

  late TabController _tabController;

  bool _isLoading = true;
  String? _errorMessage;
  double _progress = 0.0;
  String _progressText = '';

  // 数据
  List<_RepoMembersData> _repoMembersList = [];
  List<_AggregatedMember> _allMembers = [];
  List<_StudentProgress> _studentRankings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progress = 0;
      _progressText = '正在加载学生列表...';
    });

    try {
      // 1. 获取所有学生
      final students = await _authService.getStudents();
      final studentsWithRepo = students
          .where((s) =>
              s.repositoryUrl != null && s.repositoryUrl!.isNotEmpty)
          .toList();

      if (studentsWithRepo.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '暂无配置仓库地址的学生';
        });
        return;
      }

      final repoMembersList = <_RepoMembersData>[];
      final memberMap = <String, _AggregatedMember>{};
      final rankings = <_StudentProgress>[];

      // 2. 逐个加载每个学生的仓库数据
      for (int i = 0; i < studentsWithRepo.length; i++) {
        final student = studentsWithRepo[i];
        final parsed = GiteeService.parseRepoUrl(student.repositoryUrl!);
        if (parsed == null) continue;

        setState(() {
          _progress = (i + 1) / studentsWithRepo.length;
          _progressText =
              '正在加载 ${student.realName ?? student.userId} 的仓库 (${i + 1}/${studentsWithRepo.length})...';
        });

        try {
          // 并行加载成员和提交
          final results = await Future.wait([
            _giteeService.getCollaborators(parsed.owner, parsed.repo),
            _giteeService.getAllCommits(parsed.owner, parsed.repo),
            _giteeService.getBranches(parsed.owner, parsed.repo),
          ]);

          final members =
              results[0] as List<Map<String, dynamic>>;
          final commits =
              results[1] as List<Map<String, dynamic>>;
          final branches =
              results[2] as List<Map<String, dynamic>>;

          // 每仓库成员
          repoMembersList.add(_RepoMembersData(
            student: student,
            owner: parsed.owner,
            repo: parsed.repo,
            members: members,
            commitCount: commits.length,
          ));

          // 聚合所有成员
          for (final m in members) {
            final login = m['login'] as String? ?? '';
            if (login.isEmpty) continue;
            if (memberMap.containsKey(login)) {
              memberMap[login]!.repos
                  .add('${parsed.owner}/${parsed.repo}');
            } else {
              memberMap[login] = _AggregatedMember(
                login: login,
                name: m['name'] as String? ?? login,
                avatarUrl: m['avatar_url'] as String? ?? '',
                htmlUrl: m['html_url'] as String? ?? '',
                repos: ['${parsed.owner}/${parsed.repo}'],
              );
            }
          }

          // 学生进度统计
          final now = DateTime.now();
          int last7 = 0, last30 = 0;
          DateTime? lastCommitDate;
          final commitAuthors = <String>{};

          for (final commit in commits) {
            final commitData =
                commit['commit'] as Map<String, dynamic>? ?? {};
            final author =
                commitData['author'] as Map<String, dynamic>? ?? {};
            final committer =
                commitData['committer'] as Map<String, dynamic>? ?? {};
            final dateStr = committer['date'] ?? author['date'];
            final authorName = author['name'] ?? '';
            if (authorName is String && authorName.isNotEmpty) {
              commitAuthors.add(authorName);
            }

            if (dateStr != null) {
              try {
                final date = DateTime.parse(dateStr);
                if (lastCommitDate == null || date.isAfter(lastCommitDate)) {
                  lastCommitDate = date;
                }
                final diff = now.difference(date).inDays;
                if (diff <= 7) last7++;
                if (diff <= 30) last30++;
              } catch (_) {}
            }
          }

          rankings.add(_StudentProgress(
            student: student,
            owner: parsed.owner,
            repo: parsed.repo,
            totalCommits: commits.length,
            last7DaysCommits: last7,
            last30DaysCommits: last30,
            branchCount: branches.length,
            memberCount: members.length,
            lastCommitDate: lastCommitDate,
            commitAuthors: commitAuthors.toList(),
          ));
        } catch (e) {
          debugPrint('加载 ${student.userId} 仓库失败: $e');
          rankings.add(_StudentProgress(
            student: student,
            owner: parsed.owner,
            repo: parsed.repo,
            totalCommits: 0,
            last7DaysCommits: 0,
            last30DaysCommits: 0,
            branchCount: 0,
            memberCount: 0,
            lastCommitDate: null,
            commitAuthors: [],
            error: '$e',
          ));
        }
      }

      // 3. 排行排序（按总提交数降序）
      rankings.sort((a, b) => b.totalCommits.compareTo(a.totalCommits));

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('仓库分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadAllData,
          ),
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
          tabs: const [
            Tab(text: '仓库成员', icon: Icon(Icons.group)),
            Tab(text: '成员汇总', icon: Icon(Icons.people)),
            Tab(text: '进度排行', icon: Icon(Icons.leaderboard)),
          ],
        ),
      ),
      body: _isLoading
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
  // Loading & Error
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 1: 每仓库成员列表
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRepoMembersTab() {
    if (_repoMembersList.isEmpty) {
      return const Center(child: Text('暂无仓库成员数据'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _repoMembersList.length,
      itemBuilder: (context, index) {
        final data = _repoMembersList[index];
        return _buildRepoMemberCard(data, index);
      },
    );
  }

  Widget _buildRepoMemberCard(_RepoMembersData data, int index) {
    final student = data.student;
    final studentName = student.realName ?? student.userId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple,
          child: Text(
            studentName.substring(0, 1),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          studentName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data.owner}/${data.repo}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Row(
              children: [
                _miniChip(Icons.people, '${data.members.length}名成员',
                    Colors.blue),
                const SizedBox(width: 8),
                _miniChip(Icons.commit, '${data.commitCount}次提交',
                    Colors.green),
              ],
            ),
          ],
        ),
        children: [
          if (data.members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无成员信息', style: TextStyle(color: Colors.grey)),
            )
          else
            ...data.members.map((m) => _buildMemberTile(m)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final login = member['login'] ?? '';
    final name = member['name'] ?? login;
    final avatarUrl = member['avatar_url'] as String? ?? '';
    final permissions = member['permissions'] as Map<String, dynamic>? ?? {};
    final isAdmin = permissions['admin'] == true;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.grey[300],
        child: avatarUrl.isNotEmpty
            ? ClipOval(
                child: Image.network(
                  avatarUrl,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Text(login.substring(0, 1).toUpperCase()),
                ),
              )
            : Text(login.isNotEmpty ? login.substring(0, 1).toUpperCase() : '?'),
      ),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text('@$login', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: isAdmin
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('管理员',
                  style: TextStyle(fontSize: 11, color: Colors.amber)),
            )
          : null,
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
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('总成员数', '${_allMembers.length}', Icons.people, Colors.blue),
              _statItem('总仓库数', '${_repoMembersList.length}',
                  Icons.folder, Colors.teal),
              _statItem(
                '平均成员',
                _repoMembersList.isNotEmpty
                    ? (_allMembers.fold<int>(0, (s, m) => s + m.repos.length) /
                            _repoMembersList.length)
                        .toStringAsFixed(1)
                    : '0',
                Icons.analytics,
                Colors.orange,
              ),
            ],
          ),
        ),
        // 成员列表
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _allMembers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final member = _allMembers[index];
              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey[300],
                  child: member.avatarUrl.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            member.avatarUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(
                              member.login.substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
                      : Text(
                          member.login.substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                title: Text(member.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
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
                    '${member.repos.length}个仓库',
                    style: TextStyle(
                        fontSize: 12,
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

  Widget _buildRankingTab() {
    if (_studentRankings.isEmpty) {
      return const Center(child: Text('暂无排行数据'));
    }

    return Column(
      children: [
        // 排序选项
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('排序方式: ', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'total', label: Text('总提交')),
                  ButtonSegment(value: 'recent', label: Text('近7天')),
                  ButtonSegment(value: 'monthly', label: Text('近30天')),
                ],
                selected: {_sortMode},
                onSelectionChanged: (s) => _changeSortMode(s.first),
              ),
            ],
          ),
        ),
        // 排行列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _studentRankings.length,
            itemBuilder: (context, index) {
              return _buildRankingCard(_studentRankings[index], index + 1);
            },
          ),
        ),
      ],
    );
  }

  String _sortMode = 'total';

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
    final studentName = p.student.realName ?? p.student.userId;
    final hasError = p.error != null;

    // 排名颜色
    Color rankColor;
    IconData? rankIcon;
    if (rank == 1) {
      rankColor = Colors.amber;
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = Colors.grey;
      rankIcon = Icons.emoji_events;
    } else if (rank == 3) {
      rankColor = Colors.brown;
      rankIcon = Icons.emoji_events;
    } else {
      rankColor = Colors.grey[400]!;
      rankIcon = null;
    }

    // 活跃度评价
    String activityLevel;
    Color activityColor;
    if (hasError) {
      activityLevel = '加载失败';
      activityColor = Colors.red;
    } else if (p.last7DaysCommits >= 5) {
      activityLevel = '非常活跃';
      activityColor = Colors.green;
    } else if (p.last7DaysCommits >= 2) {
      activityLevel = '较为活跃';
      activityColor = Colors.blue;
    } else if (p.last30DaysCommits >= 3) {
      activityLevel = '一般活跃';
      activityColor = Colors.orange;
    } else if (p.totalCommits > 0) {
      activityLevel = '活跃度低';
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
              width: 48,
              child: Column(
                children: [
                  if (rankIcon != null)
                    Icon(rankIcon, color: rankColor, size: 28)
                  else
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rankColor.withValues(alpha: 0.2),
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          studentName,
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
                        child: Text(
                          activityLevel,
                          style: TextStyle(
                              fontSize: 11,
                              color: activityColor,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '学号: ${p.student.userId}  |  ${p.owner}/${p.repo}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  // 统计行
                  Row(
                    children: [
                      _rankStat('总提交', '${p.totalCommits}', Colors.blue),
                      _rankStat('近7天', '${p.last7DaysCommits}',
                          p.last7DaysCommits > 0 ? Colors.green : Colors.grey),
                      _rankStat(
                          '近30天',
                          '${p.last30DaysCommits}',
                          p.last30DaysCommits > 0
                              ? Colors.teal
                              : Colors.grey),
                      _rankStat('分支', '${p.branchCount}', Colors.purple),
                      _rankStat('成员', '${p.memberCount}', Colors.orange),
                    ],
                  ),
                  if (p.lastCommitDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '最近提交: ${DateFormat('yyyy-MM-dd HH:mm').format(p.lastCommitDate!)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                  if (p.commitAuthors.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '提交者: ${p.commitAuthors.join(', ')}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
          Text(
            value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
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
        xl.TextCellValue('学号'),
        xl.TextCellValue('姓名'),
        xl.TextCellValue('仓库'),
        xl.TextCellValue('成员账号'),
        xl.TextCellValue('成员名称'),
        xl.TextCellValue('仓库提交数'),
      ]);

      for (final data in _repoMembersList) {
        for (final m in data.members) {
          sheet1.appendRow([
            xl.TextCellValue(data.student.userId),
            xl.TextCellValue(data.student.realName ?? ''),
            xl.TextCellValue('${data.owner}/${data.repo}'),
            xl.TextCellValue(m['login']?.toString() ?? ''),
            xl.TextCellValue(m['name']?.toString() ?? ''),
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

      // 删除默认sheet
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      await _saveExcel(excel, '仓库成员分析');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _exportRankingExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['学生进度排行'];

      sheet.appendRow([
        xl.TextCellValue('排名'),
        xl.TextCellValue('学号'),
        xl.TextCellValue('姓名'),
        xl.TextCellValue('仓库'),
        xl.TextCellValue('总提交数'),
        xl.TextCellValue('近7天提交'),
        xl.TextCellValue('近30天提交'),
        xl.TextCellValue('分支数'),
        xl.TextCellValue('成员数'),
        xl.TextCellValue('最近提交时间'),
        xl.TextCellValue('提交者'),
        xl.TextCellValue('活跃度'),
      ]);

      for (int i = 0; i < _studentRankings.length; i++) {
        final p = _studentRankings[i];
        String activityLevel;
        if (p.error != null) {
          activityLevel = '加载失败';
        } else if (p.last7DaysCommits >= 5) {
          activityLevel = '非常活跃';
        } else if (p.last7DaysCommits >= 2) {
          activityLevel = '较为活跃';
        } else if (p.last30DaysCommits >= 3) {
          activityLevel = '一般活跃';
        } else if (p.totalCommits > 0) {
          activityLevel = '活跃度低';
        } else {
          activityLevel = '无提交';
        }

        sheet.appendRow([
          xl.IntCellValue(i + 1),
          xl.TextCellValue(p.student.userId),
          xl.TextCellValue(p.student.realName ?? ''),
          xl.TextCellValue('${p.owner}/${p.repo}'),
          xl.IntCellValue(p.totalCommits),
          xl.IntCellValue(p.last7DaysCommits),
          xl.IntCellValue(p.last30DaysCommits),
          xl.IntCellValue(p.branchCount),
          xl.IntCellValue(p.memberCount),
          xl.TextCellValue(p.lastCommitDate != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(p.lastCommitDate!)
              : ''),
          xl.TextCellValue(p.commitAuthors.join(', ')),
          xl.TextCellValue(activityLevel),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      await _saveExcel(excel, '学生进度排行');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _saveExcel(xl.Excel excel, String name) async {
    final bytes = excel.save();
    if (bytes == null) throw Exception('生成Excel失败');

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/${name}_$timestamp.xlsx');
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
    buf.writeln('        学生仓库进度排行榜');
    buf.writeln('    ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buf.writeln('═══════════════════════════════════════════');
    buf.writeln();

    for (int i = 0; i < _studentRankings.length; i++) {
      final p = _studentRankings[i];
      final name = p.student.realName ?? p.student.userId;
      buf.writeln(
          '第${i + 1}名  $name (${p.student.userId})');
      buf.writeln(
          '  仓库: ${p.owner}/${p.repo}');
      buf.writeln(
          '  总提交: ${p.totalCommits}  近7天: ${p.last7DaysCommits}  近30天: ${p.last30DaysCommits}');
      buf.writeln(
          '  分支: ${p.branchCount}  成员: ${p.memberCount}');
      if (p.lastCommitDate != null) {
        buf.writeln(
            '  最近提交: ${DateFormat('yyyy-MM-dd HH:mm').format(p.lastCommitDate!)}');
      }
      if (p.commitAuthors.isNotEmpty) {
        buf.writeln('  提交者: ${p.commitAuthors.join(', ')}');
      }
      buf.writeln();
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('排行榜已复制到剪贴板')),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助 Widgets
  // ─────────────────────────────────────────────────────────────────────────

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

  Widget _statItem(String label, String value, IconData icon, Color color) {
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

class _RepoMembersData {
  final UserModel student;
  final String owner;
  final String repo;
  final List<Map<String, dynamic>> members;
  final int commitCount;

  _RepoMembersData({
    required this.student,
    required this.owner,
    required this.repo,
    required this.members,
    required this.commitCount,
  });
}

class _AggregatedMember {
  final String login;
  final String name;
  final String avatarUrl;
  final String htmlUrl;
  final List<String> repos;

  _AggregatedMember({
    required this.login,
    required this.name,
    required this.avatarUrl,
    required this.htmlUrl,
    required this.repos,
  });
}

class _StudentProgress {
  final UserModel student;
  final String owner;
  final String repo;
  final int totalCommits;
  final int last7DaysCommits;
  final int last30DaysCommits;
  final int branchCount;
  final int memberCount;
  final DateTime? lastCommitDate;
  final List<String> commitAuthors;
  final String? error;

  _StudentProgress({
    required this.student,
    required this.owner,
    required this.repo,
    required this.totalCommits,
    required this.last7DaysCommits,
    required this.last30DaysCommits,
    required this.branchCount,
    required this.memberCount,
    required this.lastCommitDate,
    required this.commitAuthors,
    this.error,
  });
}
