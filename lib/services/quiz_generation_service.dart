import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../data/local/database_helper.dart';
import '../data/models/question_model.dart';
import '../core/error_handler.dart';
import 'ai_service.dart';

/// 测验生成服务 — 从课程包 MD 文件自动生成测验题目
///
/// 读取课程包目录下的 Markdown 文件，通过 AI 生成四选一测验题，
/// 并写入 questions 表。
class QuizGenerationService {
  final AiService _ai = AiService();

  /// 生成进度回调：(chapter, progress)
  void Function(String chapter, double progress)? onProgress;

  QuizGenerationService({this.onProgress});

  /// 为当前课程的所有章节生成测验题目
  /// 每个章节生成 [questionsPerChapter] 道题
  Future<GenerationResult> generateAll({
    required String courseId,
    int questionsPerChapter = 10,
  }) async {
    final result = GenerationResult();
    final db = await DatabaseHelper.instance.database;

    // 查找课程包目录
    final dir = await _getCourseDir(courseId);
    final planned = await _loadPlannedChapters(dir);
    if (planned.isNotEmpty) {
      await db
          .delete('questions', where: 'course_id = ?', whereArgs: [courseId]);
      for (var i = 0; i < planned.length; i++) {
        final chapter = planned[i];
        onProgress?.call(chapter.title, i / planned.length);
        final questions = _generateDeterministicQuestions(
          chapter: chapter,
          count: questionsPerChapter,
          courseId: courseId,
        );
        for (final q in questions) {
          await db.insert(
            'questions',
            q.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        result.generated.add(GenerationChapterResult(
          chapter: chapter.title,
          questionCount: questions.length,
        ));
      }
      onProgress?.call('', 1.0);
      return result;
    }

    final theoryDir = Directory('$dir${Platform.pathSeparator}理论');

    List<FileSystemEntity> mdFiles = [];
    if (await theoryDir.exists()) {
      mdFiles =
          await theoryDir.list().where((f) => f.path.endsWith('.md')).toList();
    } else {
      // 尝试 courses/{courseId}/ 目录下的 MD 文件
      final courseDir = Directory(dir);
      if (await courseDir.exists()) {
        mdFiles = await courseDir
            .list()
            .where((f) => f.path.endsWith('.md'))
            .toList();
      }
    }

    if (mdFiles.isEmpty) {
      result.error = '课程包中没有找到 Markdown 文件';
      return result;
    }

    mdFiles.sort(
        (a, b) => _chapterSortKey(a.path).compareTo(_chapterSortKey(b.path)));
    for (int i = 0; i < mdFiles.length; i++) {
      final mdFile = mdFiles[i];
      final name = mdFile.path
          .split(Platform.pathSeparator)
          .last
          .replaceAll(RegExp(r'\.md$'), '');

      onProgress?.call(name, i / mdFiles.length);

      try {
        final mdContent = await File(mdFile.path).readAsString();
        if (mdContent.trim().isEmpty) continue;

        final questions = await _generateQuestionsFromMd(
          chapterTitle: name,
          mdContent: mdContent,
          count: questionsPerChapter,
          courseId: courseId,
        );

        if (questions.isNotEmpty) {
          // 写入数据库
          for (final q in questions) {
            await db.insert(
              'questions',
              q.toMap()..['course_id'] = courseId,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          result.generated.add(GenerationChapterResult(
            chapter: name,
            questionCount: questions.length,
          ));
        }
      } catch (e) {
        swallowDebug(e, tag: 'QuizGen.$name');
        result.errors.add('$name: $e');
      }
    }

    onProgress?.call('', 1.0);
    return result;
  }

  List<QuestionModel> _generateDeterministicQuestions({
    required _QuizChapter chapter,
    required int count,
    required String courseId,
  }) {
    final concepts = <String>[
      chapter.shortTitle,
      ...chapter.keyPoints,
      ...chapter.objectives,
      ...chapter.difficultPoints,
    ]
        .map((item) => item.trim())
        .where((item) => item.length >= 2)
        .toSet()
        .toList();
    if (concepts.isEmpty) concepts.add(chapter.shortTitle);

    final templates = <QuestionModel>[];
    for (var i = 0; i < count; i++) {
      final concept = concepts[i % concepts.length];
      final source = chapter.title;
      switch (i % 5) {
        case 0:
          templates.add(QuestionModel(
            courseId: courseId,
            source: source,
            question: '关于“$concept”，下列哪项最符合${chapter.title}的教学要求？',
            optionA: '能够说明其核心含义，并联系本章学习任务进行应用',
            optionB: '只需记住名称，不需要理解用途',
            optionC: '与本章学习内容无关',
            optionD: '只在期末复习时临时了解即可',
            answerIndex: 0,
          ));
          break;
        case 1:
          templates.add(QuestionModel(
            courseId: courseId,
            source: source,
            question: '${chapter.title}学习中，围绕“$concept”应优先形成哪类学习证据？',
            optionA: '学习笔记、任务成果、测验或实践记录',
            optionB: '与课程无关的随意截图',
            optionC: '没有过程记录的口头说明',
            optionD: '只提交空白模板',
            answerIndex: 0,
          ));
          break;
        case 2:
          templates.add(QuestionModel(
            courseId: courseId,
            source: source,
            question: '教师评价“$concept”相关学习成果时，最应关注什么？',
            optionA: '概念理解、应用过程、成果质量和反思改进',
            optionB: '文件名是否足够长',
            optionC: '是否完全脱离本章目标',
            optionD: '是否只复制资料不做分析',
            answerIndex: 0,
          ));
          break;
        case 3:
          templates.add(QuestionModel(
            courseId: courseId,
            source: source,
            question: '如果学生在“$concept”上表现薄弱，合理的改进方式是？',
            optionA: '回到本章知识节点，结合示例、任务和反馈重新练习',
            optionB: '跳过本章直接进入无关内容',
            optionC: '删除学习记录避免暴露问题',
            optionD: '只看答案不理解过程',
            answerIndex: 0,
          ));
          break;
        default:
          templates.add(QuestionModel(
            courseId: courseId,
            source: source,
            question: '“$concept”在课程知识图谱中的作用更接近哪一项？',
            optionA: '连接本章目标、资源、任务和评价证据的关键节点',
            optionB: '与学习路径无关的孤立文字',
            optionC: '只用于装饰页面的标签',
            optionD: '不需要被评价或复习的内容',
            answerIndex: 0,
          ));
      }
    }
    return templates;
  }

  Future<List<_QuizChapter>> _loadPlannedChapters(String courseDir) async {
    final lazyFile = File(
      '$courseDir${Platform.pathSeparator}配置${Platform.pathSeparator}lazy_generation.json',
    );
    final chaptersFile = File(
      '$courseDir${Platform.pathSeparator}配置${Platform.pathSeparator}chapters.json',
    );
    final chapterDetails = <int, Map<String, dynamic>>{};
    if (await chaptersFile.exists()) {
      try {
        final list = jsonDecode(await chaptersFile.readAsString()) as List;
        for (final item in list.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final number = int.tryParse(map['number']?.toString() ?? '') ?? 0;
          if (number > 0) chapterDetails[number] = map;
        }
      } catch (e, st) {
        swallowDebug(e, tag: 'QuizGen.loadChapters', stack: st);
      }
    }
    if (await lazyFile.exists()) {
      try {
        final json =
            jsonDecode(await lazyFile.readAsString()) as Map<String, dynamic>;
        final chapters = (json['chapters'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        final result = <_QuizChapter>[];
        for (final chapter in chapters) {
          final number =
              int.tryParse(chapter['chapter_number']?.toString() ?? '') ?? 0;
          if (number <= 0) continue;
          final detail = chapterDetails[number] ?? const {};
          final titleText =
              chapter['chapter_title']?.toString().trim().isNotEmpty == true
                  ? chapter['chapter_title'].toString().trim()
                  : detail['title']?.toString().trim() ?? '第$number章';
          result.add(_QuizChapter(
            number: number,
            title: _normalizeChapterTitle(number, titleText),
            objectives: _stringList(detail['objectives']),
            keyPoints: _stringList(detail['key_points']),
            difficultPoints: _stringList(detail['difficult_points']),
          ));
        }
        result.sort((a, b) => a.number.compareTo(b.number));
        return result;
      } catch (e, st) {
        swallowDebug(e, tag: 'QuizGen.loadLazyPlan', stack: st);
      }
    }
    return <_QuizChapter>[];
  }

  /// 从 MD 内容生成测验题目
  Future<List<QuestionModel>> _generateQuestionsFromMd({
    required String chapterTitle,
    required String mdContent,
    required int count,
    required String courseId,
  }) async {
    // 截取 MD 内容（避免 prompt 过长）
    final content =
        mdContent.length > 3000 ? mdContent.substring(0, 3000) : mdContent;

    final prompt = '''
请根据以下课程内容，生成 $count 道四选一测验题。

章节标题：$chapterTitle

课程内容：
$content

请严格按以下 JSON 格式输出（数组）：
[
  {
    "question": "题目内容",
    "options": ["选项A", "选项B", "选项C", "选项D"],
    "answerIndex": 0,
    "explanation": "解析说明"
  }
]

要求：
1. 题目覆盖课程核心知识点
2. 四个选项要有区分度
3. 答案正确（answerIndex 范围 0-3）
4. 解析简洁明了
''';

    try {
      final response = await _ai.chat(
        [
          {'role': 'user', 'content': prompt}
        ],
        systemPrompt: '你是一个专业的测验出题助手。请只输出 JSON，不要包含其他内容。',
      );

      // 解析 AI 响应
      final jsonStr = _extractJson(response);
      if (jsonStr == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final questions = <QuestionModel>[];

      for (final item in jsonList) {
        if (item is! Map<String, dynamic>) continue;

        final options = List<String>.from(item['options'] ?? []);
        if (options.length < 4) continue;

        final q = QuestionModel(
          question: item['question']?.toString() ?? '',
          optionA: options[0],
          optionB: options[1],
          optionC: options[2],
          optionD: options[3],
          answerIndex: item['answerIndex'] as int? ?? 0,
          source: chapterTitle,
        );

        if (q.question.isNotEmpty) {
          questions.add(q);
        }
      }

      return questions;
    } catch (e) {
      swallowDebug(e, tag: 'QuizGen.aiChat');
      return [];
    }
  }

  /// 从 AI 响应中提取 JSON 字符串
  String? _extractJson(String response) {
    // 尝试直接解析
    try {
      jsonDecode(response);
      return response;
    } catch (_) {}

    // 尝试提取 ```json ... ``` 块
    final jsonBlockPattern = RegExp(r'```(?:json)?\s*\n([\s\S]*?)\n```');
    final match = jsonBlockPattern.firstMatch(response);
    if (match != null) {
      return match.group(1);
    }

    // 尝试提取 [ ... ] 块
    final arrayPattern = RegExp(r'\[[\s\S]*\]');
    final arrayMatch = arrayPattern.firstMatch(response);
    if (arrayMatch != null) {
      return arrayMatch.group(0);
    }

    return null;
  }

  /// 检查课程是否已有测验题目
  Future<bool> hasQuestions(String courseId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as c FROM questions WHERE course_id = ?",
      [courseId],
    );
    final count = (result.first['c'] as int?) ?? 0;
    return count > 0;
  }

  /// 获取课程测验题目数量
  Future<int> getQuestionCount(String courseId) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as c FROM questions WHERE course_id = ?",
      [courseId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<String> _getCourseDir(String courseId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      return '${appDir.path}${Platform.pathSeparator}courses${Platform.pathSeparator}$courseId';
    } catch (_) {
      return 'courses${Platform.pathSeparator}$courseId';
    }
  }

  String _normalizeChapterTitle(int number, String value) {
    var title = value.trim();
    if (title.startsWith('第$number章')) return title;
    title =
        title.replaceFirst(RegExp(r'^第\s*[一二三四五六七八九十\d]+\s*章\s*'), '').trim();
    return '第$number章 $title'.trim();
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? <String>[] : <String>[text];
  }

  int _chapterSortKey(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final m = RegExp(r'第\s*([一二三四五六七八九十\d]+)\s*章').firstMatch(name);
    if (m == null) return 9999;
    return _chapterNumber(m.group(1)!) ?? 9999;
  }

  int? _chapterNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) return 10 + (digits[value.substring(1)] ?? 0);
    if (value.endsWith('十')) return (digits[value.substring(0, 1)] ?? 0) * 10;
    if (value.contains('十')) {
      final parts = value.split('十');
      return (digits[parts[0]] ?? 0) * 10 + (digits[parts[1]] ?? 0);
    }
    return digits[value];
  }
}

class _QuizChapter {
  final int number;
  final String title;
  final List<String> objectives;
  final List<String> keyPoints;
  final List<String> difficultPoints;

  const _QuizChapter({
    required this.number,
    required this.title,
    required this.objectives,
    required this.keyPoints,
    required this.difficultPoints,
  });

  String get shortTitle =>
      title.replaceFirst(RegExp(r'^第\s*[一二三四五六七八九十\d]+\s*章\s*'), '').trim();
}

/// 生成结果
class GenerationResult {
  final List<GenerationChapterResult> generated = [];
  final List<String> errors = [];
  String? error;

  bool get hasError => error != null || errors.isNotEmpty;
  bool get isEmpty => generated.isEmpty;

  int get totalQuestions =>
      generated.fold<int>(0, (sum, r) => sum + r.questionCount);
}

class GenerationChapterResult {
  final String chapter;
  final int questionCount;

  GenerationChapterResult({
    required this.chapter,
    required this.questionCount,
  });
}
