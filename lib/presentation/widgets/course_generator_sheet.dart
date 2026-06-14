// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/local/course_dao.dart';
import '../../data/local/database_helper.dart';
import '../../data/local/graph_dao.dart';
import '../../data/local/knowledge_graph_dao.dart';
import '../../data/local/lab_task_dao.dart';
import '../../data/models/course_model.dart';
import '../../data/models/edge_model.dart';
import '../../data/models/graph_model.dart';
import '../../data/models/node_model.dart';
import '../../data/models/syllabus_data.dart';
import '../../services/ai_service.dart';
import '../../services/course_context_service.dart';
import '../../services/syllabus_parser.dart';

/// 一键生课 — 底部弹出表单
class CourseGeneratorSheet extends StatefulWidget {
  const CourseGeneratorSheet({super.key});

  @override
  State<CourseGeneratorSheet> createState() => _CourseGeneratorSheetState();
}

class _CourseGeneratorSheetState extends State<CourseGeneratorSheet> {
  final _nameController = TextEditingController();
  int _chapterCount = 6;
  bool _isGenerating = false;
  String _progress = '';
  final List<String> _logs = [];
  String? _outlineContent;
  String? _outlineFileName;
  SyllabusData? _parsedSyllabus;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomPadding + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖动手柄
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 标题
            Text(
              '一键生课',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'AI 自动生成完整课程体系：大纲、章节、题库、资源',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 课程名称
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '课程名称',
                hintText: '例如：Web 前端开发',
                prefixIcon: const Icon(Icons.school),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              enabled: !_isGenerating,
            ),
            const SizedBox(height: 16),

