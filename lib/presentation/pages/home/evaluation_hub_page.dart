import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import '../lab/lab_tasks_page.dart';
import '../assessment/assessment_page.dart';
import '../works/works_page.dart';
import '../learning/homework_grading_page.dart';
import '../../../data/local/assessment_dao.dart';
import '../../../data/local/classroom_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/course_context_service.dart';
import '../../../services/course_terminology_service.dart';
import '../../../services/achievement_context.dart';
import '../../../core/error_handler.dart';
import '../../../services/navigation_service.dart';

/// 评价中心 — 聚合实验、考核、作品三个模块（教师端 Tab 精简）
class EvaluationHubPage extends StatefulWidget {
  const EvaluationHubPage({super.key});

  @override
  State<EvaluationHubPage> createState() => _EvaluationHubPageState();
}

class _EvaluationHubPageState extends State<EvaluationHubPage> {
  int _subIndex = 0;
  CourseTerms? _terms;

  @override
  void initState() {
    super.initState();
    NavigationService.instance.innerTabSeq.addListener(_applyInnerTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyInnerTab();
      _loadTerminology();
    });
    AchievementContext.instance.courseNameNotifier.addListener(_onCourseChanged);
  }

  @override
  void dispose() {
    NavigationService.instance.innerTabSeq.removeListener(_applyInnerTab);
    AchievementContext.instance.courseNameNotifier.removeListener(_onCourseChanged);
    super.dispose();
  }

  void _onCourseChanged() {
    _loadTerminology();
  }

  Future<void> _loadTerminology() async {
    try {
      final terms = await CourseTerminologyService().activeTerms();
      if (mounted) setState(() => _terms = terms);
    } catch (_) {}
  }

  List<String> get _subLabels {
    final practice = _terms?.practiceLabel ?? '实验';
    return [practice, '考核', '作业', '作品'];
  }

  void _applyInnerTab() {
    if (!mounted) return;
    final req = NavigationService.instance.consumeInnerTab('evaluation');
    if (req == null) return;
    final labels = _subLabels;
    for (int i = 0; i < labels.length; i++) {
      if (req.tabKeyword.contains(labels[i]) ||
          labels[i].contains(req.tabKeyword)) {
        setState(() => _subIndex = i);
        return;
      }
    }
  }

  Future<void> _importExperimentGroups() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      if (f.bytes == null) throw StateError('无法读取文件');

      final excel = xl.Excel.decodeBytes(f.bytes!);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.maxRows < 2) {
        _showMsg('Excel文件为空', true); return;
      }

      final header = sheet.row(0);
      int idCol = -1, nameCol = -1, repoCol = -1, projCol = -1, roleCol = -1, techCol = -1;
      for (int i = 0; i < header.length; i++) {
        final h = (header[i]?.value?.toString() ?? '').replaceAll(RegExp(r'[\r\n]'), '');
        if (h.contains('学号')) idCol = i;
        if (h.contains('姓名')) nameCol = i;
        if (h.contains('分库') || h.contains('仓库')) repoCol = i;
        if (h.contains('项目')) projCol = i;
        if (h.contains('角色')) roleCol = i;
        if (h.contains('技术栈')) techCol = i;
      }
      if (idCol < 0 || projCol < 0) {
        _showMsg('未找到学号或项目列', true); return;
      }

      final db = await DatabaseHelper.instance.database;
      final courseId = await CourseContextService().activeCourseId();
      final assessmentDao = AssessmentDao();

      // 收集唯一项目 → 创建考核分组
      final projectGroups = <String, List<Map<String, String>>>{};
      final userIdToRepo = <String, String>{};

      for (int r = 1; r < sheet.maxRows; r++) {
        final row = sheet.row(r);
        final sid = row[idCol]?.value?.toString().trim() ?? '';
        final name = nameCol >= 0 ? (row[nameCol]?.value?.toString().trim() ?? '') : '';
        final repo = repoCol >= 0 ? (row[repoCol]?.value?.toString().trim() ?? '') : '';
        final proj = projCol >= 0 ? (row[projCol]?.value?.toString().trim() ?? '') : '';
        final role = roleCol >= 0 ? (row[roleCol]?.value?.toString().trim() ?? '') : '';
        final tech = techCol >= 0 ? (row[techCol]?.value?.toString().trim() ?? '') : '';
        if (sid.isEmpty || proj.isEmpty) continue;

        // 记录仓库信息（用于更新 user 表）
        if (repo.isNotEmpty) {
          userIdToRepo[sid] = repo;
        }

        projectGroups.putIfAbsent(proj, () => []).add({
          'id': sid, 'name': name, 'role': role, 'tech': tech,
        });
      }

      // 更新用户的 repository_url
      for (final e in userIdToRepo.entries) {
        await db.update('users', {'repository_url': e.value},
            where: 'user_id = ?', whereArgs: [e.key]);
      }

      int groupCount = 0, memberCount = 0;
      for (final proj in projectGroups.entries) {
        final members = proj.value;
        final groupId = await assessmentDao.addGroup(
          name: proj.key,
          projectName: proj.key,
          memberIds: members.map((m) => m['id']!).toList(),
          memberNames: members.map((m) => m['name']!).toList(),
          leader: members.firstWhere((m) => m['role']!.contains('组长'),
              orElse: () => members.first)['id'],
        );
        groupCount++;

        // 创建考核项目
        await assessmentDao.addProject(
          groupId: groupId,
          name: proj.key,
          techStack: members.firstWhere((m) => (m['tech'] ?? '').isNotEmpty,
              orElse: () => const {})['tech'],
          description: '成员：${members.map((m) => '${m['name']}(${m['role']})').join('、')}',
        );
        memberCount += members.length;
      }

      _showMsg('导入完成：$groupCount 个项目组，$memberCount 名学生');
    } catch (e, st) {
      swallowDebug(e, tag: 'EvalHub.importGroups', stack: st);
      _showMsg('导入失败: $e', true);
    }
  }

  void _showMsg(String msg, [bool err = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg),
          backgroundColor: err ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Container(
          color: primary.withOpacity(0.05),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.science, size: 16),
                        label: Text(_terms?.practiceLabel ?? '实验')),
                    const ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.assessment, size: 16),
                        label: Text('考核')),
                    const ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.assignment, size: 16),
                        label: Text('作业')),
                    const ButtonSegment(
                        value: 3,
                        icon: Icon(Icons.workspace_premium, size: 16),
                        label: Text('作品')),
                  ],
                  selected: {_subIndex},
                  onSelectionChanged: (s) =>
                      setState(() => _subIndex = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 13, color: primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.upload_file, size: 20),
                tooltip: '导入${_terms?.taskLabel ?? '实验'}分组Excel',
                onPressed: _importExperimentGroups,
                style: IconButton.styleFrom(foregroundColor: primary),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _subIndex,
            children: const [
              LabTasksPage(),
              AssessmentPage(),
              HomeworkGradingPage(),
              WorksPage(),
            ],
          ),
        ),
      ],
    );
  }
}
