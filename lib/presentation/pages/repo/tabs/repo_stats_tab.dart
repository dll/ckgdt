part of '../git_repo_page.dart';


class _RepoStatsTab extends StatefulWidget {
  final GiteeService gitee;
  final CourseResourceService resource;
  const _RepoStatsTab({required this.gitee, required this.resource});

  @override
  State<_RepoStatsTab> createState() => _RepoStatsTabState();
}

class _RepoStatsTabState extends State<_RepoStatsTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _repos = [];
  Map<String, Map<String, dynamic>> _repoDetails = {};
  bool _isLoading = true;
  bool _isLoadingDetails = false;
  String? _error;

  // 数据流审计结果
  Map<String, _AuditResult> _auditResults = {};
  bool _isAuditing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats({bool force = false}) async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final repos = await widget.resource.getStudentRepos(forceRefresh: force);
      if (mounted) {
        setState(() { _repos = repos; _isLoading = false; });
        _loadRepoDetails();
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = '$e'; });
    }
  }

  Future<void> _loadRepoDetails() async {
    if (_repos.isEmpty) return;
    setState(() => _isLoadingDetails = true);
    final details = <String, Map<String, dynamic>>{};
    for (final repo in _repos) {
      final path = repo['path']?.toString() ?? repo['name']?.toString() ?? '';
      if (path.isEmpty) continue;
      try {
        final detail = await widget.gitee.getRepoDetail(
            CourseResourceService.enterprise, path);
        details[path] = detail;
      } catch (_) {}
    }
    if (mounted) {
      setState(() { _repoDetails = details; _isLoadingDetails = false; });
    }
  }

  Future<void> _runAudit() async {
    setState(() { _isAuditing = true; _auditResults = {}; });
    final results = <String, _AuditResult>{};

    // 1. 测试 Gitee 连接
    try {
      await widget.gitee.testConnection();
      results['gitee_connection'] = _AuditResult(true, 'Token 有效，API 连接正常');
    } catch (e) {
      results['gitee_connection'] = _AuditResult(false, '连接失败: $e');
    }

    // 2. 测试 mad-data 课程配置读取
    try {
      final content = await widget.gitee.getFileContent(
          'chzcldl', 'mad-data', 'course_config/lab_tasks.json');
      results['mad_data_config'] = _AuditResult(
          content != null, content != null ? '读取成功 (${content.length} 字符)' : '文件为空');
    } catch (e) {
      results['mad_data_config'] = _AuditResult(false, '读取失败: $e');
    }

    // 3. 测试 mad-data 目录列表
    try {
      final dir = await widget.gitee.listDir(
          'chzcldl', 'mad-data', 'course_config');
      results['mad_data_dir'] = _AuditResult(
          dir.isNotEmpty, '${dir.length} 个配置文件');
    } catch (e) {
      results['mad_data_dir'] = _AuditResult(false, '列表失败: $e');
    }

    // 4. 测试学生仓库列表
    try {
      final repos = await widget.resource.getStudentRepos();
      results['student_repos'] = _AuditResult(
          repos.isNotEmpty, '发现 ${repos.length} 个学生仓库');
    } catch (e) {
      results['student_repos'] = _AuditResult(false, '获取失败: $e');
    }

    // 5. 测试学生仓库文件读取（取第一个仓库）
    if (_repos.isNotEmpty) {
      final firstRepo = _repos.first['path']?.toString() ?? '';
      if (firstRepo.isNotEmpty) {
        try {
          final tree = await widget.gitee.getTree(
              CourseResourceService.enterprise, firstRepo);
          final fileCount = tree.where((f) => f['type'] == 'blob').length;
          final dirCount = tree.where((f) => f['type'] == 'tree').length;
          results['student_repo_tree'] = _AuditResult(
              tree.isNotEmpty, '$firstRepo: $fileCount 文件, $dirCount 目录');

          // 检查 docs/reports 目录
          final hasReports = tree.any((f) =>
              (f['path']?.toString() ?? '').startsWith('docs/reports'));
          final hasWorks = tree.any((f) =>
              (f['path']?.toString() ?? '').startsWith('works/'));
          results['student_repo_structure'] = _AuditResult(true,
              '实验报告: ${hasReports ? "✓ 存在" : "✗ 未创建"}  '
              '作品目录: ${hasWorks ? "✓ 存在" : "✗ 未创建"}');
        } catch (e) {
          results['student_repo_tree'] = _AuditResult(false, '读取失败: $e');
        }
      }
    }

    // 6. 测试分支获取
    if (_repos.isNotEmpty) {
      final firstRepo = _repos.first['path']?.toString() ?? '';
      if (firstRepo.isNotEmpty) {
        try {
          final branches = await widget.gitee.getBranches(
              CourseResourceService.enterprise, firstRepo);
          final studentBranches = branches.where((b) =>
              CourseResourceService.studentBranchPattern
                  .hasMatch(b['name'].toString())).length;
          results['student_branches'] = _AuditResult(
              branches.isNotEmpty,
              '$firstRepo: ${branches.length} 分支 (${studentBranches} 学生分支)');
        } catch (e) {
          results['student_branches'] = _AuditResult(false, '获取失败: $e');
        }
      }
    }

    // 7. 测试课件下载 URL 可达性
    try {
      final rawUrl = await widget.gitee.getRawUrl(
          'chzcldl', 'mad-data', 'course_config/lab_tasks.json');
      results['raw_download'] = _AuditResult(true, 'Raw URL 生成正常');
      // 不实际下载，仅验证 URL 生成
      debugPrint('Audit: raw URL = $rawUrl');
    } catch (e) {
      results['raw_download'] = _AuditResult(false, 'URL 生成失败: $e');
    }

    if (mounted) setState(() { _auditResults = results; _isAuditing = false; });
  }

  // ── 统计计算 ──────────────────────────────────────────────────────────

  int get _totalStars => _repoDetails.values.fold(0,
      (sum, d) => sum + ((d['stargazers_count'] as num?) ?? 0).toInt());
  int get _totalForks => _repoDetails.values.fold(0,
      (sum, d) => sum + ((d['forks_count'] as num?) ?? 0).toInt());
  int get _totalWatchers => _repoDetails.values.fold(0,
      (sum, d) => sum + ((d['watchers_count'] as num?) ?? 0).toInt());
  int get _totalOpenIssues => _repoDetails.values.fold(0,
      (sum, d) => sum + ((d['open_issues_count'] as num?) ?? 0).toInt());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('加载失败: $_error', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadStats(force: true),
            icon: const Icon(Icons.refresh), label: const Text('重试'),
          ),
        ],
      ));
    }

    return RefreshIndicator(
      onRefresh: () => _loadStats(force: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildAggregateStats(),
          const SizedBox(height: 16),
          _buildDataFlowDiagram(),
          const SizedBox(height: 16),
          _buildAuditSection(),
          const SizedBox(height: 16),
          _buildRepoDetailList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAggregateStats() {
    final gradient = AppGradientTheme.of(context);
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: gradient.linearGradient,
        ),
        child: Column(
          children: [
            const Text('仓库统计概览',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 600 ? 6 : 3;
              final items = [
                _StatItem('${_repos.length}', '仓库', Icons.folder_copy),
                _StatItem('$_totalStars', '星标', Icons.star),
                _StatItem('$_totalForks', 'Fork', Icons.fork_right),
                _StatItem('$_totalWatchers', '关注', Icons.visibility),
                _StatItem('$_totalOpenIssues', 'Issues', Icons.bug_report),
                _StatItem(_isLoadingDetails ? '...' : '${_repoDetails.length}',
                    '已获详情', Icons.check_circle),
              ];
              return Wrap(
                spacing: 8, runSpacing: 8,
                children: items.map((item) => SizedBox(
                  width: (c.maxWidth - (cols - 1) * 8) / cols,
                  child: Column(children: [
                    Icon(item.icon, color: Colors.white70, size: 20),
                    const SizedBox(height: 4),
                    Text(item.value, style: const TextStyle(fontSize: 20,
                        fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(item.label, style: const TextStyle(fontSize: 11,
                        color: Colors.white70)),
                  ]),
                )).toList(),
              );
            }),
            if (_isLoadingDetails) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(Colors.white70)),
              const SizedBox(height: 4),
              const Text('正在获取仓库详情...',
                  style: TextStyle(fontSize: 11, color: Colors.white60)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataFlowDiagram() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_tree, size: 20, color: Colors.blue),
              ),
              const SizedBox(width: 10),
              const Text('数据流架构', style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            _buildFlowItem(
              icon: Icons.cloud,
              color: Colors.indigo,
              title: 'mad-data 仓库 (chzcldl/mad-data)',
              subtitle: '系统课件仓库 — 教学视频/PPT/PDF/课程配置',
              items: [
                'course_config/*.json → 实验定义、章节、考核方案、报告模板',
                '视频/*.mp4 → 教学视频（CoursewareDownloadService 下载）',
                '课件/清言智谱/*.pdf → PDF 文档',
                '课件/秒出PPT/*.pptx → PPT 课件',
              ],
            ),
            _buildFlowArrow(),
            _buildFlowItem(
              icon: Icons.group_work,
              color: Colors.teal,
              title: '学生项目仓库 (chzuczldl/cg{1-3}-*)',
              subtitle: '${_repos.length} 个仓库 — 学生项目代码和提交物',
              items: [
                'src/ → 项目源代码（个人分支 feat-xxx）',
                'docs/reports/ → 实验报告（实验X_姓名.md）',
                'docs/defense/ → 答辩材料 PPT',
                'works/ → 作品展示（README + 截图/视频）',
              ],
            ),
            _buildFlowArrow(),
            _buildFlowItem(
              icon: Icons.phone_android,
              color: Colors.deepPurple,
              title: 'mad-fd 仓库 (osgisOne/mad-fd)',
              subtitle: '系统代码仓库 — Flutter 应用 + SQLite 数据库',
              items: [
                'assets/learning_data.db → 预置 SQLite 数据库',
                'assets/student_group_data.json → 学生分组数据',
                'assets/student_repo_map.json → 学生-仓库映射（78人）',
                'lib/ → Flutter 应用源代码',
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isDark ? Colors.blue[900] : Colors.blue[50])!
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '数据流向：mad-data（课件配置）→ Gitee API → App 本地缓存\n'
                '学生提交：个人分支 → 项目仓库 → 系统读取（Contents/Tree API）\n'
                '存储策略：课件 → SharedPreferences 缓存 + 本地文件下载\n'
                '　　　　　学生数据 → SQLite 本地库 + Gitee API 实时读取',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowItem({
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
        color: color.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.bold, color: color))),
        ]),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('• ', style: TextStyle(color: color, fontSize: 12)),
            Expanded(child: Text(item, style: const TextStyle(fontSize: 11))),
          ]),
        )),
      ]),
    );
  }

  Widget _buildFlowArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(child: Icon(Icons.arrow_downward,
          size: 20, color: Colors.grey[400])),
    );
  }

  Widget _buildAuditSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.verified_user, size: 20,
                    color: Colors.orange),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('数据流审计', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold))),
              ElevatedButton.icon(
                onPressed: _isAuditing ? null : _runAudit,
                icon: _isAuditing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(_isAuditing ? '检测中...' : '开始检测'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
            if (_auditResults.isEmpty && !_isAuditing) ...[
              const SizedBox(height: 12),
              Text('点击「开始检测」验证所有数据通道是否畅通',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
            if (_auditResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._auditResults.entries.map((e) => _buildAuditRow(e.key, e.value)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuditRow(String key, _AuditResult result) {
    final labels = {
      'gitee_connection': 'Gitee API 连接',
      'mad_data_config': 'mad-data 配置文件读取',
      'mad_data_dir': 'mad-data 目录列表',
      'student_repos': '学生仓库发现',
      'student_repo_tree': '学生仓库文件树',
      'student_repo_structure': '学生仓库目录规范',
      'student_branches': '学生分支识别',
      'raw_download': 'Raw 下载 URL',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.ok ? Icons.check_circle : Icons.cancel,
              size: 16, color: result.ok ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labels[key] ?? key, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
              Text(result.message, style: TextStyle(fontSize: 11,
                  color: result.ok ? Colors.green[700] : Colors.red[700])),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildRepoDetailList() {
    if (_repoDetails.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(
            _isLoadingDetails ? '正在加载仓库详情...' : '暂无仓库详情数据',
            style: TextStyle(color: Colors.grey[500]),
          )),
        ),
      );
    }

    final sorted = _repoDetails.entries.toList()
      ..sort((a, b) {
        final aStars = (a.value['stargazers_count'] as num?) ?? 0;
        final bStars = (b.value['stargazers_count'] as num?) ?? 0;
        return bStars.compareTo(aStars);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.list_alt, size: 20, color: Colors.purple),
          ),
          const SizedBox(width: 10),
          Text('各仓库详情 (${sorted.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        ...sorted.map((entry) => _buildRepoDetailCard(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildRepoDetailCard(String name, Map<String, dynamic> detail) {
    final stars = (detail['stargazers_count'] as num?) ?? 0;
    final forks = (detail['forks_count'] as num?) ?? 0;
    final watchers = (detail['watchers_count'] as num?) ?? 0;
    final issues = (detail['open_issues_count'] as num?) ?? 0;
    final language = detail['language']?.toString() ?? '—';
    final updatedAt = detail['updated_at']?.toString() ?? '';
    final desc = detail['description']?.toString() ?? '';
    final groupNum = CourseResourceService.extractGroupNumber(name);
    final groupColor = {'1': Colors.blue, '2': Colors.green, '3': Colors.orange}[groupNum] ?? Colors.grey;

    String timeAgo = '';
    if (updatedAt.isNotEmpty) {
      final dt = DateTime.tryParse(updatedAt);
      if (dt != null) {
        final diff = DateTime.now().difference(dt);
        timeAgo = diff.inDays > 0 ? '${diff.inDays}天前'
            : diff.inHours > 0 ? '${diff.inHours}小时前'
            : '${diff.inMinutes}分前';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: groupColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('CG${groupNum ?? "?"}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                        color: groupColor)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14))),
              if (timeAgo.isNotEmpty) Text(timeAgo,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _buildMiniStat(Icons.star, '$stars', Colors.amber),
              _buildMiniStat(Icons.fork_right, '$forks', Colors.blue),
              _buildMiniStat(Icons.visibility, '$watchers', Colors.green),
              _buildMiniStat(Icons.bug_report, '$issues', Colors.red),
              _buildMiniStat(Icons.code, language, Colors.purple),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String text, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color.withValues(alpha: 0.7)),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }
}

class _StatItem {
  final String value, label;
  final IconData icon;
  const _StatItem(this.value, this.label, this.icon);
}

class _AuditResult {
  final bool ok;
  final String message;
  const _AuditResult(this.ok, this.message);
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 4: 提交规范（学生指南）
// ══════════════════════════════════════════════════════════════════════════════

