// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/local/course_dao.dart';
import '../../data/local/database_helper.dart';
import '../../data/local/graph_dao.dart';
import '../../data/local/lab_task_dao.dart';
import '../../data/local/achievement_dao.dart';
import '../../data/models/course_model.dart';
import '../../data/models/edge_model.dart';
import '../../data/models/graph_model.dart';
import '../../data/models/node_model.dart';
import '../../services/achievement/achievement_excel_service.dart';
import '../../services/course_generation_service.dart';
import '../../services/resource_persistence_service.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

/// 一键生课 — 底部弹出表单（只上传大纲）
class CourseGeneratorSheet extends StatefulWidget {
  const CourseGeneratorSheet({super.key});

  @override
  State<CourseGeneratorSheet> createState() => _CourseGeneratorSheetState();
}

class _CourseGeneratorSheetState extends State<CourseGeneratorSheet> {
  final _nameController = TextEditingController();
  bool _isGenerating = false;
  String _progress = '';
  final List<String> _logs = [];

  // 大纲相关
  String? _outlineFileName;
  String? _outlineText;
  String? _outlineError;

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
              '上传课程大纲，自动识别课程名称并快速创建资源包',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            _buildDetectedCourseName(theme),
            const SizedBox(height: 16),

            // 上传大纲
            _buildOutlineUpload(theme),
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
              onPressed: _isGenerating ? null : _generateCourseEnhanced,
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

  Widget _buildOutlineUpload(ThemeData theme) {
    final hasOutline = _outlineText != null && _outlineText!.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isGenerating ? null : _pickOutline,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasOutline
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _outlineError != null
                ? theme.colorScheme.error
                : hasOutline
                    ? theme.colorScheme.primary.withValues(alpha: 0.4)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              hasOutline ? Icons.description : Icons.upload_file,
              size: 36,
              color: hasOutline
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              hasOutline ? '已上传: $_outlineFileName' : '上传课程大纲',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: hasOutline ? theme.colorScheme.primary : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasOutline ? '点击重新选择' : '支持 Markdown / Word / Excel / CSV',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            if (_outlineError != null) ...[
              const SizedBox(height: 4),
              Text(
                _outlineError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetectedCourseName(ThemeData theme) {
    final name = _nameController.text.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.school, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '课程名称',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name.isEmpty ? '上传大纲后自动识别' : name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: name.isEmpty
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOutline() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'docx', 'xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final ext = (file.extension ?? '').toLowerCase();
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw StateError('无法读取文件内容');
      final text = AchievementExcelService.instance.syllabusRawText(bytes, ext);

      if (text.trim().isEmpty) {
        setState(() {
          _outlineError = '文件内容为空';
          _outlineFileName = null;
          _outlineText = null;
        });
        return;
      }

      setState(() {
        _outlineFileName = file.name;
        _outlineText = text;
        _outlineError = null;
        _nameController.text =
            CourseGenerationService.extractCourseNameFromSyllabus(text) ?? '';
      });
    } catch (e) {
      setState(() {
        _outlineError = '读取文件失败: $e';
        _outlineFileName = null;
        _outlineText = null;
      });
    }
  }

  void _log(String msg) {
    setState(() {
      _logs.add(msg);
      _progress = msg;
    });
  }

  void _updateProgress(String msg) {
    if (mounted) {
      setState(() => _progress = msg);
    }
  }

  /// 增强版课程生成 — 从大纲生成完整课程资源包
  Future<void> _generateCourseEnhanced() async {
    if (_outlineText == null || _outlineText!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请上传课程大纲')),
      );
      return;
    }
    final name =
        CourseGenerationService.extractCourseNameFromSyllabus(_outlineText!) ??
            _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('未能从大纲识别课程名称，请检查大纲是否包含“课程名称”或“《课程名》教学大纲”')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _logs.clear();
    });

