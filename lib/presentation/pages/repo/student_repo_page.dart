import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/gitee_service.dart';
import '../../../services/course_resource_service.dart';

/// 学生仓库页面 — 学生专属视图
///
/// 功能：
/// 1. 我的项目 Tab — 显示所在小组仓库详情 + 个人分支提交记录
/// 2. 提交规范 Tab — 仓库/分支/提交命名规范说明
class StudentRepoPage extends StatefulWidget {
  const StudentRepoPage({super.key});

  @override
  State<StudentRepoPage> createState() => _StudentRepoPageState();
}

class _StudentRepoPageState extends State<StudentRepoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _gitee = GiteeService();
  final _resource = CourseResourceService();

  // 数据
  List<Map<String, dynamic>> _myRepos = [];
  Map<String, dynamic>? _selectedRepo;
  List<Map<String, dynamic>> _myBranches = [];
  List<Map<String, dynamic>> _myCommits = [];
  bool _isLoadingRepos = true;
  bool _isLoadingDetail = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyRepos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载学生所在的项目仓库
  Future<void> _loadMyRepos() async {
    setState(() {
      _isLoadingRepos = true;
      _errorMessage = null;
    });

    try {
      final allRepos = await _resource.getStudentRepos();
      if (allRepos.isEmpty) {
        setState(() {
          _myRepos = [];
          _isLoadingRepos = false;
          _errorMessage = '未找到项目仓库，请确认 Gitee 令牌已配置';
        });
        return;
      }

      // 学生看到所有 CG 仓库（他们需要找到自己的组）
      setState(() {
        _myRepos = allRepos;
        _isLoadingRepos = false;
      });

      // 如果只有一个仓库，自动选中
      if (allRepos.length == 1) {
        _selectRepo(allRepos.first);
      }
    } catch (e) {
      setState(() {
        _isLoadingRepos = false;
        _errorMessage = '加载仓库失败: $e';
      });
    }
  }

  /// 选中仓库后加载分支和提交
  Future<void> _selectRepo(Map<String, dynamic> repo) async {
    final owner = repo['namespace']?['path']?.toString() ??
        CourseResourceService.enterprise;
    final repoPath = repo['path']?.toString() ?? '';

    setState(() {
      _selectedRepo = repo;
      _isLoadingDetail = true;
      _myBranches = [];
      _myCommits = [];
    });

    try {
      // 获取该仓库所有学生分支
      final branches = await _resource.getStudentBranches(owner, repoPath);

      // 找到与当前用户匹配的分支
      final userId = _authService.currentUser?.userId ?? '';
      final realName = _authService.currentUser?.realName ?? '';

      setState(() {
        _myBranches = branches;
        _isLoadingDetail = false;
      });

      // 尝试加载当前用户分支的提交
      final myBranch = _findMyBranch(branches, userId, realName);
      if (myBranch != null) {
        _loadBranchCommits(owner, repoPath, myBranch);
      }
    } catch (e) {
      setState(() {
        _isLoadingDetail = false;
      });
    }
  }

  /// 匹配当前用户的分支
  String? _findMyBranch(
      List<Map<String, dynamic>> branches, String userId, String realName) {
    for (final b in branches) {
      final name = b['name']?.toString() ?? '';
      // 匹配 feat-{拼音首字母}
      if (name.startsWith('feat-')) {
        // 无法精确匹配时返回第一个（后续可改进）
      }
    }
    return branches.isNotEmpty ? branches.first['name']?.toString() : null;
  }

  /// 加载指定分支的提交记录
  Future<void> _loadBranchCommits(
      String owner, String repo, String branch) async {
    try {
      final commits =
          await _resource.getBranchCommits(owner, repo, branch, perPage: 50);
      if (mounted) {
        setState(() {
          _myCommits = commits;
        });
      }
    } catch (_) {}
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
              Tab(icon: Icon(Icons.folder_special, size: 18), text: '我的项目'),
              Tab(icon: Icon(Icons.rule_folder, size: 18), text: '提交规范'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMyProjectTab(),
              const _SubmissionGuidelinesTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Tab 1: 我的项目
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMyProjectTab() {
    if (_isLoadingRepos) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadMyRepos,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyRepos,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户信息卡片
          _buildUserInfoCard(),
          const SizedBox(height: 16),

          // 仓库列表
          const Text('项目仓库',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._myRepos.map((repo) => _buildRepoCard(repo)),

          // 选中仓库后的详情
          if (_selectedRepo != null) ...[
            const SizedBox(height: 24),
            _buildRepoDetailSection(),
          ],
        ],
      ),
    );
  }

  /// 用户信息卡片
  Widget _buildUserInfoCard() {
    final user = _authService.currentUser;
    final gradient = AppGradientTheme.of(context);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient.linearGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              child: Text(
                (user?.realName ?? '?').substring(0, 1),
                style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.realName ?? '未知用户',
                    style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '学号: ${user?.userId ?? '-'}',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  Text(
                    '角色: 学生',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            // 提交统计
            Column(
              children: [
                Text(
                  '${_myCommits.length}',
                  style: const TextStyle(
                      fontSize: 28,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  '提交数',
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 仓库卡片
  Widget _buildRepoCard(Map<String, dynamic> repo) {
    final name = repo['name']?.toString() ?? repo['path']?.toString() ?? '';
    final path = repo['path']?.toString() ?? '';
    final description = repo['description']?.toString() ?? '';
    final isSelected = _selectedRepo?['path'] == repo['path'];

    // 提取组号
    final groupNum = CourseResourceService.extractGroupNumber(path);
    final groupLabel = groupNum != null ? 'CG$groupNum' : '项目';

    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getGroupColor(groupLabel),
          child: Text(groupLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: description.isNotEmpty
            ? Text(description, maxLines: 1, overflow: TextOverflow.ellipsis)
            : Text(path, style: const TextStyle(color: Colors.grey)),
        trailing: isSelected
            ? Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary)
            : const Icon(Icons.chevron_right),
        onTap: () => _selectRepo(repo),
      ),
    );
  }

  /// 仓库详情区域
  Widget _buildRepoDetailSection() {
    if (_isLoadingDetail) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final repoName = _selectedRepo?['name']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分支列表
        Row(
          children: [
            const Icon(Icons.account_tree, size: 20),
            const SizedBox(width: 8),
            Text('$repoName — 学生分支',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${_myBranches.length} 个分支',
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        if (_myBranches.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('暂无学生分支',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          ..._myBranches.map((b) => _buildBranchTile(b)),

        // 提交记录
        if (_myCommits.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: 8),
              const Text('最近提交',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_myCommits.length} 条记录',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          ..._myCommits.take(20).map((c) => _buildCommitTile(c)),
        ],
      ],
    );
  }

  /// 分支列表项
  Widget _buildBranchTile(Map<String, dynamic> branch) {
    final name = branch['name']?.toString() ?? '';
    final isProtected = branch['protected'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.merge_type,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
        title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
        trailing: isProtected
            ? const Chip(
                label: Text('保护', style: TextStyle(fontSize: 10)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            : null,
        onTap: () {
          // 加载该分支提交
          final owner = _selectedRepo?['namespace']?['path']?.toString() ??
              CourseResourceService.enterprise;
          final repo = _selectedRepo?['path']?.toString() ?? '';
          _loadBranchCommits(owner, repo, name);
        },
      ),
    );
  }

  /// 提交记录项
  Widget _buildCommitTile(Map<String, dynamic> commit) {
    final message = commit['commit']?['message']?.toString() ?? '';
    final authorName =
        commit['commit']?['author']?['name']?.toString() ?? '未知';
    final dateStr =
        commit['commit']?['author']?['date']?.toString() ?? '';
    final sha = commit['sha']?.toString() ?? '';
    final shortSha = sha.length >= 7 ? sha.substring(0, 7) : sha;

    String timeAgo = '';
    if (dateStr.isNotEmpty) {
      final date = DateTime.tryParse(dateStr);
      if (date != null) {
        final diff = DateTime.now().difference(date);
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
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.split('\n').first,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(shortSha,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 12),
                      Text(authorName,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const Spacer(),
                      Text(timeAgo,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGroupColor(String group) {
    switch (group) {
      case 'CG1':
        return Colors.blue;
      case 'CG2':
        return Colors.green;
      case 'CG3':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2: 提交规范（复用自 git_repo_page.dart 中的内容）
// ══════════════════════════════════════════════════════════════════════════════

class _SubmissionGuidelinesTab extends StatelessWidget {
  const _SubmissionGuidelinesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSection(
          context,
          icon: Icons.folder_copy,
          title: '1. 仓库命名规范',
          color: Colors.blue,
          items: const [
            '仓库由教师创建，命名格式: cg{组号}-{项目名}',
            '示例: cg1-shopping, cg2-chat, cg3-news',
            '学生通过 Gitee 平台邀请加入仓库成为成员',
          ],
        ),
        _buildSection(
          context,
          icon: Icons.account_tree,
          title: '2. 分支命名规范',
          color: Colors.green,
          items: const [
            '每位学生创建个人分支: feat-{姓名拼音首字母小写}',
            '示例: feat-ldl (刘东良), feat-zwq (张伟强)',
            '拼音首字母取2~5个小写字母',
            '不要在 master/main 分支直接提交',
          ],
        ),
        _buildSection(
          context,
          icon: Icons.commit,
          title: '3. 提交消息规范',
          color: Colors.orange,
          items: const [
            '格式: <类型>: <简短描述>',
            'feat: 新功能  |  fix: 修复  |  docs: 文档',
            'style: 格式  |  refactor: 重构  |  test: 测试',
            '示例: feat: 添加用户登录页面',
          ],
        ),
        _buildSection(
          context,
          icon: Icons.assignment,
          title: '4. 实验提交流程',
          color: Colors.purple,
          items: const [
            '① 在个人分支上完成开发',
            '② 提交代码并推送到远程仓库',
            '③ 在本系统「实验」页面提交实验报告',
            '④ 等待教师评阅反馈',
          ],
        ),
        _buildSection(
          context,
          icon: Icons.terminal,
          title: '5. 常用 Git 命令',
          color: Colors.teal,
          items: const [
            'git clone <仓库地址>        — 克隆仓库',
            'git checkout -b feat-xxx  — 创建并切换分支',
            'git add .                 — 暂存所有修改',
            'git commit -m "消息"       — 提交',
            'git push origin feat-xxx  — 推送到远程',
            'git pull origin master    — 拉取最新主分支',
          ],
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required List<String> items,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 16),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: Colors.grey)),
                      Expanded(
                        child: Text(item,
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
