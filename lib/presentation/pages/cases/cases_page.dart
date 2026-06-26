import 'dart:io';
import 'package:flutter/material.dart';
import '../../../data/local/case_dao.dart';
import '../../../services/achievement_context.dart';
import '../../../core/error_handler.dart';
import '../../widgets/noir_page_shell.dart';

/// 教学案例页 — 展示当前课程的教师演示项目（课程隔离）
class CasesPage extends StatefulWidget {
  const CasesPage({super.key});

  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  final CaseDao _caseDao = CaseDao();
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;
  String _courseName = '';

  @override
  void initState() {
    super.initState();
    _loadCases();
    AchievementContext.instance.courseNameNotifier.addListener(_onCourseChanged);
  }

  @override
  void dispose() {
    AchievementContext.instance.courseNameNotifier.removeListener(_onCourseChanged);
    super.dispose();
  }

  void _onCourseChanged() {
    _loadCases();
  }

  Future<void> _loadCases() async {
    setState(() => _loading = true);
    try {
      _courseName = AchievementContext.instance.courseName;
      _cases = await _caseDao.getCases();
    } catch (e, st) {
      swallowDebug(e, tag: 'CasesPage.loadCases', stack: st);
      _cases = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCase() async {
    final nameCtrl = TextEditingController();
    final pathCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加教学案例'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(
                labelText: '项目名称（如：TingChengGIS）', isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: pathCtrl, decoration: const InputDecoration(
                labelText: '演示程序路径（.exe）', isDense: true,
                hintText: '如：D:\\projects\\Demo.exe')),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(
                labelText: '描述', isDense: true)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, {
            'name': nameCtrl.text.trim(),
            'path': pathCtrl.text.trim(),
            'desc': descCtrl.text.trim(),
          }), child: const Text('添加')),
        ],
      ),
    );
    if (result == null || result['name']?.isEmpty == true) return;
    try {
      await _caseDao.addCase(
        name: result['name']!,
        projectPath: result['path'],
        description: result['desc'],
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
          Icon(Icons.folder_open, size: 64,
              color: Colors.grey.shade500),
          const SizedBox(height: 16),
          Text(
            _courseName.isEmpty
                ? '暂无教学案例'
                : '「$_courseName」暂无教学案例',
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
      itemCount: _cases.length + 1, // +1 for add button
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
    final name = c['name'] ?? '';
    final fullName = c['full_name']?.toString();
    final desc = c['description']?.toString();
    final path = c['project_path']?.toString() ?? '';
    final repoUrl = c['repo_url']?.toString();
    final dirExists = path.isNotEmpty && Directory(path).existsSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(dirExists ? Icons.folder : Icons.folder_off,
                    color: dirExists ? const Color(0xFF4CAF50) : Colors.grey, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (fullName != null && fullName.isNotEmpty)
                        Text(fullName,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red.shade400,
                  tooltip: '删除',
                  onPressed: () => _deleteCase(c['id'] as int),
                ),
              ],
            ),
            if (desc != null && desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (path.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: dirExists ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(dirExists ? Icons.check_circle : Icons.error,
                            size: 14, color: dirExists ? const Color(0xFF4CAF50) : Colors.red),
                        const SizedBox(width: 4),
                        Text(dirExists ? '就绪' : '文件不存在',
                            style: TextStyle(
                                fontSize: 12,
                                color: dirExists ? Colors.green.shade700 : Colors.red.shade700)),
                      ],
                    ),
                  ),
                const Spacer(),
                if (path.isNotEmpty && dirExists)
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('启动演示'),
                    onPressed: () {
                      Process.run(path, [], runInShell: true);
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                if (path.isNotEmpty && !dirExists)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('定位文件'),
                    onPressed: () {
                      final dir = File(path).parent.path;
                      if (Directory(dir).existsSync()) {
                        Process.run('explorer', ['/select,', path]);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (repoUrl != null && repoUrl.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.link, size: 20),
                    tooltip: '仓库地址',
                    onPressed: () => Process.run('start', [repoUrl]),
                  ),
                ],
              ],
            ),
            if (path.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(path,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                        fontFamily: 'monospace')),
              ),
          ],
        ),
      ),
    );
  }
}
