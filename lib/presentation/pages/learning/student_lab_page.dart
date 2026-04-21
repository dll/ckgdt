import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/local/lab_task_dao.dart';
import '../../../services/auth_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/sync_service.dart';
import '../lab/lab_material_preview_page.dart';
import '../../widgets/agent_entry_button.dart';

/// 学生实验中心 — 查看实验任务、提交作业、查看成绩
class StudentLabPage extends StatefulWidget {
  const StudentLabPage({super.key});

  @override
  State<StudentLabPage> createState() => _StudentLabPageState();
}

class _StudentLabPageState extends State<StudentLabPage> {
  final _dao = LabTaskDao();
  final _authService = AuthService();

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _mySubmissions = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  String get _userId => _authService.currentUser?.userId ?? '';

  /// 验证实验报告文件名：必须为 学号+姓名+任务名称.pdf
  String? _validateFileName(String fileName, String taskTitle) {
    final userId = _userId;
    final realName = _authService.currentUser?.realName ?? '';
    if (userId.isEmpty || realName.isEmpty) {
      return '提交失败：无法获取当前用户信息，请重新登录';
    }

    // 去掉扩展名
    final baseName = fileName.endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    // 检查非法后缀：(1) (2) 1 2 new copy 副本 - 复制 等
    if (RegExp(r'[\(\（]\d+[\)\）]$').hasMatch(baseName) ||
        RegExp(r'[_\-\s]?\d+$').hasMatch(baseName) &&
            !baseName.endsWith(taskTitle) ||
        RegExp(r'(new|copy|副本|复制|备份)', caseSensitive: false)
            .hasMatch(baseName)) {
      return '提交失败：文件名不规范，不允许包含(1)、new、copy、副本等后缀\n'
          '正确格式：$userId$realName$taskTitle.pdf';
    }

    // 检查学号是否匹配当前登录用户
    if (!baseName.startsWith(userId)) {
      return '提交失败：文件名中的学号与当前登录用户不匹配\n'
          '正确格式：$userId$realName$taskTitle.pdf';
    }

    // 检查是否包含姓名
    if (!baseName.contains(realName)) {
      return '提交失败：文件名中未包含姓名"$realName"\n'
          '正确格式：$userId$realName$taskTitle.pdf';
    }

    // 检查是否包含任务名称
    if (!baseName.contains(taskTitle)) {
      return '提交失败：文件名中未包含实验名称"$taskTitle"\n'
          '正确格式：$userId$realName$taskTitle.pdf';
    }

    // 严格匹配：学号+姓名+任务名称
    final expected = '$userId$realName$taskTitle';
    if (baseName != expected) {
      return '提交失败：文件命名不规范\n'
          '正确格式：$userId$realName$taskTitle.pdf';
    }

    return null; // 验证通过
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _dao.initDemoDataIfEmpty();
      final tasks = await _dao.getTasks(status: 'active');
      final subs = await _dao.getSubmissions(userId: _userId);
      final stats = await _dao.getStudentLabStats(_userId);
      setState(() {
        _tasks = tasks;
        _mySubmissions = subs;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的实验'),
        actions: const [
          AgentEntryButton(agentId: 'lab'),
          SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 统计卡片
            _buildStatsCard(),
            const SizedBox(height: 16),
            // 实验材料快捷入口
            _buildMaterialsCard(),
            const SizedBox(height: 16),
            // 实验任务列表
            const Text('实验任务',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._tasks.map(_buildTaskItem),
            if (_tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.assignment, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text('暂无实验任务',
                          style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final submitted = _stats['submitted_tasks'] ?? 0;
    final total = _stats['total_tasks'] ?? 0;
    final avgScore = _stats['avg_score'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _statItem(
                Icons.assignment_turned_in,
                '$submitted / $total',
                '已提交',
                Colors.blue,
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey[200]),
            Expanded(
              child: _statItem(
                Icons.score,
                avgScore != null
                    ? (avgScore as num).toStringAsFixed(1)
                    : '--',
                '平均分',
                Colors.green,
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey[200]),
            Expanded(
              child: _statItem(
                Icons.grading,
                '${_stats['graded_count'] ?? 0}',
                '已批改',
                Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildMaterialsCard() {
    const categories = [
      {'icon': Icons.school, 'title': '实验教程', 'color': Color(0xFF667eea),
       'dir': 'data/实验/实验教程/', 'desc': '6个实验的步骤教程'},
      {'icon': Icons.layers, 'title': '移动技术栈', 'color': Color(0xFF764ba2),
       'dir': 'data/实验/移动技术栈/', 'desc': '主流技术手册'},
      {'icon': Icons.menu_book, 'title': '实验指导', 'color': Colors.teal,
       'dir': 'data/实验/实验指导/', 'desc': '实验指导书'},
      {'icon': Icons.assignment, 'title': '报告模板', 'color': Colors.orange,
       'dir': 'data/实验/报告模板/', 'desc': '报告填写模板'},
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book, size: 18, color: Color(0xFF667eea)),
                const SizedBox(width: 6),
                const Text('实验材料',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const _StudentMaterialsPage(),
                      ),
                    );
                  },
                  child: const Text('查看全部', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: categories.map((cat) {
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _StudentMaterialsPage(
                            initialCategory: categories.indexOf(cat),
                          ),
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (cat['color'] as Color)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(cat['icon'] as IconData,
                              color: cat['color'] as Color, size: 20),
                        ),
                        const SizedBox(height: 4),
                        Text(cat['title'] as String,
                            style: const TextStyle(fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(Map<String, dynamic> task) {
    // Find my submission for this task
    final mySub = _mySubmissions.where((s) => s['task_id'] == task['id']).toList();
    final hasSubmitted = mySub.isNotEmpty;
    final score = hasSubmitted ? mySub.first['score'] as int? : null;

    final difficulty = task['difficulty'] as String? ?? '中等';
    final diffColor = difficulty == '简单'
        ? Colors.green
        : difficulty == '较难'
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (hasSubmitted ? Colors.green : Colors.blue)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            hasSubmitted ? Icons.check_circle : Icons.assignment,
            color: hasSubmitted ? Colors.green : Colors.blue,
            size: 22,
          ),
        ),
        title: Text(
          task['title'] as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: diffColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(difficulty,
                  style: TextStyle(fontSize: 10, color: diffColor)),
            ),
            const SizedBox(width: 6),
            if (score != null)
              Text('得分：$score',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.w500))
            else if (hasSubmitted)
              const Text('已提交·待批改',
                  style: TextStyle(fontSize: 11, color: Colors.orange))
            else
              const Text('未提交',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((task['description'] as String?)?.isNotEmpty == true) ...[
                  Text(task['description'] as String,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                if ((task['requirements'] as String?)?.isNotEmpty == true) ...[
                  const Text('实验要求：',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(task['requirements'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[700])),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '截止：${(task['due_date'] as String? ?? '').split('T').first}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
                // 批改反馈
                if (hasSubmitted && mySub.first['feedback'] != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.rate_review,
                          size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      const Text('教师批改反馈：',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(mySub.first['feedback'] as String,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          _showSubmitDialog(task, hasSubmitted ? mySub.first : null),
                      icon: Icon(hasSubmitted ? Icons.edit : Icons.upload,
                          size: 16),
                      label:
                          Text(hasSubmitted ? '重新提交' : '提交作业'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSubmitDialog(
      Map<String, dynamic> task, Map<String, dynamic>? existing) async {
    String? selectedFilePath;
    String? selectedFileName;

    // 如果已提交过文件，显示已有文件名
    if (existing != null && existing['file_names'] != null) {
      selectedFileName = existing['file_names'] as String;
      selectedFilePath = existing['file_paths'] as String?;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('提交 - ${task['title']}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // PDF 选择区域
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                      dialogTitle: '选择 PDF 实验报告',
                    );
                    if (result != null && result.files.single.path != null) {
                      final pickedName = result.files.single.name;
                      final error = _validateFileName(
                          pickedName, task['title'] as String? ?? '');
                      if (error != null) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                        return;
                      }
                      setDialogState(() {
                        selectedFilePath = result.files.single.path!;
                        selectedFileName = result.files.single.name;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: selectedFilePath != null
                          ? const Color(0xFF667eea).withValues(alpha: 0.05)
                          : Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedFilePath != null
                            ? const Color(0xFF667eea).withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.3),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: selectedFilePath != null
                        ? Row(
                            children: [
                              const Icon(Icons.picture_as_pdf,
                                  color: Colors.red, size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedFileName ?? 'PDF文件',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (selectedFilePath != null)
                                      FutureBuilder<int>(
                                        future: File(selectedFilePath!).length(),
                                        builder: (_, snap) => Text(
                                          snap.hasData
                                              ? '${(snap.data! / 1024 / 1024).toStringAsFixed(1)} MB'
                                              : '',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500]),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.swap_horiz, size: 20),
                                tooltip: '重新选择',
                                onPressed: () async {
                                  final result =
                                      await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['pdf'],
                                  );
                                  if (result != null &&
                                      result.files.single.path != null) {
                                    final pickedName =
                                        result.files.single.name;
                                    final error = _validateFileName(
                                        pickedName,
                                        task['title'] as String? ?? '');
                                    if (error != null) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(error),
                                            backgroundColor: Colors.red,
                                            duration:
                                                const Duration(seconds: 4),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    setDialogState(() {
                                      selectedFilePath =
                                          result.files.single.path!;
                                      selectedFileName =
                                          result.files.single.name;
                                    });
                                  }
                                },
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Icon(Icons.upload_file,
                                  size: 40,
                                  color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                '点击选择 PDF 实验报告',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey[600]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '仅支持 PDF 格式',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[400]),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: selectedFilePath == null
                  ? null
                  : () async {
                      await _dao.submitTask(
                        taskId: task['id'] as int,
                        userId: _userId,
                        content: 'PDF实验报告：$selectedFileName',
                        filePaths: selectedFilePath,
                        fileNames: selectedFileName,
                      );
                      // 通知教师
                      NotificationService().notifyLabSubmission(
                        studentId: _userId,
                        studentName: _authService.currentUser?.realName ?? _userId,
                        taskTitle: task['title'] as String? ?? '实验任务',
                        taskId: task['id'] as int,
                      );
                      // 立即触发同步上传（不等定时器）
                      unawaited(SyncService().uploadStudentData(_userId));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('提交成功！')),
                        );
                      }
                      _loadData();
                    },
              child: const Text('确认提交'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 学生实验材料浏览页面
// ══════════════════════════════════════════════════════════════════════════════

class _StudentMaterialsPage extends StatefulWidget {
  final int initialCategory;
  const _StudentMaterialsPage({this.initialCategory = 0});

  @override
  State<_StudentMaterialsPage> createState() => _StudentMaterialsPageState();
}

class _StudentMaterialsPageState extends State<_StudentMaterialsPage> {
  static const _categories = [
    {'title': '实验教程', 'icon': Icons.school, 'color': Color(0xFF667eea),
     'dir': 'data/实验/实验教程/',
     'desc': '6 个实验的详细步骤教程'},
    {'title': '移动技术栈', 'icon': Icons.layers, 'color': Color(0xFF764ba2),
     'dir': 'data/实验/移动技术栈/',
     'desc': '覆盖 Kotlin/Swift/Flutter/ArkUI 等主流技术手册'},
    {'title': '实验指导', 'icon': Icons.menu_book, 'color': Colors.teal,
     'dir': 'data/实验/实验指导/',
     'desc': '实验指导书及 UML 设计文档参考'},
    {'title': '报告模板', 'icon': Icons.assignment, 'color': Colors.orange,
     'dir': 'data/实验/报告模板/',
     'desc': '每个实验对应的报告模板'},
  ];

  final Map<int, List<Map<String, String>>> _files = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    try {
      final manifestContent =
          await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(manifestContent);

      for (int i = 0; i < _categories.length; i++) {
        final dir = _categories[i]['dir'] as String;
        final files = manifest.keys
            .where((k) => k.startsWith(dir) && k.endsWith('.md'))
            .map((assetPath) {
          final fileName = Uri.decodeFull(assetPath.split('/').last);
          final displayName =
              fileName.replaceAll('_new.md', '').replaceAll('.md', '');
          return {'assetPath': assetPath, 'displayName': displayName};
        }).toList();
        files.sort(
            (a, b) => a['displayName']!.compareTo(b['displayName']!));
        _files[i] = files;
      }
    } catch (e) {
      debugPrint('加载实验材料失败: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实验材料'),
        actions: const [
          AgentEntryButton(agentId: 'lab'),
          SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _categories.length,
              itemBuilder: (context, catIdx) {
                final cat = _categories[catIdx];
                final files = _files[catIdx] ?? [];
                final color = cat['color'] as Color;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(cat['icon'] as IconData,
                          color: color, size: 22),
                    ),
                    title: Row(
                      children: [
                        Text(cat['title'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${files.length}',
                              style: TextStyle(fontSize: 11, color: color)),
                        ),
                      ],
                    ),
                    subtitle: Text(cat['desc'] as String,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    initiallyExpanded: catIdx == widget.initialCategory,
                    children: [
                      ...files.map((file) => ListTile(
                            dense: true,
                            leading:
                                Icon(Icons.article, color: color, size: 20),
                            title: Text(file['displayName']!,
                                style: const TextStyle(fontSize: 13)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.visibility,
                                      size: 18, color: color),
                                  tooltip: '在线预览',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            LabMaterialPreviewPage(
                                          assetPath: file['assetPath'],
                                          title: file['displayName']!,
                                          agentId: 'lab',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.download,
                                      size: 18, color: Colors.grey),
                                  tooltip: '下载到本地',
                                  onPressed: () =>
                                      _downloadFile(file),
                                ),
                              ],
                            ),
                          )),
                      if (files.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('暂无材料',
                              style: TextStyle(color: Colors.grey[400])),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _downloadFile(Map<String, String> file) async {
    try {
      final content = await rootBundle.loadString(file['assetPath']!);
      final dir = await getApplicationDocumentsDirectory();
      final labDir = Directory('${dir.path}/lab_materials');
      if (!await labDir.exists()) {
        await labDir.create(recursive: true);
      }
      final saveName =
          file['displayName']!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final saveFile = File('${labDir.path}/$saveName.md');
      await saveFile.writeAsString(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载: ${saveFile.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
