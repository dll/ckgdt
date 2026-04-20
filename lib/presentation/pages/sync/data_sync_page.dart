import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/sync_service.dart';
import '../../../core/constants/app_theme.dart';

/// 数据同步管理页面
///
/// 直接使用本项目 Gitee 仓库 osgisOne/mad-fd，无需额外配置。
/// 学生：手动/自动上传学习数据
/// 教师：手动/自动拉取学生数据 + 查看已同步学生列表
class DataSyncPage extends StatefulWidget {
  const DataSyncPage({super.key});

  @override
  State<DataSyncPage> createState() => _DataSyncPageState();
}

class _DataSyncPageState extends State<DataSyncPage> {
  final _authService = AuthService();
  final _syncService = SyncService();

  // 状态
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSyncing = false;
  bool _autoSync = false;
  int _intervalMinutes = 10;
  String? _lastUpload;
  String? _lastDownload;
  String? _statusMsg;
  bool? _statusSuccess;

  // 教师：已同步的学生列表
  List<Map<String, dynamic>> _syncedStudents = [];
  bool _isLoadingStudents = false;

  bool get _isTeacherOrAdmin =>
      _authService.isTeacher || _authService.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final config = await _syncService.getConfig();
      _autoSync = config.enabled;
      _intervalMinutes = config.intervalMinutes.clamp(5, 60);
      _lastUpload = config.lastUpload;
      _lastDownload = config.lastDownload;
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    await _syncService.saveConfig(
      enabled: _autoSync,
      interval: _intervalMinutes,
    );
    await _authService.restartSync();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final result = await _syncService.testConnection();
    _showStatus(result.success, result.message);
    setState(() => _isTesting = false);
  }

  Future<void> _doSync() async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) {
      _showStatus(false, '未登录');
      return;
    }

    setState(() => _isSyncing = true);

    SyncResult result;
    if (_isTeacherOrAdmin) {
      result = await _syncService.downloadAllStudentData();
    } else {
      result = await _syncService.uploadStudentData(userId);
    }

    _showStatus(result.success, result.message);

    // 刷新同步时间
    _lastUpload = await _syncService.getLastUploadTime();
    _lastDownload = await _syncService.getLastDownloadTime();

    setState(() => _isSyncing = false);

    // 教师拉取后刷新学生列表
    if (_isTeacherOrAdmin && result.success) {
      _loadSyncedStudents();
    }
  }

  Future<void> _loadSyncedStudents() async {
    setState(() => _isLoadingStudents = true);
    try {
      _syncedStudents = await _syncService.listSyncedStudents();
    } catch (e) {
      debugPrint('加载已同步学生失败: $e');
    }
    setState(() => _isLoadingStudents = false);
  }

  void _showStatus(bool success, String message) {
    setState(() {
      _statusSuccess = success;
      _statusMsg = message;
    });
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '从未同步';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      final exact = '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (diff.inMinutes < 1) return '刚刚 ($exact)';
      if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前 ($exact)';
      if (diff.inHours < 24) return '${diff.inHours} 小时前 ($exact)';
      return exact;
    } catch (_) {
      return isoTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = AppGradientTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── 渐变 AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('数据同步',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
              background: Container(
                decoration: BoxDecoration(gradient: gradient.linearGradient),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (_isTeacherOrAdmin)
                IconButton(
                  icon: const Icon(Icons.people),
                  tooltip: '查看已同步学生',
                  onPressed: _loadSyncedStudents,
                ),
            ],
          ),

          // ── 内容 ────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_isLoading) ...[
                  const Center(child: CircularProgressIndicator()),
                ] else ...[
                  // 说明卡片
                  _buildInfoCard(theme, isDark),
                  const SizedBox(height: 16),

                  // 状态消息
                  if (_statusMsg != null) ...[
                    _buildStatusBanner(theme),
                    const SizedBox(height: 16),
                  ],

                  // 仓库信息 + 连接测试
                  _buildRepoInfoCard(theme, isDark),
                  const SizedBox(height: 16),

                  // 自动同步设置
                  _buildAutoSyncSection(theme, isDark),
                  const SizedBox(height: 16),

                  // 操作按钮
                  _buildActionSection(theme, gradient),
                  const SizedBox(height: 16),

                  // 同步时间
                  _buildSyncTimeSection(theme, isDark),

                  // 教师：已同步学生列表
                  if (_isTeacherOrAdmin) ...[
                    const SizedBox(height: 16),
                    _buildSyncedStudentsSection(theme, isDark),
                  ],

                  const SizedBox(height: 32),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── 说明卡片 ──────────────────────────────────────────────────────

  Widget _buildInfoCard(ThemeData theme, bool isDark) {
    final isStudent = !_isTeacherOrAdmin;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isStudent ? Icons.cloud_upload : Icons.cloud_download,
            color: theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isStudent ? '学生数据上传' : '教师数据拉取',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isStudent
                      ? '将本地的测验成绩、学习记录、错题等数据同步到课程仓库，教师可拉取查看。'
                      : '从课程仓库拉取所有学生的学习数据（测验成绩、学习记录、错题等）到本地查看。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 状态消息条 ────────────────────────────────────────────────────

  Widget _buildStatusBanner(ThemeData theme) {
    final isSuccess = _statusSuccess ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSuccess
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error,
            color: isSuccess ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMsg ?? '',
              style: TextStyle(
                color: isSuccess ? Colors.green[800] : Colors.red[800],
                fontSize: 13,
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() {
              _statusMsg = null;
              _statusSuccess = null;
            }),
            child: const Icon(Icons.close, size: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ── 仓库信息卡片 ──────────────────────────────────────────────────

  Widget _buildRepoInfoCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_shared,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('同步仓库',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),

            // 仓库地址（只读展示）
            _buildInfoRow(
              icon: Icons.link,
              label: '仓库',
              value: '${SyncService.repoOwner}/${SyncService.repoName}',
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.call_split,
              label: '分支',
              value: SyncService.repoBranch,
              color: Colors.purple,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              icon: Icons.folder_open,
              label: '路径',
              value: 'sync/students/{学号}.json',
              color: Colors.teal,
            ),
            const SizedBox(height: 12),

            // 测试连接按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_isTesting ? '测试中...' : '测试连接'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontFamily: 'monospace')),
      ],
    );
  }

  // ── 自动同步设置 ──────────────────────────────────────────────────

  Widget _buildAutoSyncSection(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('自动同步',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: _autoSync,
                  onChanged: (v) {
                    setState(() => _autoSync = v);
                    _saveConfig();
                  },
                ),
              ],
            ),
            if (_autoSync) ...[
              const SizedBox(height: 12),
              Text(
                '同步间隔: $_intervalMinutes 分钟',
                style: theme.textTheme.bodySmall,
              ),
              Slider(
                value: _intervalMinutes.toDouble(),
                min: 5,
                max: 60,
                divisions: 11,
                label: '$_intervalMinutes 分钟',
                onChanged: (v) {
                  setState(() => _intervalMinutes = v.round());
                },
                onChangeEnd: (_) => _saveConfig(),
              ),
              Text(
                _isTeacherOrAdmin
                    ? '启用后每隔 $_intervalMinutes 分钟自动从仓库拉取学生数据'
                    : '启用后每隔 $_intervalMinutes 分钟自动上传学习数据到仓库',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 操作按钮 ──────────────────────────────────────────────────────

  Widget _buildActionSection(ThemeData theme, AppGradientTheme gradient) {
    final isStudent = !_isTeacherOrAdmin;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSyncing ? null : _doSync,
        icon: _isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                isStudent ? Icons.cloud_upload : Icons.cloud_download,
                size: 22,
              ),
        label: Text(
          _isSyncing
              ? (isStudent ? '正在上传...' : '正在拉取...')
              : (isStudent ? '立即上传数据' : '立即拉取数据'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: gradient.gradientStart,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }

  // ── 同步时间 ──────────────────────────────────────────────────────

  Widget _buildSyncTimeSection(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('同步记录',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _buildTimeRow(
              icon: Icons.cloud_upload,
              label: '上次上传',
              time: _formatTime(_lastUpload),
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildTimeRow(
              icon: Icons.cloud_download,
              label: '上次拉取',
              time: _formatTime(_lastDownload),
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(time,
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ],
    );
  }

  // ── 已同步学生列表（教师用）──────────────────────────────────────

  Widget _buildSyncedStudentsSection(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('已同步学生 (${_syncedStudents.length})',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_isLoadingStudents)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadSyncedStudents,
                    tooltip: '刷新列表',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (_syncedStudents.isEmpty && !_isLoadingStudents) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off,
                        size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      '暂无已同步学生',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '学生启用自动上传后，数据将显示在这里',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ...List.generate(_syncedStudents.length, (i) {
                final s = _syncedStudents[i];
                return _buildStudentTile(s, theme, isDark);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTile(
      Map<String, dynamic> student, ThemeData theme, bool isDark) {
    final userId = student['user_id'] ?? '';
    final userName = student['user_name'] ?? '';
    final syncedAt = student['synced_at'] as String? ?? '';
    final lastActive = student['last_active'] as String? ?? '';
    final quizCount = student['quiz_count'] ?? 0;
    final recordCount = student['record_count'] ?? 0;
    final wrongCount = student['wrong_count'] ?? 0;
    final feedbackCount = student['feedback_count'] ?? 0;
    final favoriteCount = student['favorite_count'] ?? 0;
    final pathCount = student['path_count'] ?? 0;
    final labCount = student['lab_count'] ?? 0;
    final reportCount = student['report_count'] ?? 0;
    final workCount = student['work_count'] ?? 0;
    final checkinCount = student['checkin_count'] ?? 0;
    final surveyCount = student['survey_count'] ?? 0;

    // 判断在线状态（5 分钟内为在线）
    bool isOnline = false;
    String lastActiveExact = '';
    if (lastActive.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastActive);
        isOnline = DateTime.now().difference(dt).inMinutes < 5;
        lastActiveExact =
            '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    // 构建统计 chips（只显示有数据的或核心的）
    final chips = <Widget>[
      _buildStatChip(Icons.quiz, '测验 $quizCount', Colors.blue),
      _buildStatChip(Icons.school, '学习 $recordCount', Colors.green),
      _buildStatChip(Icons.error_outline, '错题 $wrongCount', Colors.orange),
      _buildStatChip(Icons.feedback, '反馈 $feedbackCount', Colors.purple),
    ];
    // 以下仅在有数据时显示
    if (favoriteCount > 0) {
      chips.add(_buildStatChip(Icons.star, '收藏 $favoriteCount', Colors.amber));
    }
    if (pathCount > 0) {
      chips.add(_buildStatChip(Icons.route, '路径 $pathCount', Colors.teal));
    }
    if (labCount > 0) {
      chips.add(_buildStatChip(Icons.science, '实验 $labCount', Colors.indigo));
    }
    if (reportCount > 0) {
      chips.add(_buildStatChip(Icons.description, '报告 $reportCount', Colors.brown));
    }
    if (workCount > 0) {
      chips.add(_buildStatChip(Icons.work, '作品 $workCount', Colors.pink));
    }
    if (checkinCount > 0) {
      chips.add(_buildStatChip(Icons.check_circle, '签到 $checkinCount', Colors.cyan));
    }
    if (surveyCount > 0) {
      chips.add(_buildStatChip(Icons.poll, '问卷 $surveyCount', Colors.lime));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isOnline ? Colors.green : Colors.grey[400]!,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：名称 + 在线状态
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? Colors.green : Colors.grey[400],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  userName.isNotEmpty ? '$userName ($userId)' : userId,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: '上传: ${_formatTime(syncedAt)}\n'
                    '活跃: ${lastActiveExact.isNotEmpty ? lastActiveExact : "未知"}',
                child: Text(
                  _formatTime(syncedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：数据统计
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
