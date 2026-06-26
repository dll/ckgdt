import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/local/case_dao.dart';
import '../../../services/achievement_context.dart';
import '../../../services/project_detector.dart';
import '../../../services/process_manager_service.dart' as pm;
import '../../../core/error_handler.dart';
import '../../widgets/noir_page_shell.dart';

class CasesPage extends StatefulWidget {
  const CasesPage({super.key});
  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  final CaseDao _caseDao = CaseDao();
  final pm.ProcessManagerService _procMgr = pm.ProcessManagerService.instance;
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;
  String _courseName = '';
  final Set<int> _expandedOutputs = {};
  final Map<int, List<String>> _outputs = {};
  final Map<int, StreamSubscription?> _subs = {};
  bool _vscodeAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadCases();
    _checkVSCode();
    AchievementContext.instance.courseNameNotifier.addListener(_onCourseChanged);
  }

  @override
  void dispose() {
    AchievementContext.instance.courseNameNotifier.removeListener(_onCourseChanged);
    for (final sub in _subs.values) { sub?.cancel(); }
    _procMgr.killAll();
    super.dispose();
  }

  void _onCourseChanged() => _loadCases();

  Future<void> _checkVSCode() async {
    final avail = await ProjectDetector.canOpenInVSCode('');
    if (mounted) setState(() => _vscodeAvailable = avail);
  }

  Future<void> _loadCases() async {
    setState(() => _loading = true);
    try {
      _courseName = AchievementContext.instance.courseName;
      _cases = await _caseDao.getCases();
      for (final c in _cases) {
        final id = c['id'] as int;
        if (_procMgr.isRunning(_procKey(id))) {
          _subscribeOutput(id);
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'CasesPage.loadCases', stack: st);
      _cases = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _procKey(int id) => 'case_$id';

  void _subscribeOutput(int caseId) {
    _subs[caseId]?.cancel();
    _outputs.putIfAbsent(caseId, () => []);
    final sub = _procMgr.subscribe(_procKey(caseId)).listen((line) {
      if (!mounted) return;
      final lines = _outputs[caseId]!;
      lines.add(line);
      if (lines.length > 500) lines.removeRange(0, lines.length - 500);
      if (mounted) setState(() {});
    });
    _subs[caseId] = sub;
  }

  Future<void> _startCase(Map<String, dynamic> c) async {
    final id = c['id'] as int;
    final path = c['project_path']?.toString() ?? '';
    final entryCmd = c['entry_command']?.toString();
    if (path.isEmpty) return;
    _outputs[id] = [];
    _subscribeOutput(id);
    setState(() => _expandedOutputs.add(id));
    final info = ProjectDetector.getProjectInfo(path);
    if (entryCmd != null && entryCmd.isNotEmpty) {
      final parts = entryCmd.split(' ');
      await _procMgr.start(_procKey(id),
        executable: parts.first,
        args: parts.skip(1).toList(),
        workingDirectory: Directory(path).existsSync() ? path : null,
      );
    } else if (info.type == ProjectType.executable) {
      await _procMgr.start(_procKey(id),
        executable: path,
        workingDirectory: Directory(path).parent.existsSync() ? Directory(path).parent.path : null,
      );
    } else if (info.runCommand != null) {
      await _procMgr.start(_procKey(id),
        executable: info.runCommand!,
        args: info.runArgs,
        workingDirectory: path,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _stopCase(int caseId) async {
    await _procMgr.stop(_procKey(caseId));
    _subs[caseId]?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> _buildCase(Map<String, dynamic> c) async {
    final path = c['project_path']?.toString() ?? '';
    if (path.isEmpty) return;
    final id = c['id'] as int;
    final info = ProjectDetector.getProjectInfo(path);
    if (info.buildCommand == null) return;
    _outputs[id] = [];
    _subscribeOutput(id);
    setState(() => _expandedOutputs.add(id));
    await _procMgr.start(_procKey(id),
      executable: info.buildCommand!,
      args: info.buildArgs,
      workingDirectory: path,
    );
    if (mounted) setState(() {});
  }

  void _toggleOutput(int caseId) {
    setState(() {
      if (_expandedOutputs.contains(caseId)) {
        _expandedOutputs.remove(caseId);
      } else {
        _expandedOutputs.add(caseId);
      }
    });
  }

  Future<void> _addCase() async {
    final nameCtrl = TextEditingController();
    final pathCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    String detectedType = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('添加教学案例'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(
                    labelText: '项目名称', isDense: true, hintText: '如：TingChengGIS')),
                const SizedBox(height: 8),
                TextField(controller: pathCtrl, decoration: InputDecoration(
                    labelText: '项目路径',
                    isDense: true,
                    hintText: '如：D:\\development\\TingChengGIS',
                    suffixIcon: detectedType.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(detectedType, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                        : null),
                    onChanged: (v) {
                      if (Directory(v).existsSync()) {
                        final info = ProjectDetector.getProjectInfo(v);
                        setDlgState(() => detectedType = info.label);
                      } else {
                        setDlgState(() => detectedType = '');
                      }
                    }),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(
                    labelText: '描述', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: cmdCtrl, decoration: const InputDecoration(
                    labelText: '启动命令（可选，覆盖自动检测）', isDense: true,
                    hintText: '如：npm run dev')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, {
              'name': nameCtrl.text.trim(),
              'path': pathCtrl.text.trim(),
              'desc': descCtrl.text.trim(),
              'cmd': cmdCtrl.text.trim(),
            }), child: const Text('添加')),
          ],
        ),
      ),
    );
    if (result == null || result['name']?.isEmpty == true) return;
    try {
      await _caseDao.addCase(
        name: result['name']!,
        projectPath: result['path'],
        description: result['desc'],
        entryCommand: result['cmd'],
      );
      await _loadCases();
    } catch (e, st) {
      swallowDebug(e, tag: 'CasesPage.addCase', stack: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteCase(int id) async {
    await _stopCase(id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除案例'),
        content: const Text('确定删除此教学案例吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await _caseDao.deleteCase(id);
    await _loadCases();
  }

  @override
  Widget build(BuildContext context) {
    return NoirPageShell(
      title: '教学案例',
      eyebrow: 'TEACHING CASES',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cases.isEmpty
              ? _buildEmpty()
              : _buildCaseList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade500),
          const SizedBox(height: 16),
          Text(
            _courseName.isEmpty ? '暂无教学案例' : '「$_courseName」暂无教学案例',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('添加教学案例'),
            onPressed: _addCase,
          ),
        ],
      ),
    );
  }

  Widget _buildCaseList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cases.length + 1,
      itemBuilder: (ctx, i) {
        if (i == _cases.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加教学案例'),
              onPressed: _addCase,
            ),
          );
        }
        return _buildCaseCard(_cases[i]);
      },
    );
  }

  Widget _buildCaseCard(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final name = c['name'] ?? '';
    final desc = c['description']?.toString();
    final path = c['project_path']?.toString() ?? '';
    final projectType = c['project_type']?.toString() ?? '';
    final repoUrl = c['repo_url']?.toString();
    final pathExists = path.isNotEmpty && (FileSystemEntity.isFileSync(path) || Directory(path).existsSync());
    final status = _procMgr.getStatus(_procKey(id));
    final isRunning = status == pm.ProcessStatus.running;
    final info = pathExists ? ProjectDetector.getProjectInfo(path) : null;
    final typeLabel = projectType.isNotEmpty ? projectType : (info?.label ?? '');
    final outputExpanded = _expandedOutputs.contains(id);
    final outputLines = _outputs[id] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
            child: Row(
              children: [
                _statusIcon(isRunning, status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (desc != null && desc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ),
                    ],
                  ),
                ),
                if (typeLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(typeLabel, style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.red.shade300,
                  tooltip: '删除',
                  onPressed: () => _deleteCase(id),
                ),
              ],
            ),
          ),
          if (path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(path, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontFamily: 'monospace')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (isRunning)
                  _actionBtn(Icons.stop, '停止', Colors.red.shade400, () => _stopCase(id))
                else if (pathExists)
                  _actionBtn(Icons.play_arrow, '启动', Colors.green.shade600, () => _startCase(c)),
                if (pathExists && info?.buildCommand != null && !isRunning)
                  _actionBtn(Icons.build, '构建', Colors.indigo, () => _buildCase(c)),
                if (pathExists && _vscodeAvailable)
                  _actionBtn(Icons.code, 'VS Code', Colors.blue.shade600, () => ProjectDetector.openInVSCode(path)),
                if (pathExists)
                  _actionBtn(Icons.folder_open, '文件夹', Colors.brown, () => ProjectDetector.openInExplorer(path)),
                if (repoUrl != null && repoUrl.isNotEmpty)
                  _actionBtn(Icons.link, '仓库', Colors.blue.shade400, () => Process.run('start', [repoUrl])),
                if (outputLines.isNotEmpty || isRunning)
                  _actionBtn(
                    outputExpanded ? Icons.expand_less : Icons.expand_more,
                    outputExpanded ? '收起输出' : '输出 (${outputLines.length})',
                    Colors.grey.shade600,
                    () => _toggleOutput(id),
                  ),
              ],
            ),
          ),
          if (outputExpanded && outputLines.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: outputLines.length,
                itemBuilder: (ctx, i) {
                  final line = outputLines[i];
                  final isError = line.contains('error') || line.contains('Error');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isError ? Colors.red.shade300 : Colors.green.shade200,
                        height: 1.3,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusIcon(bool isRunning, pm.ProcessStatus status) {
    if (isRunning) {
      return const SizedBox(
        width: 12, height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
      );
    }
    return Icon(
      status == pm.ProcessStatus.failed ? Icons.error_outline : Icons.circle,
      size: 12,
      color: status == pm.ProcessStatus.failed ? Colors.red : Colors.grey.shade400,
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onPressed) {
    return TextButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    );
  }
}