    try {
      final chapters =
          CourseGenerationService.extractChaptersFromSyllabus(_outlineText!);
      final finalChapters = chapters.isNotEmpty ? chapters : ['课程导论'];

      _log('开始快速创建课程资源包...');
      _log('共 ${finalChapters.length} 个章节');

      // 使用 CourseGenerationService 生成所有资源
      final generator = CourseGenerationService(
        onProgress: (step, progress) {
          _updateProgress('$step (${(progress * 100).toInt()}%)');
        },
      );

      final result = await generator.generateAll(
        courseName: name,
        chapters: finalChapters,
        syllabusContent: _outlineText,
        lazy: true,
      );

      if (!result.isSuccess) {
        _log('生成失败: ${result.error}');
        return;
      }

      _log('资源生成完成，保存到本地...');
      _updateProgress('保存到本地...');

      // 保存到本地文件系统
      final persistence = ResourcePersistenceService.instance;
      final courseDir = await persistence.saveLocally(result);
      _log('已保存到: $courseDir');
      final inventoryFile = File('$courseDir/课程资源包清单.json');
      var generatedFileCount = 0;
      if (await inventoryFile.exists()) {
        try {
          final inventory = jsonDecode(await inventoryFile.readAsString())
              as Map<String, dynamic>;
          final summary = inventory['summary'] as Map<String, dynamic>? ?? {};
          generatedFileCount = summary['files'] as int? ?? 0;
        } catch (e) {
          swallowDebug(e, tag: 'CourseGeneratorSheet.inventory');
        }
      }

      // 保存到数据库
      _updateProgress('保存到数据库...');
      await _saveToDatabase(result);
      await _saveCourseObjectivesFromSyllabus(result);

      _log('课程《$name》创建成功！');
      _log('已建立懒生成资源包：测验、课件、视频脚本将在首次使用时生成');
      _log('登记 ${result.videoScripts.length} 个视频脚本待生成项');
      _log('登记 ${result.courseware.length} 个课件待生成项');
      _log('包含 ${result.graphs.length} 个图谱');
      final practiceLabel =
          result.courseProfile['practice_label']?.toString() ?? '实践任务';
      _log('包含 ${result.labTasks.length} 个$practiceLabel');
      _log('包含 ${result.homeworks.length} 章作业');
      _log('包含 ${result.reportTemplates.length} 个报告模板');
      if (result.courseProfile.isNotEmpty) {
        _log(
          '课程画像: ${result.courseProfile['discipline'] ?? '通用'} / ${result.courseProfile['course_mode'] ?? '理论实践型'} / ${result.courseProfile['practice_label'] ?? '实践任务'}',
        );
      }
      if (result.platformReadiness.isNotEmpty) {
        _log(
          '平台化检测: ${result.platformReadiness['passed'] == true ? '通过' : '需完善'}，得分 ${result.platformReadiness['score'] ?? 0}',
        );
      }
      if (generatedFileCount > 0) {
        _log('课程资源包共 $generatedFileCount 个文件');
      }
      _log('清单: $courseDir\\课程资源包清单.md');

      // 返回创建的课程
      if (mounted) {
        final courseDao = CourseDao();
        final courses = await courseDao.getAllCourses();
        final newCourse = courses.firstWhere(
          (c) => c.id == result.courseId,
          orElse: () => CourseModel(
            id: result.courseId,
            name: name,
            description: '',
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
        Navigator.of(context).pop(newCourse);
      }
    } catch (e, st) {
      swallowDebug(e,
          tag: 'CourseGeneratorSheet._generateCourseEnhanced', stack: st);
      _log('生成失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _saveCourseObjectivesFromSyllabus(
    CourseGenerationResult result,
  ) async {
    final outline = _outlineText;
    if (outline == null || outline.trim().isEmpty) return;
    final rows = await AchievementExcelService.instance
        .extractSyllabusRowsFromRawText(outline);
    if (rows.isEmpty) {
      _log('未从大纲识别课程目标，请到课程目标管理中审核补录');
      return;
    }
    final version =
        AchievementExcelService.instance.syllabusVersionFromText(outline);
    await AchievementDao().saveCourseObjectives(
      result.courseName,
      rows,
      syllabusVersion: version,
    );
    _log('已保存 ${rows.length} 个课程目标到课程目标管理（$version）');
  }

  /// 保存到数据库
  Future<void> _saveToDatabase(CourseGenerationResult result) async {
    final db = await DatabaseHelper.instance.database;

    // 保存课程
    final courseDao = CourseDao();
    final course = CourseModel(
      id: result.courseId,
      name: result.courseName,
      description: result.config['description'] ?? '',
      chapterCount: result.chapters.isNotEmpty ? result.chapters.length : 1,
      chapters: result.chapters
          .map((chapter) => chapter['title']?.toString() ?? '')
          .where((title) => title.trim().isNotEmpty)
          .toList(),
      isActive: false,
      createdAt: DateTime.now().toIso8601String(),
    );
    if (await courseDao.getCourse(result.courseId) == null) {
      await courseDao.addCourse(course);
    } else {
      await courseDao.updateCourse(course);
    }
    await courseDao.setActiveCourse(result.courseId);

    // 保存测验题目
    for (final q in result.quizzes) {
      await db.insert('questions', {
        'course_id': result.courseId,
        'source': q['chapter'] ?? '',
        'question': q['question'] ?? '',
        'option_a': q['option_a'] ?? '',
        'option_b': q['option_b'] ?? '',
        'option_c': q['option_c'] ?? '',
        'option_d': q['option_d'] ?? '',
        'answer_index': q['answer_index'] ?? 0,
      });
    }

    // 保存实践任务。数据库表名沿用 lab_tasks 兼容旧数据。
    final labDao = LabTaskDao();
    await db.delete(
      'lab_tasks',
      where: '''
        course_id = ?
        AND id NOT IN (SELECT DISTINCT task_id FROM lab_submissions WHERE task_id IS NOT NULL)
      ''',
      whereArgs: [result.courseId],
    );
    for (final lab in result.labTasks) {
      final chapterNumber = lab['chapter_number'];
      final chapter = lab['chapter']?.toString().trim().isNotEmpty == true
          ? lab['chapter'].toString().trim()
          : chapterNumber == null
              ? null
              : '第$chapterNumber章';
      await labDao.addTask(
        title: lab['title'] ?? '',
        chapter: chapter,
        description: lab['description'] ?? '',
        requirements: (lab['requirements'] as List?)?.join('\n'),
        deliverables: (lab['deliverables'] as List?)?.join('\n'),
        difficulty: lab['difficulty']?.toString() == 'hard' ? '较难' : '中等',
        maxScore: int.tryParse(lab['max_score']?.toString() ?? '') ?? 100,
        creatorId: 'course_generator',
      );
    }

    // 保存作业
    final now = DateTime.now().toIso8601String();
    final oldHomeworks = await db.query(
      'homeworks',
      columns: ['id'],
      where: 'course_id = ?',
      whereArgs: [result.courseId],
    );
    for (final old in oldHomeworks) {
      await db.delete(
        'homework_items',
        where: 'homework_id = ?',
        whereArgs: [old['id']],
      );
      await db.delete(
        'homework_submissions',
        where: 'homework_id = ?',
        whereArgs: [old['id']],
      );
    }
    await db.delete(
      'homeworks',
      where: 'course_id = ?',
      whereArgs: [result.courseId],
    );
    for (final homework in result.homeworks) {
      final items = (homework['items'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      final homeworkId = await db.insert('homeworks', {
        'course_id': result.courseId,
        'title': '${homework['chapter_title'] ?? ''}作业',
        'description': homework['description']?.toString() ?? '',
        'chapter': homework['chapter']?.toString() ?? '',
        'chapter_title': homework['chapter_title']?.toString() ?? '',
        'course_objective': homework['course_objective']?.toString() ?? '',
        'total_score': items.fold<int>(
          0,
          (sum, item) =>
              sum + (int.tryParse(item['max_score']?.toString() ?? '') ?? 100),
        ),
        'deadline': homework['deadline']?.toString(),
        'status': 'published',
        'created_at': now,
      });
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        await db.insert('homework_items', {
          'homework_id': homeworkId,
          'item_index': i + 1,
          'type': item['type_code']?.toString() ?? 'basic',
          'type_label': item['type']?.toString() ?? '基础题',
          'question': item['question']?.toString() ?? '',
          'reference_answer': item['reference_answer']?.toString(),
          'max_score': int.tryParse(item['max_score']?.toString() ?? '') ?? 100,
          'objective_mapping': jsonEncode(item['objective_mapping'] ?? []),
        });
      }
    }

    await db.delete(
      'resource_files',
      where: 'course_id = ? AND source_type = ?',
      whereArgs: [result.courseId, 'course_package'],
    );
    for (final item in result.courseware) {
      final chapterNum = item['chapter_number'] ?? 0;
      final title = item['title']?.toString() ?? '课件';
      final lazy = item['lazy_generation'] == true;
      await db.insert('resource_files', {
        'course_id': result.courseId,
        'file_name': lazy ? '$title-课件.lazy.json' : '$title.json',
        'file_path': lazy
            ? 'courses/${result.courseId}/课件/$title-课件.lazy.json'
            : 'courses/${result.courseId}/课件/$title.json',
        'file_type': 'ppt',
        'chapter': chapterNum == 0 ? '课程资源' : '第$chapterNum章',
        'description': lazy ? '$title 课件（首次使用时生成）' : '$title 课件',
        'source_type': 'course_package',
      });
    }
    for (final item in result.videoScripts) {
      final chapterNum = item['chapter_number'] ?? 0;
      final title = item['title']?.toString() ?? '视频脚本';
      final lazy = item['lazy_generation'] == true;
      await db.insert('resource_files', {
        'course_id': result.courseId,
        'file_name': lazy ? '$title-视频脚本.lazy.json' : '$title-视频脚本.json',
        'file_path': lazy
            ? 'courses/${result.courseId}/视频/$title-视频脚本.lazy.json'
            : 'courses/${result.courseId}/视频/$title-视频脚本.json',
        'file_type': 'video',
        'chapter': chapterNum == 0 ? '课程资源' : '第$chapterNum章',
        'description': lazy ? '$title 视频脚本（首次使用时生成）' : '$title 视频脚本',
        'source_type': 'course_package',
      });
    }

    // 保存图谱：总图谱 + 按课程类型生成的可编辑子图谱
    final graphDao = GraphDao();
    final existingGraphs = await db.query(
      'graphs',
      columns: ['id'],
      where: 'course_id = ?',
      whereArgs: [result.courseId],
    );
    for (final graph in existingGraphs) {
      final id = graph['id']?.toString() ?? '';
      if (id == 'g_${result.courseId}' ||
          id.startsWith('graph_main_${result.courseId}') ||
          id.startsWith('graph_detail_${result.courseId}_')) {
        await graphDao.deleteGraph(id);
      }
    }

    final mainGraphId = 'graph_main_${result.courseId}';
    await graphDao.createGraph(GraphModel(
      id: mainGraphId,
      title: '${result.courseName}总图谱',
      courseId: result.courseId,
      graphType: 'overview',
      layout: 'force',
    ));

    final mainRootId = '${mainGraphId}_root';
    await graphDao.insertNode(NodeModel(
      id: mainRootId,
      graphId: mainGraphId,
      title: result.courseName,
      content: '课程总图谱，连接所有按大纲生成的子图谱。',
      nodeType: 'course',
      level: 0,
    ));

    for (var graphIndex = 0; graphIndex < result.graphs.length; graphIndex++) {
      final graph = result.graphs[graphIndex];
      final category = graph['category']?.toString().trim().isNotEmpty == true
          ? graph['category'].toString().trim()
          : '子图谱${graphIndex + 1}';
      final graphId = 'graph_detail_${result.courseId}_${graphIndex + 1}';
      await graphDao.createGraph(GraphModel(
        id: graphId,
        title: category,
        courseId: result.courseId,
        graphType: 'md_import',
        layout: 'force',
      ));

      final categoryNodeId = '${mainGraphId}_cat_${graphIndex + 1}';
      await graphDao.insertNode(NodeModel(
        id: categoryNodeId,
        graphId: mainGraphId,
        title: category,
        content: '子图谱：$category。可进入后编辑节点、关系和说明。',
        nodeType: 'subgraph',
        level: 1,
        parentId: mainRootId,
      ));
      await graphDao.insertEdge(EdgeModel(
        id: '${mainGraphId}_edge_${graphIndex + 1}',
        graphId: mainGraphId,
        sourceId: mainRootId,
        targetId: categoryNodeId,
        edgeType: 'contains',
        label: '子图谱',
      ));

      final nodes = graph['nodes'] as List? ?? [];
      final edges = graph['edges'] as List? ?? [];
      final idMap = <String, String>{};
      for (final node in nodes) {
        final sourceId = node['id']?.toString() ?? '';
        if (sourceId.isEmpty) continue;
        final nodeId = '${graphId}_$sourceId';
        idMap[sourceId] = nodeId;
        await graphDao.insertNode(NodeModel(
          id: nodeId,
          graphId: graphId,
          title: node['label']?.toString() ?? '',
          content: node['content']?.toString(),
          nodeType: node['type']?.toString() ?? 'concept',
          level: int.tryParse(node['level']?.toString() ?? '') ?? 0,
          parentId: idMap[node['parent_id']?.toString()],
        ));
      }

      for (final edge in edges) {
        final from = edge['from']?.toString() ?? '';
        final to = edge['to']?.toString() ?? '';
        final sourceId = idMap[from];
        final targetId = idMap[to];
        if (sourceId == null || targetId == null) continue;
        await graphDao.insertEdge(EdgeModel(
          id: '${graphId}_e_${from}_$to',
          graphId: graphId,
          sourceId: sourceId,
          targetId: targetId,
          edgeType: edge['type']?.toString() ?? 'related',
          label: edge['label']?.toString() ?? '',
        ));
      }
    }
  }
}
