import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/local/course_dao.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/course_model.dart';
import '../../services/ai_service.dart';

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

            // 课程大纲（文件上传）
            InkWell(
              onTap: _isGenerating ? null : _pickOutlineFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _outlineContent != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    width: _outlineContent != null ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: _outlineContent != null
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      _outlineContent != null
                          ? Icons.check_circle
                          : Icons.upload_file,
                      color: _outlineContent != null
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _outlineFileName ?? '上传课程大纲',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: _outlineContent != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _outlineContent != null
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _outlineContent != null
                                ? '已加载 ${_outlineContent!.length} 字'
                                : '可选：上传 .txt / .md 大纲文件，不上传则 AI 自动生成',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_outlineContent != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _isGenerating
                            ? null
                            : () => setState(() {
                                  _outlineContent = null;
                                  _outlineFileName = null;
                                }),
                        tooltip: '移除大纲',
                      ),
                  ],
                ),
              ),
            ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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

  Future<void> _pickOutlineFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final file = File(filePath);
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
        _outlineFileName = result.files.single.name;
      });
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
    if (_outlineContent == null || _outlineContent!.trim().isEmpty) {
      // 大纲可选：无大纲时让 AI 自由生成
      _log('未上传大纲，AI 将自动生成章节...');
    }

    setState(() {
      _isGenerating = true;
      _logs.clear();
    });

    try {
      final aiService = AiService();
      final outline = _outlineContent!.trim();

      // ── 步骤 1：生成课程章节 ──
      final hasOutline = outline.isNotEmpty;
      _log(hasOutline ? '正在基于大纲生成课程章节...' : '正在由 AI 生成课程章节...');

      final outlinePrompt = hasOutline
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

      final outlineResponse = await aiService.chat(
        [{'role': 'user', 'content': outlinePrompt}],
      );

      // 解析章节列表
      final chapters = _parseChapters(outlineResponse, _chapterCount);
      _log('大纲生成完成：${chapters.length} 个章节');

      // ── 步骤 2：保存课程到数据库 ──
      _log('正在保存课程...');
      final courseId = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final now = DateTime.now().toIso8601String();

      final course = CourseModel(
        id: courseId.isEmpty ? 'course_${DateTime.now().millisecondsSinceEpoch}' : courseId,
        name: name,
        description: '基于上传大纲生成的$name课程',
        chapterCount: chapters.length,
        chapters: chapters,
        isActive: false,
        createdAt: now,
      );

      final courseDao = CourseDao();
      await courseDao.addCourse(course);
      _log('课程保存成功');

      // ── 步骤 3：生成各章节测验题 ──
      _log('正在生成章节测验题（每章5题）...');
      final db = await DatabaseHelper.instance.database;
      int totalQuestions = 0;

      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        final quizPrompt =
            '为《$name》课程的"$chapter"章节生成5道选择题。\n\n'
            '请严格按以下JSON格式输出（不要包含其他文字）：\n'
            '[{"question":"题目","option_a":"A","option_b":"B","option_c":"C","option_d":"D","answer_index":0}]\n\n'
            '要求：answer_index 为正确答案索引（0=A,1=B,2=C,3=D），题目难度适中。';

        try {
          final quizRaw = await aiService.chat(
            [{'role': 'user', 'content': quizPrompt}],
            systemPrompt: '你是$name课程的出题专家，请用中文回复，仅返回合法JSON数组。',
          );

          final quizJsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(quizRaw);
          if (quizJsonMatch != null) {
            final questions =
                jsonDecode(quizJsonMatch.group(0)!) as List<dynamic>;
            final batch = db.batch();
            for (final q in questions) {
              batch.insert('questions', {
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

      // ── 步骤 4：生成预制学习资源条目 ──
      _log('正在生成课程资源条目...');
      final resBatch = db.batch();
      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        for (final type in ['pdf', 'ppt', 'video']) {
          final ext = type == 'video' ? 'mp4' : (type == 'ppt' ? 'pptx' : 'pdf');
          resBatch.insert('resource_files', {
            'file_name': '$chapter.$ext',
            'file_path': '',
            'file_type': type,
            'chapter': chapter,
            'description': '$name - $chapter',
            'source_type': 'preset',
          });
        }
      }
      await resBatch.commit(noResult: true);
      _log('资源条目生成完成：${chapters.length * 3} 条');

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
        final chaptersMatch = RegExp(r'"chapters"\s*:\s*\[(.*?)\]', dotAll: true)
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
        .map((l) => l.replaceAll(RegExp(r'^[\d]+[.、)\]]\s*'), '').replaceAll('"', '').trim())
        .where((l) => l.isNotEmpty && l.length > 2)
        .toList();

    if (lines.isNotEmpty) return lines.take(expected).toList();

    // 最终回退：生成默认章节名
    return List.generate(expected, (i) => '第${i + 1}章');
  }
}
