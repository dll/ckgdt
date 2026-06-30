import '../../core/error_handler.dart';
import '../../data/local/database_helper.dart';
import '../auth_service.dart';
import '../course_context_service.dart';

/// Builds a compact, live teaching context for agents and AI skills.
///
/// This keeps all agents grounded in the current course instead of relying on
/// static examples baked into individual prompts.
class AgentTeachingContextService {
  AgentTeachingContextService._();

  static final AgentTeachingContextService instance =
      AgentTeachingContextService._();

  final CourseContextService _courseContext = CourseContextService();

  Future<String> buildPromptContext({String? userMessage}) async {
    try {
      final course = await _courseContext.getActiveCourse();
      final chapters = await _courseContext.chapterTitles();
      final db = await DatabaseHelper.instance.database;
      final user = AuthService().currentUser;

      final conceptCount = await _countScoped(db, 'knowledge_concepts');
      final relationCount = await _countScoped(db, 'concept_relations');
      final graphCount = await _countScoped(db, 'graphs');
      final questionCount = await _countScoped(db, 'questions');
      final resourceCount = await _countScoped(db, 'resource_files');
      final labTaskCount = await _countScoped(db, 'lab_tasks');
      final workCount = await _countScoped(db, 'student_works');
      final groupCount = await _countScoped(db, 'assessment_groups');
      final projectCount = await _countScoped(db, 'assessment_projects');
      final caseCount = await _countScoped(db, 'teaching_cases');
      final objectivesCount = await _countCourseObjectives(db, course.name);
      final batchCount = await _countAchievementBatches(db, course.name);
      final topConcepts = await _topConcepts(db);

      final chapterText = chapters.isEmpty
          ? '未维护章节'
          : chapters.take(8).map((c) => '- $c').join('\n');
      final conceptText = topConcepts.isEmpty
          ? '暂无核心概念'
          : topConcepts.map((c) => '- $c').join('\n');

      return '''
## 当前课程教学上下文

- 平台：课程知识图谱与数字孪生（CKGDT）
- 当前课程：${course.name}
- 课程 ID：${course.id}
- 当前用户：${user?.realName ?? user?.userId ?? '未登录'}（${user?.role ?? 'unknown'}）
- 章节数：${chapters.length}

### 章节
$chapterText

### 数据概览
- 知识图谱：$conceptCount 个概念，$relationCount 条关系，$graphCount 个图谱
- 题库与资源：$questionCount 道题，$resourceCount 个资源
- 实验与作品：$labTaskCount 个实验任务，$workCount 个学生作品
- 考核与达成：$groupCount 个考核分组，$projectCount 个项目，$objectivesCount 个课程目标，$batchCount 个达成批次
- 教学案例：$caseCount 个

### 核心概念参考
$conceptText

### 工作原则
- 所有建议必须服务当前课程，不沿用固定的《移动应用开发》内容，除非用户明确要求分析旧课程。
- 回答教师时优先连接“教学设计、实验任务、考核评价、达成改进、案例演示”。
- 回答学生时优先连接“知识图谱学习、测验练习、实验提交、作品改进、个人成长”。
- 涉及事实数据时优先使用上面的本地数据；没有数据时明确提示需要先导入或维护。
''';
    } catch (e, st) {
      swallowDebug(e, tag: 'AgentTeachingContextService.build', stack: st);
      return '';
    }
  }

  Future<int> _countScoped(dynamic db, String table) async {
    try {
      final scope = await _courseContext.scopedWhere();
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM $table WHERE ${scope.where}',
        scope.args,
      );
      return (rows.first['c'] as int?) ?? 0;
    } catch (e) {
      swallow(e, tag: 'AgentTeachingContextService.count.$table');
      return 0;
    }
  }

  Future<int> _countCourseObjectives(dynamic db, String courseName) async {
    try {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM course_objectives WHERE course_name = ?',
        [courseName],
      );
      return (rows.first['c'] as int?) ?? 0;
    } catch (e) {
      swallow(e, tag: 'AgentTeachingContextService.objectives');
      return 0;
    }
  }

  Future<int> _countAchievementBatches(dynamic db, String courseName) async {
    try {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM achievement_batches WHERE course_name = ?',
        [courseName],
      );
      return (rows.first['c'] as int?) ?? 0;
    } catch (e) {
      swallow(e, tag: 'AgentTeachingContextService.batches');
      return 0;
    }
  }

  Future<List<String>> _topConcepts(dynamic db) async {
    try {
      final scope = await _courseContext.scopedWhere(
        extraWhere: "concept_name IS NOT NULL AND concept_name != ''",
      );
      final rows = await db.rawQuery('''
        SELECT concept_name, chapter, importance
        FROM knowledge_concepts
        WHERE ${scope.where}
        ORDER BY
          CASE importance
            WHEN 'core' THEN 0
            WHEN 'important' THEN 1
            ELSE 2
          END,
          chapter ASC,
          id ASC
        LIMIT 8
      ''', scope.args);
      return rows.map<String>((r) {
        final name = (r['concept_name'] ?? '').toString();
        final chapter = r['chapter'];
        final importance = (r['importance'] ?? '').toString();
        final parts = <String>[name];
        if (chapter != null) parts.add('第$chapter章');
        if (importance.isNotEmpty) parts.add(importance);
        return parts.join(' · ');
      }).toList();
    } catch (e) {
      swallow(e, tag: 'AgentTeachingContextService.topConcepts');
      return const [];
    }
  }
}
