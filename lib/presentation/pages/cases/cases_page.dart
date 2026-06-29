import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/local/case_dao.dart';
import '../../../services/achievement_context.dart';
import '../../../services/project_detector.dart';
import '../../../services/process_manager_service.dart' as pm;
import '../../../services/apk_launcher_service.dart';
import '../../../core/error_handler.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../core/utils/path_utils.dart';

/// 教学案例页面
/// 设计目标：极简、零空白、可视化强
/// - 进入页面：立即显示空状态引导 + 顶部"添加案例"按钮
/// - 添加案例：粘贴路径 → 一键运行
/// - 案例卡片：状态灯 + 名称 + 路径 + 启动/停止按钮
class CasesPage extends StatefulWidget {
  const CasesPage({super.key});
  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  final CaseDao _caseDao = CaseDao();
  final pm.ProcessManagerService _procMgr = pm.ProcessManagerService.instance;
  final ApkLauncherService _apkService = ApkLauncherService();
  List<Map<String, dynamic>> _cases = [];
  bool _loading = false; // 关键：初始为 false，避免卡死
  String? _loadError; // 加载错误信息

  @override
  void initState() {
    super.initState();
    // 延迟到第一帧后再加载，确保 UI 先渲染空状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCases();
    });
    AchievementContext.instance.courseNameNotifier.addListener(_onCourseChanged);
  }

  @override
  void dispose() {
    AchievementContext.instance.courseNameNotifier.removeListener(_onCourseChanged);
    super.dispose();
  }

  void _onCourseChanged() => _loadCases();

  Future<void> _loadCases() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await _caseDao.getCases();
      if (!mounted) return;
      setState(() {
        _cases = list;
        _loading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'CasesPage.loadCases', stack: st);
      if (!mounted) return;
      setState(() {
        _cases = [];
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  String _procKey(int id) => 'case_$id';

  // ════════════════════════════════════════════════════════════════
  // 启动 / 停止
  // ════════════════════════════════════════════════════════════════

  Future<void> _startCase(Map<String, dynamic> c) async {
    final id = c['id'] as int;
    // 关键：规范化路径，去除用户可能带入的引号
    final path = PathUtils.normalize(c['project_path']?.toString() ?? '');
    if (path.isEmpty) {
      _toast('案例路径为空', color: Colors.red);
      return;
    }

    final pathExists = PathUtils.pathExists(path);
    if (!pathExists) {
      _toast('路径不存在: $path', color: Colors.red);
      return;
    }

    // ── APK 文件：走 APK 启动流程 ────────────────────────────────
    if (path.toLowerCase().endsWith('.apk')) {
      await _startApk(path);
      if (mounted) setState(() {});
      return;
    }

    final entryCmd = c['entry_command']?.toString();
    final info = ProjectDetector.getProjectInfo(path);
    final isWeb = info.url != null;

    // Web 应用：启动后自动打开浏览器
    if (isWeb) {
      _toast('正在启动 Web 服务: ${info.url}', color: Colors.blue);
      _openBrowserAfterStart(info.url!);
    }

    try {
      if (entryCmd != null && entryCmd.isNotEmpty) {
        final parts = entryCmd.split(RegExp(r'\s+'));
        await _procMgr.start(
          _procKey(id),
          executable: parts.first,
          args: parts.skip(1).toList(),
          workingDirectory: path,
          onOutput: isWeb ? (line) => _tryOpenBrowserFromLog(line, info.url!) : null,
        );
      } else {
        if (info.runCommand == null) {
          _toast('无法识别该项目类型', color: Colors.orange);
          return;
        }
        await _procMgr.start(
          _procKey(id),
          executable: info.runCommand!,
          args: info.runArgs,
          workingDirectory: info.workingDir ?? path,
          onOutput: isWeb ? (line) => _tryOpenBrowserFromLog(line, info.url!) : null,
        );
      }
    } catch (e) {
      _toast('启动失败: $e', color: Colors.red);
    }
    if (mounted) setState(() {});
  }

  // Web 应用：延迟 + 日志监听，自动打开浏览器
  final Set<String> _openedUrls = {};

  void _openBrowserAfterStart(String url) {
    // 首次启动等待服务就绪后打开浏览器
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_openedUrls.contains(url)) {
        _openedUrls.add(url);
        ProjectDetector.openInBrowser(url);
      }
    });
  }

  void _tryOpenBrowserFromLog(String line, String fallbackUrl) {
    // 从启动日志中提取 URL
    final match = RegExp('https?://(?:localhost|127\\.0\\.0\\.1):\\d+[^\\s"\']*')
        .firstMatch(line);
    final url = match?.group(0) ?? fallbackUrl;
    if (!_openedUrls.contains(url)) {
      _openedUrls.add(url);
      ProjectDetector.openInBrowser(url);
    }
  }

  /// APK 启动：检测 ADB/模拟器 → 启动模拟器 → 安装 APK → 启动 APK
  Future<void> _startApk(String apkPath) async {
    _toast('正在准备 APK 启动环境...', color: Colors.blue);
    final ok = await _apkService.launchApk(
      apkPath: apkPath,
      onProgress: (msg) {
        if (mounted) _toast(msg, color: Colors.blue);
      },
    );
    if (mounted) {
      _toast(ok ? 'APK 已启动' : 'APK 启动失败',
          color: ok ? Colors.green : Colors.red);
    }
  }

  Future<void> _stopCase(int caseId) async {
    try {
      await _procMgr.stop(_procKey(caseId));
      // 停止后清除 URL 打开记录，方便下次重新启动自动打开浏览器
      _openedUrls.clear();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _toast(String msg, {Color color = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 添加案例（核心交互）
  // ════════════════════════════════════════════════════════════════

  Future<void> _addCase() async {
    var path = await _showAddDialog();
    if (path == null || path.isEmpty) return;

    // 关键：规范化路径（去除用户复制时带入的引号）
    path = PathUtils.normalize(path);

    // 路径校验
    if (!PathUtils.pathExists(path)) {
      _toast('路径不存在，请检查: $path', color: Colors.red);
      return;
    }

    // 自动命名
    final name = path.toLowerCase().endsWith('.apk')
        ? path.split(Platform.pathSeparator).last
        : (PathUtils.deriveName(path).isNotEmpty
            ? PathUtils.deriveName(path)
            : path.split(Platform.pathSeparator).last);

    try {
      final id = await _caseDao.addCase(name: name, projectPath: path);
      await _loadCases();
      if (!mounted) return;
      // 自动启动
      final nc = _cases.firstWhere(
        (c) => c['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (nc.isNotEmpty) {
        await _startCase(nc);
        _toast('已添加并启动: $name', color: Colors.green);
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'CasesPage.addCase', stack: st);
      _toast('添加失败: $e', color: Colors.red);
    }
  }

  /// 添加案例对话框（极简设计）
  Future<String?> _showAddDialog() async {
    final pathCtrl = TextEditingController();
    String? detectedType;

    void detectType() {
      final p = PathUtils.normalize(pathCtrl.text);
      if (p.isEmpty) {
        detectedType = null;
        return;
      }
      if (p.toLowerCase().endsWith('.apk')) {
        detectedType = 'APK 安装包';
        return;
      }
      if (PathUtils.pathExists(p)) {
        final info = ProjectDetector.getProjectInfo(p);
        detectedType = info.label;
      } else {
        detectedType = null;
      }
    }

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // 首次打开时检测一次
          WidgetsBinding.instance.addPostFrameCallback((_) {
            detectType();
            setDialogState(() {});
          });
          return AlertDialog(
            backgroundColor: const Color(0xFF1A2530),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.add_circle, color: Color(0xFF4FC3F7), size: 24),
                SizedBox(width: 8),
                Text('添加教学案例',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '请输入项目目录或可执行文件路径',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: r'D:\project\output\app-v1.0',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0E1620),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon:
                        const Icon(Icons.folder, color: Colors.white38, size: 20),
                  ),
                  onChanged: (_) {
                    detectType();
                    setDialogState(() {});
                  },
                  onSubmitted: (v) {
                    final p = v.trim();
                    if (p.isNotEmpty) Navigator.pop(ctx, p);
                  },
                ),
                if (detectedType != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: Color(0xFF4FC3F7), size: 14),
                        const SizedBox(width: 6),
                        Text('识别为: $detectedType',
                            style: const TextStyle(
                                color: Color(0xFF4FC3F7), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '支持格式:\n'
                    '• 已打包目录（包含 .exe）\n'
                    '• 单个 .exe / .bat / .jar / .py / .apk 文件\n'
                    '• Flutter / Java / Node 项目目录',
                    style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.5),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  // 尝试用系统文件夹选择器
                  try {
                    final picked = await Process.run('powershell', [
                      '-Command',
                      'Add-Type -AssemblyName System.Windows.Forms; '
                      '\$f = New-Object System.Windows.Forms.FolderBrowserDialog; '
                      '\$f.Description = "选择项目目录"; '
                      'if (\$f.ShowDialog() -eq "OK") { Write-Output \$f.SelectedPath }',
                    ], runInShell: true);
                    final path = (picked.stdout as String).trim();
                    if (path.isNotEmpty) {
                      pathCtrl.text = path;
                      detectType();
                      setDialogState(() {});
                    }
                  } catch (_) {}
                },
                child: const Text('浏览...', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Colors.white54)),
              ),
              FilledButton.icon(
                onPressed: () {
                  final p = pathCtrl.text.trim();
                  if (p.isEmpty) return;
                  Navigator.pop(ctx, p);
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('运行'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4FC3F7),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteCase(int id) async {
    await _stopCase(id);
    try {
      await _caseDao.deleteCase(id);
    } catch (_) {}
    await _loadCases();
  }

  // ════════════════════════════════════════════════════════════════
  // UI 构建
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopToolbar(),
        const Divider(height: 1, color: Color(0xFF1F2A38)),
        Expanded(child: _buildBody()),
      ],
    );
  }

  /// 顶部工具栏：[+ 添加案例] [↻ 刷新]
  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: NoirTokens.ink,
      child: Row(
        children: [
          // 左侧标题（小字）
          Text(
            '共 ${_cases.length} 个案例',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // 添加案例（亮色按钮）
          TextButton.icon(
            onPressed: _addCase,
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
              foregroundColor: const Color(0xFF4FC3F7),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加案例',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          // 刷新
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
            onPressed: _loadCases,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _cases.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4FC3F7)),
      );
    }

    if (_loadError != null && _cases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text('加载失败',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 6),
              Text(_loadError!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loadCases,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cases.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      itemCount: _cases.length,
      itemBuilder: (ctx, i) => _buildCaseCard(_cases[i]),
    );
  }

  /// 空状态：清晰引导用户添加第一个案例
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open,
                  size: 48, color: Color(0xFF4FC3F7)),
            ),
            const SizedBox(height: 20),
            const Text('还没有教学案例',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              '点击顶部"添加案例"按钮，添加你的第一个项目\n系统会自动识别类型并启动',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _addCase,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('立即添加', style: TextStyle(fontSize: 15)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 案例卡片
  Widget _buildCaseCard(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final name = (c['name'] ?? '').toString().trim();
    // 关键：规范化路径（修复历史脏数据中可能带有的引号）
    final rawPath = (c['project_path'] ?? '').toString();
    final path = PathUtils.normalize(rawPath);
    final pathExists = PathUtils.pathExists(path);
    final isApk = path.toLowerCase().endsWith('.apk');
    final status = _procMgr.getStatus(_procKey(id));
    final isRunning = status == pm.ProcessStatus.running;
    final isFailed = status == pm.ProcessStatus.failed;
    final info = pathExists && !isApk
        ? ProjectDetector.getProjectInfo(path)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF162230),
        borderRadius: BorderRadius.circular(10),
        border: isRunning
            ? Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: [
          // 状态指示灯
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning
                  ? Colors.green
                  : isFailed
                      ? Colors.red
                      : pathExists
                          ? Colors.white38
                          : Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          // 名称和路径
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isApk) ...[
                      const SizedBox(width: 6),
                      _badge('APK', Colors.green),
                    ] else if (info != null) ...[
                      const SizedBox(width: 6),
                      _badge(info.label, null),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isRunning && info?.url != null
                      ? '▶ ${info!.url}'
                      : (pathExists ? path : '⚠ 路径不存在'),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: isRunning
                        ? Colors.green.shade400
                        : pathExists
                            ? Colors.white38
                            : Colors.orange,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 操作按钮
          if (isRunning) ...[
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red, size: 26),
              tooltip: '停止',
              onPressed: () => _stopCase(id),
            ),
            if (info?.url != null)
              IconButton(
                icon: const Icon(Icons.open_in_browser,
                    color: Colors.green, size: 22),
                tooltip: '打开浏览器',
                onPressed: () => ProjectDetector.openInBrowser(info!.url!),
              ),
          ] else if (pathExists)
            IconButton(
              icon: Icon(
                isApk ? Icons.android : Icons.play_circle,
                color: isApk ? Colors.green : const Color(0xFF4FC3F7),
                size: 26,
              ),
              tooltip: isApk ? '启动 APK' : '启动',
              onPressed: () => _startCase(c),
            ),
          // 删除
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
            tooltip: '删除',
            onPressed: () => _confirmDelete(id, name),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2530),
        title: const Text('删除案例', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除 "$name" 吗？',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteCase(id);
    }
  }

  Widget _badge(String label, Color? customColor) {
    Color bg, fg;
    final custom = customColor;
    if (custom != null) {
      bg = custom.withValues(alpha: 0.2);
      fg = custom;
    } else if (label.contains('Java') || label.contains('打包')) {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade900;
    } else if (label.contains('Flutter')) {
      bg = Colors.blue.shade100;
      fg = Colors.blue.shade900;
    } else if (label.contains('bat') || label.contains('cmd')) {
      bg = Colors.cyan.shade100;
      fg = Colors.cyan.shade900;
    } else {
      bg = Colors.grey.shade300;
      fg = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
