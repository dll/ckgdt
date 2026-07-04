import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../core/error_handler.dart';
import '../data/local/database_helper.dart';
import 'course_context_service.dart';
import 'course_data_service.dart';

/// 从 data/{courseId}/ 理论/*-测验.md 动态导入课程测验题目
class CkgdtQuizImporter {
  static final CkgdtQuizImporter instance = CkgdtQuizImporter._();
  CkgdtQuizImporter._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final CourseContextService _courseContext = CourseContextService();

  /// 导入当前课程的测验题目
  Future<int> importCkgdtQuizzes() async {
    final db = await _dbHelper.database;
    final course = await _courseContext.getActiveCourse();
    final courseId = course.id;

    // 通过 CourseDataService 动态获取测验文件列表
    final pkg = await CourseDataService.instance.getPackage(courseId);
    if (pkg.quizFiles.isEmpty) {
      debugPrint('=== CkgdtQuizImporter: No quiz files found for $courseId');
      return 0;
    }

    // 检查是否已导入
    final existing = await db.rawQuery(
      "SELECT COUNT(*) as c FROM questions WHERE course_id = ?",
      [courseId],
    );
    final count = (existing.first['c'] as int?) ?? 0;
    final expectedCount = pkg.quizFiles.length * 10; // 假设每章10题
    if (count >= expectedCount) {
      debugPrint('=== CkgdtQuizImporter: Already have $count questions (expected $expectedCount), skip');
      return 0;
    }

    // 删除旧数据
    await db.delete('questions', where: 'course_id = ?', whereArgs: [courseId]);

    int totalImported = 0;
    for (final quizFile in pkg.quizFiles) {
      try {
        final content = await rootBundle.loadString(quizFile.path);
        final chapterName = _extractChapterName(quizFile.fileName);
        final questions = _parseQuizMd(content, chapterName);
        for (final q in questions) {
          q['course_id'] = courseId;
          await db.insert('questions', q, conflictAlgorithm: ConflictAlgorithm.replace);
          totalImported++;
        }
        debugPrint('=== CkgdtQuizImporter: ${quizFile.fileName} → ${questions.length} questions');
      } catch (e, st) {
        swallowDebug(e, tag: 'CkgdtQuizImporter.${quizFile.fileName}', stack: st);
      }
    }

    debugPrint('=== CkgdtQuizImporter: Total imported $totalImported questions for $courseId');
    return totalImported;
  }

  /// 从文件名提取章节名
  String _extractChapterName(String fileName) {
    // "第1章 课程知识图谱基础-测验.md" → "课程知识图谱基础"
    final match = RegExp(r'第\d+章\s+(.+?)-测验').firstMatch(fileName);
    return match?.group(1)?.trim() ?? fileName.replaceAll('.md', '');
  }

  /// 解析单个测验MD文件
  List<Map<String, dynamic>> _parseQuizMd(String content, String chapterName) {
    final questions = <Map<String, dynamic>>[];
    final blocks = content.split(RegExp(r'###\s+第\d+题'));

    for (var i = 1; i < blocks.length; i++) {
      final q = _parseQuestionBlock(blocks[i], chapterName);
      if (q != null) questions.add(q);
    }
    return questions;
  }

  Map<String, dynamic>? _parseQuestionBlock(String block, String chapterName) {
    final questionMatch = RegExp(r'\*\*题目\*\*[：:]\s*(.+?)(?=\n\s*A\.)', dotAll: true).firstMatch(block);
    if (questionMatch == null) return null;
    final question = questionMatch.group(1)!.trim();

    final optionA = _extractOption(block, r'A\.\s*(.+?)(?=\n\s*B\.)');
    final optionB = _extractOption(block, r'B\.\s*(.+?)(?=\n\s*C\.)');
    final optionC = _extractOption(block, r'C\.\s*(.+?)(?=\n\s*D\.)');
    final optionD = _extractOption(block, r'D\.\s*(.+?)(?=\n\s*\*\*正确答案|$)');

    if (optionA == null || optionB == null || optionC == null || optionD == null) return null;

    final answerMatch = RegExp(r'\*\*正确答案\*\*[：:]\s*([A-D])').firstMatch(block);
    if (answerMatch == null) return null;

    return {
      'source': chapterName,
      'question': question,
      'option_a': optionA,
      'option_b': optionB,
      'option_c': optionC,
      'option_d': optionD,
      'answer_index': 'ABCD'.indexOf(answerMatch.group(1)!),
    };
  }

  String? _extractOption(String block, String pattern) {
    return RegExp(pattern, dotAll: true).firstMatch(block)?.group(1)?.trim();
  }
}