            // 课程大纲（文件上传，支持 .docx / .txt / .md）
            InkWell(
              onTap: _isGenerating ? null : _pickOutlineFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _parsedSyllabus != null
                        ? Colors.green
                        : (_outlineContent != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline),
                    width: _parsedSyllabus != null || _outlineContent != null
                        ? 2
                        : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: _parsedSyllabus != null
                      ? Colors.green.withValues(alpha: 0.1)
                      : (_outlineContent != null
                          ? theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.3)
                          : null),
                ),
                child: Row(
                  children: [
                    Icon(
                      _parsedSyllabus != null
                          ? Icons.description
                          : (_outlineContent != null
                              ? Icons.check_circle
                              : Icons.upload_file),
                      color: _parsedSyllabus != null
                          ? Colors.green
                          : (_outlineContent != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _outlineFileName ?? '上传教学大纲',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _parsedSyllabus != null
                                  ? Colors.green.shade700
                                  : (_outlineContent != null
                                      ? theme.colorScheme.primary
                                      : null),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _parsedSyllabus != null
                                ? '已解析：${_parsedSyllabus!.chapters.length}章 · ${_parsedSyllabus!.labs.length}个实验 · ${_parsedSyllabus!.objectives.length}个目标'
                                : (_outlineContent != null
                                    ? '已加载 ${_outlineContent!.length} 字'
                                    : '上传 .docx 教学大纲文件（推荐），不传则 AI 自动生成'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _parsedSyllabus != null
                                  ? Colors.green.shade600
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_outlineContent != null || _parsedSyllabus != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _isGenerating
                            ? null
                            : () => setState(() {
                                  _outlineContent = null;
                                  _outlineFileName = null;
                                  _parsedSyllabus = null;
                                }),
                        tooltip: '移除大纲',
                      ),
                  ],
                ),
              ),
            ),
            if (_parsedSyllabus != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip(theme, '${_parsedSyllabus!.chapters.length} 章',
                      Icons.menu_book),
                  _chip(theme, '${_parsedSyllabus!.labs.length} 个实验',
                      Icons.science),
                  _chip(
                      theme,
                      '${_parsedSyllabus!.lectureHours}+${_parsedSyllabus!.labHours} 学时',
                      Icons.schedule),
                  _chip(
                      theme,
                      '${(_parsedSyllabus!.assessment.dailyWeight * 100).toInt()}%平时/${(_parsedSyllabus!.assessment.labWeight * 100).toInt()}%实验/${(_parsedSyllabus!.assessment.examWeight * 100).toInt()}%期末',
                      Icons.balance),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // 章节数量
            Row(
              children: [
                const Icon(Icons.format_list_numbered, size: 20),
                const SizedBox(width: 8),
                Text('章节数量：', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: _chapterCount.toDouble(),
                    min: 4,
                    max: 12,
                    divisions: 8,
                    label: '$_chapterCount 章',
                    onChanged: _isGenerating
                        ? null
                        : (v) => setState(() => _chapterCount = v.toInt()),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_chapterCount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 生成进度
            if (_isGenerating || _logs.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isGenerating)
                      Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _progress,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_logs.isNotEmpty) ...[
                      if (_isGenerating) const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          reverse: true,
                          itemCount: _logs.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              _logs[_logs.length - 1 - i],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 生成按钮
            FilledButton.icon(
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isGenerating ? '生成中...' : '开始生成'),
              onPressed: _isGenerating ? null : _generateCourse,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: Colors.green.shade700)),
        ],
      ),
    );
  }

  Future<void> _pickOutlineFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'docx'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final fileName = result.files.single.name;
      final file = File(filePath);

      if (fileName.endsWith('.docx')) {
        final parser = SyllabusParser();
        final syllabus = await parser.parseFile(filePath);
        setState(() {
          _parsedSyllabus = syllabus;
          _outlineFileName = fileName;
          _outlineContent = syllabus.description;
          _chapterCount = syllabus.chapters.length;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '已解析教学大纲：${syllabus.chapters.length}章 · ${syllabus.labs.length}个实验'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final content = await file.readAsString();
        if (content.trim().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件内容为空，请选择包含大纲内容的文件')),
            );
          }
          return;
        }
        setState(() {
          _outlineContent = content;
          _outlineFileName = fileName;
          _parsedSyllabus = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败：$e')),
        );
      }
    }
  }

  void _log(String msg) {
    setState(() {
      _logs.add(msg);
      _progress = msg;
    });
  }

  Future<void> _generateCourse() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入课程名称')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _logs.clear();
    });

    try {
      final aiService = AiService();
      final db = await DatabaseHelper.instance.database;

      // ═══ 步骤 1：确定章节列表 ═══
      // 当上传了 DOCX 大纲时直接用解析结果，否则靠 AI 生成
      List<String> chapters;
      List<SyllabusChapter> syllabusChapters;
      List<SyllabusLab> syllabusLabs;
      AssessmentStructure assessment;

      if (_parsedSyllabus != null) {
        _log('使用教学大纲中的 ${_parsedSyllabus!.chapters.length} 个章节');
        syllabusChapters = _parsedSyllabus!.chapters;
        syllabusLabs = _parsedSyllabus!.labs;
        assessment = _parsedSyllabus!.assessment;
        if (assessment.dailyWeight > 0 ||
            assessment.labWeight > 0 ||
            assessment.examWeight > 0) {
          _log(
              '考核方式：平时${(assessment.dailyWeight * 100).toInt()}% · 实验${(assessment.labWeight * 100).toInt()}% · 期末${(assessment.examWeight * 100).toInt()}%');
        }
        chapters =
            syllabusChapters.map((c) => '第${c.index}章 ${c.title}').toList();
      } else {
        syllabusChapters = [];
        syllabusLabs = [];
        assessment = const AssessmentStructure();

        final outline = _outlineContent?.trim() ?? '';
        final hasOutline = outline.isNotEmpty;
        _log(hasOutline ? '正在基于大纲生成课程章节...' : '正在由 AI 生成课程章节...');

        final prompt = hasOutline
            ? '''
请基于以下课程大纲，为《$name》课程提取或整理出 $_chapterCount 个章节标题。

=== 课程大纲 ===
$outline
=== 大纲结束 ===

要求：
1. 章节标题简洁明确（10-20 字）
2. 忠实于大纲内容，按照大纲的结构和顺序组织
3. 如果大纲章节数与要求的 $_chapterCount 章不同，请合理拆分或合并
4. 保留大纲中的核心知识点和教学重点

请严格按以下 JSON 格式输出（不要包含其他文字）：
{"chapters": ["第1章标题", "第2章标题", ...]}
'''
            : '''
为《$name》课程设计 $_chapterCount 个章节标题。

要求：
1. 章节标题简洁明确（10-20 字）
2. 内容循序渐进，从基础到进阶
3. 涵盖该课程的核心知识领域
4. 兼顾理论与实践

请严格按以下 JSON 格式输出（不要包含其他文字）：
{"chapters": ["第1章标题", "第2章标题", ...]}
''';

        final resp = await aiService.chat([
          {'role': 'user', 'content': prompt}
        ]);
        chapters = _parseChapters(resp, _chapterCount);
        _log('大纲生成完成：${chapters.length} 个章节');
      }

      // ═══ 步骤 2：保存课程到数据库 ═══
      _log('正在保存课程...');
      final courseDao = CourseDao();
      final baseCourseId = CourseContextService.buildStableCourseId(name);
      var courseId = baseCourseId;
      var suffix = 2;
      while (await courseDao.getCourse(courseId) != null) {
        courseId = '${baseCourseId}_$suffix';
        suffix++;
      }
      final now = DateTime.now().toIso8601String();
      final hasSyllabus = _parsedSyllabus != null;

      final course = CourseModel(
        id: courseId,
        name: name,
        description: hasSyllabus
            ? _parsedSyllabus!.description.isNotEmpty
                ? _parsedSyllabus!.description
                : '基于教学大纲生成的$name课程'
            : 'AI 自动生成的$name课程',
        chapterCount: chapters.length,
        chapters: chapters,
        isActive: true,
        createdAt: now,
      );

      await courseDao.addCourse(course);
      await courseDao.setActiveCourse(course.id);
      _log('课程保存成功');

      // ═══ 步骤 3：生成各章节测验题 ═══
      _log('正在生成章节测验题（每章5题）...');
      int totalQuestions = 0;

      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        final chContent =
            i < syllabusChapters.length ? syllabusChapters[i].content : '';
        final chObjectives = i < syllabusChapters.length
            ? syllabusChapters[i].teachingObjectives
            : '';
        final chKeyPoints =
            i < syllabusChapters.length ? syllabusChapters[i].keyPoints : '';

        final extraContext = hasSyllabus && chContent.isNotEmpty
            ? '\n\n章节教学内容：$chContent\n章节目标：$chObjectives\n教学重点：$chKeyPoints'
            : '';

        final quizPrompt = '为《$name》课程的"$chapter"章节生成5道选择题。$extraContext\n\n'
            '请严格按以下JSON格式输出（不要包含其他文字）：\n'
            '[{"question":"题目","option_a":"A","option_b":"B","option_c":"C","option_d":"D","answer_index":0}]\n\n'
            '要求：answer_index 为正确答案索引（0=A,1=B,2=C,3=D），题目难度适中。';

        try {
          final quizRaw = await aiService.chat(
            [
              {'role': 'user', 'content': quizPrompt}
            ],
            systemPrompt: '你是$name课程的出题专家，请用中文回复，仅返回合法JSON数组。',
          );

          final quizJsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(quizRaw);
          if (quizJsonMatch != null) {
            final questions =
                jsonDecode(quizJsonMatch.group(0)!) as List<dynamic>;
            final batch = db.batch();
            for (final q in questions) {
              batch.insert('questions', {
                'course_id': course.id,
                'source': chapter,
                'question': q['question'] ?? '',
                'option_a': q['option_a'] ?? '',
                'option_b': q['option_b'] ?? '',
                'option_c': q['option_c'] ?? '',
                'option_d': q['option_d'] ?? '',
                'answer_index': q['answer_index'] ?? 0,
              });
            }
            await batch.commit(noResult: true);
            totalQuestions += questions.length;
          }
          _log('第${i + 1}章题目完成');
        } catch (e) {
          _log('第${i + 1}章题目生成失败，跳过');
        }
      }
      _log('测验题生成完成：共 $totalQuestions 题');

      // ═══ 步骤 4：生成预制学习资源条目 ═══
      _log('正在生成课程资源条目...');
      final resBatch = db.batch();
      for (final ch in chapters) {
        for (final type in ['pdf', 'ppt', 'video']) {
          final ext =
              type == 'video' ? 'mp4' : (type == 'ppt' ? 'pptx' : 'pdf');
          resBatch.insert('resource_files', {
            'course_id': course.id,
            'file_name': '$ch.$ext',
            'file_path': '',
            'file_type': type,
            'chapter': ch,
            'description': '$name - $ch',
            'source_type': 'preset',
          });
        }
      }
      await resBatch.commit(noResult: true);
      _log('资源条目生成完成：${chapters.length * 3} 条');

      // ═══ 步骤 5：创建实验任务（如果大纲包含实验） ═══
      if (syllabusLabs.isNotEmpty) {
        _log('正在创建实验任务（${syllabusLabs.length} 个）...');
        final labDao = LabTaskDao();
        int labCreated = 0;
        for (final lab in syllabusLabs) {
          try {
            await labDao.addTask(
              title: lab.title,
              chapter: '实验${lab.index}',
              description: lab.content.isNotEmpty ? lab.content : '详见实验指导书',
              requirements: lab.objectives.isNotEmpty ? lab.objectives : null,
              deliverables: lab.notes.isNotEmpty ? lab.notes : null,
              difficulty: '中等',
              maxScore: 100,
            );
            labCreated++;
          } catch (e) {
            _log('实验"${lab.title}"创建失败');
          }
        }
        _log('实验任务创建完成：$labCreated 个');
      }

      // ═══ 步骤 6：生成知识图谱 ═══
      _log('正在生成知识图谱...');
      try {
        final graphDao = GraphDao();
        final graphId = 'g_${course.id}';
        // Use courseTitle from syllabus if available, else course name
        final graphTitle = hasSyllabus
            ? (_parsedSyllabus!.courseName.isNotEmpty
                ? _parsedSyllabus!.courseName
                : name)
            : name;

        await graphDao.createGraph(GraphModel(
          id: graphId,
          title: graphTitle,
          courseId: course.id,
          graphType: 'knowledge',
          layout: 'force',
        ));

        final nodes = <NodeModel>[];
        final edges = <EdgeModel>[];
        int nIdx = 0;
        const colors = [
          '#667eea',
          '#764ba2',
          '#f093fb',
          '#4facfe',
          '#43e97b',
          '#fa709a',
          '#a18cd1',
          '#fbc2eb',
          '#84fab0',
          '#8fd3f4',
          '#ffecd2',
          '#fcb69f'
        ];

        for (var i = 0; i < chapters.length; i++) {
          final chTitle = chapters[i];
          final ch = i < syllabusChapters.length ? syllabusChapters[i] : null;
          nIdx++;

          // Chapter main node
          nodes.add(NodeModel(
            id: '${graphId}_n${nIdx}',
            graphId: graphId,
            title: chTitle,
            content: ch?.content.isNotEmpty == true ? ch!.content : '',
            nodeType: 'chapter',
            level: 0,
            x: 80.0 + (i % 3) * 250.0,
            y: 80.0 + (i ~/ 3) * 200.0,
            color: colors[i % colors.length],
            visible: true,
          ));

          // Link to previous chapter
          if (i > 0) {
            edges.add(EdgeModel(
              id: '${graphId}_e${i}',
              graphId: graphId,
              sourceId: '${graphId}_n${i}',
              targetId: '${graphId}_n${i + 1}',
              edgeType: 'prerequisite',
              label: '前置',
              weight: 1.0,
              visible: true,
            ));
          }

          // Sub-nodes: key points
          if (ch?.keyPoints.isNotEmpty == true) {
            nIdx++;
            nodes.add(NodeModel(
              id: '${graphId}_n${nIdx}',
              graphId: graphId,
              title: '教学重点',
              content: ch!.keyPoints,
              nodeType: 'keypoint',
              level: 1,
              parentId: '${graphId}_n${i + 1}',
              x: 80.0 + (i % 3) * 250.0,
              y: 80.0 + (i ~/ 3) * 200.0 + 60.0,
              color: '#ff6b6b',
              visible: true,
            ));
            edges.add(EdgeModel(
              id: '${graphId}_e_kp${i}',
              graphId: graphId,
              sourceId: '${graphId}_n${i + 1}',
              targetId: '${graphId}_n${nIdx}',
              edgeType: 'contains',
              label: '重点',
              visible: true,
            ));
          }

          // Sub-nodes: difficult points
          if (ch?.difficultPoints.isNotEmpty == true) {
            nIdx++;
            nodes.add(NodeModel(
              id: '${graphId}_n${nIdx}',
              graphId: graphId,
              title: '教学难点',
              content: ch!.difficultPoints,
              nodeType: 'difficult',
              level: 1,
              parentId: '${graphId}_n${i + 1}',
              x: 80.0 + (i % 3) * 250.0 + 120.0,
              y: 80.0 + (i ~/ 3) * 200.0 + 60.0,
              color: '#feca57',
              visible: true,
            ));
            edges.add(EdgeModel(
              id: '${graphId}_e_dp${i}',
              graphId: graphId,
              sourceId: '${graphId}_n${i + 1}',
              targetId: '${graphId}_n${nIdx}',
              edgeType: 'contains',
              label: '难点',
              visible: true,
            ));
          }
        }

        await graphDao.insertNodes(nodes);
        await graphDao.insertEdges(edges);
        _log('知识图谱生成完成：${nodes.length} 节点 · ${edges.length} 关系线');

        // Also create knowledge_concepts entries
        if (hasSyllabus) {
          try {
            final kgDao = KnowledgeGraphDao();
            for (var i = 0; i < syllabusChapters.length; i++) {
              final sc = syllabusChapters[i];
              await kgDao.addConcept({
                'concept_name': sc.title,
                'concept_type': 'chapter',
                'chapter': sc.index,
                'description': sc.content.isNotEmpty ? sc.content : '',
                'importance': 'core',
              });
              if (sc.keyPoints.isNotEmpty) {
                await kgDao.addConcept({
                  'concept_name': '${sc.title}·重点',
                  'concept_type': 'keypoint',
                  'chapter': sc.index,
                  'description': sc.keyPoints,
                  'importance': 'important',
                });
              }
              if (sc.difficultPoints.isNotEmpty) {
                await kgDao.addConcept({
                  'concept_name': '${sc.title}·难点',
                  'concept_type': 'difficult',
                  'chapter': sc.index,
                  'description': sc.difficultPoints,
                  'importance': 'important',
                });
              }
            }
          } catch (_) {}
        }
      } catch (e) {
        _log('知识图谱生成失败：$e');
      }

      _log('课程《$name》生成完成！');

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.pop(context, course);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('课程《$name》生成成功！可在课程管理中查看和切换。'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _log('生成失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  /// 从 AI 响应中解析章节列表
  List<String> _parseChapters(String response, int expected) {
    // 尝试解析 JSON
    try {
      final cleaned = response
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

      // 查找 JSON 对象
      final jsonStart = cleaned.indexOf('{');
      final jsonEnd = cleaned.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);
        // 简易解析 chapters 数组
        final chaptersMatch =
            RegExp(r'"chapters"\s*:\s*\[(.*?)\]', dotAll: true)
                .firstMatch(jsonStr);
        if (chaptersMatch != null) {
          final arrContent = chaptersMatch.group(1)!;
          final items = RegExp(r'"([^"]+)"')
              .allMatches(arrContent)
              .map((m) => m.group(1)!)
              .toList();
          if (items.isNotEmpty) return items;
        }
      }
    } catch (_) {}

    // 回退：按行解析
    final lines = response
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('{') && !l.startsWith('}'))
        .map((l) => l
            .replaceAll(RegExp(r'^[\d]+[.、)\]]\s*'), '')
            .replaceAll('"', '')
            .trim())
        .where((l) => l.isNotEmpty && l.length > 2)
        .toList();

    if (lines.isNotEmpty) return lines.take(expected).toList();

    // 最终回退：生成默认章节名
    return List.generate(expected, (i) => '第${i + 1}章');
  }
}
