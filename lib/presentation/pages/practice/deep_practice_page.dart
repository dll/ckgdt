import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../services/ai_service.dart';
import '../../../services/course_context_service.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/markdown_bubble.dart';
import '../../widgets/back_button_bar.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';

class DeepPracticePage extends StatefulWidget {
  const DeepPracticePage({super.key});

  @override
  State<DeepPracticePage> createState() => _DeepPracticePageState();
}

class _DeepPracticePageState extends State<DeepPracticePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _learningRecordDao = LearningRecordDao();
  final _courseContext = CourseContextService();

  List<_ChapterDeepContent> _chapters = [];
  bool _isLoading = true;

  Map<String, Set<int>> _completedSections = {};
  int _selectedSection = -1;
  String? _selectedChapter;
  bool _isAiLoading = false;
  String _aiAnswer = '';
  String? _aiProvider;
  String? _aiModel;
  final _aiQuestionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContent();
    _loadProgress();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _aiQuestionController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final courseId = await _courseContext.activeCourseId();
      final course = await _courseContext.getActiveCourse();
      final chapterTitles = course.chapters.isNotEmpty
          ? course.chapters
          : List.generate(course.chapterCount, (i) => '第${i + 1}章');

      String jsonContent;
      try {
        jsonContent =
            await rootBundle.loadString('assets/deep_practice/$courseId.json');
      } catch (_) {
        jsonContent =
            await rootBundle.loadString('assets/deep_practice/default.json');
      }

      final parsed = jsonDecode(jsonContent) as Map<String, dynamic>;

      if (parsed.containsKey('chapters')) {
        _chapters = (parsed['chapters'] as List)
            .map((e) => _ChapterDeepContent.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (parsed.containsKey('chapterTemplate')) {
        final template = parsed['chapterTemplate'] as Map<String, dynamic>;
        final sections = (template['sections'] as List)
            .map((e) => _parseSectionWithPlaceholders(
                e as Map<String, dynamic>, '{chapterTitle}'))
            .toList();
        _chapters = List.generate(chapterTitles.length, (i) {
          final title = chapterTitles[i];
          final chapterLabel = '第${i + 1}章';
          return _ChapterDeepContent(
            chapter: chapterLabel,
            title: title,
            icon: Icons.school,
            color: Colors.primaries[i % Colors.primaries.length],
            sections: sections
                .map((s) => _replaceChapterPlaceholder(s, title))
                .toList(),
          );
        });
      }

      _tabController = TabController(length: _chapters.length, vsync: this);
      if (mounted) setState(() => _isLoading = false);
    } catch (e, st) {
      swallowDebug(e, tag: 'deep_practice_page', stack: st);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  _DeepSection _parseSectionWithPlaceholders(
      Map<String, dynamic> map, String placeholder) {
    final raw = _DeepSection.fromJson(map);
    return _DeepSection(
      title: raw.title,
      icon: raw.icon,
      content: raw.content,
      keyPoints: raw.keyPoints,
      practiceQuestions: raw.practiceQuestions,
    );
  }

  _DeepSection _replaceChapterPlaceholder(
      _DeepSection section, String chapterTitle) {
    return _DeepSection(
      title: section.title.replaceAll('{chapterTitle}', chapterTitle),
      icon: section.icon,
      content: section.content.replaceAll('{chapterTitle}', chapterTitle),
      keyPoints: section.keyPoints
          .map((kp) => kp.replaceAll('{chapterTitle}', chapterTitle))
          .toList(),
      practiceQuestions: section.practiceQuestions
          .map((pq) => pq.replaceAll('{chapterTitle}', chapterTitle))
          .toList(),
    );
  }

  Future<void> _loadProgress() async {
    final userId = _authService.currentUser?.userId;
    if (userId == null) return;

    try {
      final records = await _learningRecordDao.getRecords(userId);
      final completed = <String, Set<int>>{};
      for (final r in records) {
        final nodeTitle = r['node_title']?.toString() ?? '';
        final match = RegExp(r'深度-(.+)-(\d+)').firstMatch(nodeTitle);
        if (match != null) {
          final chapter = match.group(1)!;
          final idx = int.tryParse(match.group(2)!) ?? 0;
          completed.putIfAbsent(chapter, () => {}).add(idx);
        }
      }
      if (mounted) setState(() => _completedSections = completed);
    } catch (e) {
      swallowDebug(e, tag: 'deep_practice_page');
    }
  }

  Future<void> _markCompleted(String chapter, int sectionIdx) async {
    final userId = _authService.currentUser?.userId;
    if (userId == null) return;

    try {
      await _learningRecordDao.addRecord(
        userId: userId,
        nodeId: 'deep-$chapter-$sectionIdx',
        nodeTitle: '深度-$chapter-$sectionIdx',
        studyTime: '30',
      );
      setState(() {
        _completedSections.putIfAbsent(chapter, () => {}).add(sectionIdx);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已标记完成 ✓'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      swallowDebug(e, tag: 'deep_practice_page');
    }
  }

  Future<void> _askAi(String question) async {
    setState(() {
      _isAiLoading = true;
      _aiAnswer = '';
      _aiProvider = null;
      _aiModel = null;
    });
    try {
      final ai = AiService();
      final result = await ai.chatWithMeta(
        [
          {'role': 'user', 'content': question}
        ],
        systemPrompt: '你是课程 AI 助教。请用简洁、专业的语言回答问题。',
      );
      if (mounted) {
        setState(() {
          _aiAnswer = result.content;
          _aiProvider = result.provider;
          _aiModel = result.model;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _aiAnswer = '抱歉，AI 回答失败：$e');
    } finally {
      if (mounted) setState(() => _isAiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: BackButtonBar(title: '深度实践中心'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_chapters.isEmpty) {
      return Scaffold(
        appBar: BackButtonBar(title: '深度实践中心'),
        body: const Center(child: Text('暂无深度实践内容')),
      );
    }

    return Scaffold(
      appBar: BackButtonBar(
        title: '深度实践中心',
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelColor: Colors.white60,
          tabs: _chapters
              .map((c) => Tab(
                    icon: Icon(c.icon, size: 18),
                    text: c.chapter,
                  ))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children:
            _chapters.map((ch) => _buildChapterContent(ch, isDark)).toList(),
      ),
    );
  }

  Widget _buildChapterContent(_ChapterDeepContent chapter, bool isDark) {
    final completed = _completedSections[chapter.chapter] ?? {};
    final total = chapter.sections.length;
    final done = completed.length;
    final progress = total > 0 ? done / total : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [chapter.color, chapter.color.withValues(alpha: 0.7)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(chapter.icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(chapter.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$done/$total',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: isDark ? Colors.blueGrey[800] : Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.lightbulb, color: Colors.amber[700], size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '学习建议：按顺序完成 知识拓展 → 核心概念 → 动手练习 → 实战挑战',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(chapter.sections.length, (idx) {
            final section = chapter.sections[idx];
            final isCompleted = completed.contains(idx);
            final isExpanded =
                _selectedChapter == chapter.chapter && _selectedSection == idx;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isCompleted
                    ? BorderSide(
                        color: Colors.green.withValues(alpha: 0.5), width: 1.5)
                    : BorderSide.none,
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green.withValues(alpha: 0.15)
                            : chapter.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCompleted ? Icons.check : section.icon,
                        color: isCompleted ? Colors.green : chapter.color,
                        size: 20,
                      ),
                    ),
                    title: Text(section.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null)),
                    trailing: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: chapter.color,
                    ),
                    onTap: () => setState(() {
                      if (isExpanded) {
                        _selectedSection = -1;
                        _selectedChapter = null;
                      } else {
                        _selectedSection = idx;
                        _selectedChapter = chapter.chapter;
                      }
                      _aiAnswer = '';
                    }),
                  ),
                  if (isExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          Text(section.content,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87)),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[850] : Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: chapter.color.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.bookmark,
                                        color: chapter.color, size: 16),
                                    const SizedBox(width: 4),
                                    Text('核心要点',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: chapter.color)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...section.keyPoints.map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('• ',
                                              style: TextStyle(
                                                  color: chapter.color,
                                                  fontSize: 13)),
                                          Expanded(
                                              child: Text(p,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      height: 1.5))),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('💡 思考与练习',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: chapter.color)),
                          const SizedBox(height: 6),
                          ...section.practiceQuestions
                              .asMap()
                              .entries
                              .map((e) => Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.indigo
                                              .withValues(alpha: 0.15)
                                          : Colors.indigo
                                              .withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: chapter.color
                                                .withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text('${e.key + 1}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: chapter.color)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(e.value,
                                              style: const TextStyle(
                                                  fontSize: 12, height: 1.4)),
                                        ),
                                        InkWell(
                                          onTap: () => _askAi(e.value),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.smart_toy,
                                                    size: 12,
                                                    color:
                                                        Colors.deepPurple[400]),
                                                const SizedBox(width: 2),
                                                Text('AI',
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors
                                                            .deepPurple[400])),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                          if (_aiAnswer.isNotEmpty || _isAiLoading)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.deepPurple.withValues(alpha: 0.15)
                                    : Colors.deepPurple.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.deepPurple
                                        .withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.smart_toy,
                                          size: 16,
                                          color: Colors.deepPurple[400]),
                                      const SizedBox(width: 4),
                                      Text('AI 解答',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: Colors.deepPurple[400])),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isAiLoading)
                                    const Center(
                                        child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ))
                                  else
                                    MarkdownBubble(
                                      content: _aiAnswer,
                                      provider: _aiProvider,
                                      model: _aiModel,
                                      compact: true,
                                      accentColor: Colors.deepPurple,
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _aiQuestionController,
                                  decoration: InputDecoration(
                                    hintText: '输入问题，向AI请教...',
                                    hintStyle: const TextStyle(fontSize: 12),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: _isAiLoading
                                    ? null
                                    : () {
                                        final q =
                                            _aiQuestionController.text.trim();
                                        if (q.isNotEmpty) {
                                          _askAi(q);
                                          _aiQuestionController.clear();
                                        }
                                      },
                                child: const Text('提问',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (!isCompleted)
                                FilledButton.icon(
                                  onPressed: () =>
                                      _markCompleted(chapter.chapter, idx),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('标记完成',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              if (isCompleted)
                                Chip(
                                  avatar: const Icon(Icons.check_circle,
                                      color: Colors.green, size: 16),
                                  label: const Text('已完成',
                                      style: TextStyle(fontSize: 12)),
                                  backgroundColor:
                                      Colors.green.withValues(alpha: 0.1),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

IconData _parseIcon(String name) {
  const iconMap = {
    'history_edu': Icons.history_edu,
    'psychology': Icons.psychology,
    'assignment': Icons.assignment,
    'rocket_launch': Icons.rocket_launch,
    'panorama_wide_angle': Icons.panorama_wide_angle,
    'grid_on': Icons.grid_on,
    'phone_android': Icons.phone_android,
    'architecture': Icons.architecture,
    'loop': Icons.loop,
    'checklist': Icons.checklist,
    'chat': Icons.chat,
    'flutter_dash': Icons.flutter_dash,
    'engineering': Icons.engineering,
    'account_tree': Icons.account_tree,
    'cloud': Icons.cloud,
    'shopping_cart': Icons.shopping_cart,
    'wechat': Icons.wechat,
    'merge_type': Icons.merge_type,
    'widgets': Icons.widgets,
    'school': Icons.school,
    'payment': Icons.payment,
    'devices': Icons.devices,
    'hub': Icons.hub,
    'code': Icons.code,
    'calculate': Icons.calculate,
    'draw': Icons.draw,
    'integration_instructions': Icons.integration_instructions,
    'build_circle': Icons.build_circle,
    'speed': Icons.speed,
    'foundation': Icons.foundation,
    'emoji_events': Icons.emoji_events,
  };
  return iconMap[name] ?? Icons.school;
}

Color _parseColor(String hex) {
  hex = hex.replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse(hex, radix: 16));
}

class _ChapterDeepContent {
  final String chapter;
  final String title;
  final IconData icon;
  final Color color;
  final List<_DeepSection> sections;

  const _ChapterDeepContent({
    required this.chapter,
    required this.title,
    required this.icon,
    required this.color,
    required this.sections,
  });

  factory _ChapterDeepContent.fromJson(Map<String, dynamic> json) {
    return _ChapterDeepContent(
      chapter: json['chapter'] as String? ?? '',
      title: json['title'] as String? ?? '',
      icon: _parseIcon(json['icon'] as String? ?? ''),
      color: _parseColor(json['color'] as String? ?? '#FF2196F3'),
      sections: (json['sections'] as List?)
              ?.map((e) => _DeepSection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class _DeepSection {
  final String title;
  final IconData icon;
  final String content;
  final List<String> keyPoints;
  final List<String> practiceQuestions;

  const _DeepSection({
    required this.title,
    required this.icon,
    required this.content,
    required this.keyPoints,
    required this.practiceQuestions,
  });

  factory _DeepSection.fromJson(Map<String, dynamic> json) {
    return _DeepSection(
      title: json['title'] as String? ?? '',
      icon: _parseIcon(json['icon'] as String? ?? ''),
      content: json['content'] as String? ?? '',
      keyPoints:
          (json['keyPoints'] as List?)?.map((e) => e.toString()).toList() ?? [],
      practiceQuestions: (json['practiceQuestions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
