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
    final theoryDir = Directory('$dir${Platform.pathSeparator}理论');

    List<FileSystemEntity> mdFiles = [];
    if (await theoryDir.exists()) {
      mdFiles = await theoryDir
          .list()
          .where((f) => f.path.endsWith('.md'))
          .toList();
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

    for (int i = 0; i < mdFiles.length; i++) {
      final mdFile = mdFiles[i];
      final name = mdFile.path.split(Platform.pathSeparator).last
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

  /// 从 MD 内容生成测验题目
  Future<List<QuestionModel>> _generateQuestionsFromMd({
    required String chapterTitle,
    required String mdContent,
    required int count,
    required String courseId,
  }) async {
    // 截取 MD 内容（避免 prompt 过长）
    final content = mdContent.length > 3000
        ? mdContent.substring(0, 3000)
        : mdContent;

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
      final appDir = await getApplicationSupportDirectory();
      return '${appDir.path}${Platform.pathSeparator}courses${Platform.pathSeparator}$courseId';
    } catch (_) {
      return 'courses${Platform.pathSeparator}$courseId';
    }
  }
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
