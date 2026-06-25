part of '../git_repo_page.dart';

class _GiteeSettingsTab extends StatefulWidget {
  final GiteeService gitee;
  const _GiteeSettingsTab({required this.gitee});

  @override
  State<_GiteeSettingsTab> createState() => _GiteeSettingsTabState();
}

class _GiteeSettingsTabState extends State<_GiteeSettingsTab> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;
  DateTime? _lastSyncTime;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final token = await widget.gitee.getToken();
    if (token != null) {
      _tokenController.text = token;
    }
    // 加载同步时间
    final syncTime = await CourseResourceService().getLastSyncTime();
    if (mounted) {
      setState(() => _lastSyncTime = syncTime);
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    await widget.gitee.saveToken(token);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('令牌已保存'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // 先保存
      await _saveToken();
      final user = await widget.gitee.testConnection();
      final name = user['name'] ?? user['login'] ?? '未知';
      setState(() {
        _isTesting = false;
        _testSuccess = true;
        _testResult = '连接成功！用户: $name';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = '连接失败: $e';
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _clearCacheAndReload() async {
    setState(() => _isClearing = true);
    try {
      await CourseResourceService().clearCache();
      if (mounted) {
        setState(() {
          _isClearing = false;
          _lastSyncTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('缓存已清除，下次访问将重新同步'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradient = AppGradientTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 说明卡片
          Card(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: gradient.linearGradient,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Gitee 配置说明',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    '• 系统资源从 mad-data 仓库读取（实验/课件/考核配置）\n'
                    '• 学生仓库从 chzuczldl 企业读取（cg1-/cg2-/cg3- 前缀）\n'
                    '• 每个仓库使用 feat-姓名拼音首字母小写 标识学生\n'
                    '• 需要有企业仓库的读取权限\n'
                    '• 详见「提交规范」Tab',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Token 输入
          const Text('Gitee 私人令牌 (Personal Access Token)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            decoration: InputDecoration(
              hintText: '请输入 Gitee 私人令牌',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                        _obscureToken ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                  IconButton(
                    icon: const Icon(Icons.save),
                    onPressed: _saveToken,
                    tooltip: '保存',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '获取方式：Gitee → 设置 → 私人令牌 → 生成新令牌（勾选 projects 权限）',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // 测试连接
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(_isTesting ? '测试中...' : '测试连接'),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testSuccess ? Colors.green : Colors.red)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (_testSuccess ? Colors.green : Colors.red)
                        .withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess ? Icons.check_circle : Icons.error,
                    color: _testSuccess ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_testResult!,
                        style: TextStyle(
                            color: _testSuccess ? Colors.green[700] : Colors.red[700],
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // 仓库配置信息
          const Text('仓库配置', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildConfigItem('系统资源仓库', 'chzcldl/mad-data'),
          _buildConfigItem('企业命名空间', 'chzuczldl (滁州学院-刘东良)'),
          _buildConfigItem('学生仓库前缀', 'cg1-, cg2-, cg3-'),
          _buildConfigItem('分支命名规范', 'feat-{姓名拼音首字母小写}'),

          const SizedBox(height: 24),

          // 同步状态
          const Text('数据同步', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _lastSyncTime != null
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                        size: 18,
                        color: _lastSyncTime != null
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastSyncTime != null
                              ? '上次同步: ${_formatSyncTime(_lastSyncTime!)}'
                              : '尚未同步远程数据',
                          style: TextStyle(
                            fontSize: 13,
                            color: _lastSyncTime != null
                                ? Colors.green[700]
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '系统启动时自动从 Gitee 同步课程配置（实验/章节/考核方案），'
                    '缓存有效期1小时。如需立即刷新，可清除缓存。',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isClearing ? null : _clearCacheAndReload,
                      icon: _isClearing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_sweep, size: 18),
                      label: Text(_isClearing ? '清除中...' : '清除所有缓存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSyncTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildConfigItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
