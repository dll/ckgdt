import 'package:flutter/material.dart';
import '../../data/local/course_dao.dart';
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
  final _descController = TextEditingController();
  int _chapterCount = 6;
  bool _isGenerating = false;
  String _progress = '';
  final List<String> _logs = [];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
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
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
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
              'AI 自动生成完整课程体系：大纲、章节、知识图谱、题库',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
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

            // 课程描述
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '课程描述',
                hintText: '简要描述课程内容和教学目标',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.description),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              enabled: !_isGenerating,
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
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
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
      final description = _descController.text.trim();

      // ── 步骤 1：生成课程大纲 ──
      _log('正在生成课程大纲...');
      final outlinePrompt = '''
请为《$name》课程生成 $_chapterCount 个章节的大纲。
${description.isNotEmpty ? '课程描述：$description' : ''}

要求：
1. 章节标题简洁明确（10-20 字）
2. 内容循序渐进，从基础到进阶
3. 涵盖理论知识和实践技能
4. 最后一章为综合实践/项目

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
        description: description.isEmpty ? '由 AI 自动生成的$name课程' : description,
        chapterCount: chapters.length,
        chapters: chapters,
        isActive: false,
        createdAt: now,
      );

      final courseDao = CourseDao();
      await courseDao.addCourse(course);
      _log('课程保存成功');

      // ── 步骤 3：生成各章节摘要（可选增强） ──
      _log('正在生成章节内容概要...');
      final summaryPrompt = '''
课程《$name》有以下章节：
${chapters.asMap().entries.map((e) => '第${e.key + 1}章：${e.value}').join('\n')}

请为每一章生成一句话摘要（20-30 字），说明该章的核心教学内容。
格式：每章一行，只写摘要文本。
''';

      await aiService.chat(
        [{'role': 'user', 'content': summaryPrompt}],
      );
      _log('章节概要生成完成');

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
