import '../../../core/error_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../base_agent.dart';
import '../agent_model.dart';
import '../../ai_service.dart';
import '../../../data/local/archive_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/archive_document_model.dart';

class ArchiveAgent extends BaseAgent {
  final _dao = ArchiveDao();
  final _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
    id: 'archive',
    name: '归档助手',
    emoji: '📦',
    description: '辅助生成教学归档材料，支持一键归档与打印。',
    allowedRoles: ['teacher', 'admin'],
    persona: '''你是一位经验丰富的教学归档专家，熟悉课程教学文档的规范与格式。
你可以根据课程类型（考试/考查）和教学阶段（期初/期中/期末），
参考学校模板，生成规范的教学归档文档。

请根据用户需求生成相应文档内容，使用 Markdown 格式输出。''',
    priority: 6,
    keywords: ['归档', '存档', '教学材料', '文档生成', '打印'],
    capabilities: ['教学文档生成', '归档管理', '模板参考', '一键打印'],
    requiresAi: true,
    usageSteps: ['在归档页面选择教学阶段和文档类型', '点击"生成"按钮调用归档助手', '预览并确认内容，然后打印或归档'],
    classicCases: [
      AgentCase(title: '生成期末课程总结', userInput: '请生成期末课程总结', agentReply: '生成包含教学概况、成绩分析、经验反思的课程总结报告'),
      AgentCase(title: '生成试卷审核表', userInput: '请生成试卷审核表', agentReply: '生成包含命题质量、难度分布、审核意见的试卷审核表'),
    ],
  );

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }

  Future<ArchiveDocument> generateDocument({
    required String title,
    required String documentType,
    required String period,
    required String courseType,
    String? templateRef,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final contextData = await _collectContext(db, documentType);
    final prompt = _buildPrompt(title, documentType, period, courseType,
        templateRef: templateRef, context: contextData);
    final messages = [
      {'role': 'system', 'content': config.persona},
      {'role': 'user', 'content': prompt},
    ];
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    final doc = ArchiveDocument(
      title: title,
      documentType: documentType,
      period: period,
      courseType: courseType,
      content: result.content,
      isGenerated: true,
    );
    final id = await _dao.saveDocument(doc);
    return doc.copyWith(id: id);
  }

  Future<Map<String, dynamic>> _collectContext(
      Database db, String documentType) async {
    final context = <String, dynamic>{};
    try {
      if (documentType == 'syllabus') {
        final rows = await db.query('syllabus_items', limit: 50);
        context['syllabus_items'] = rows;
      } else if (documentType == 'lesson_plan') {
        final rows = await db.query('lesson_plans', limit: 50);
        context['lesson_plans'] = rows;
        // Also fetch existing teaching_schedule for context
        final teachingDocs = await _dao.getDocuments(
          period: 'beginning',
          courseType: 'exam',
          documentType: 'teaching_schedule',
        );
        if (teachingDocs.isNotEmpty) {
          context['teaching_schedule_content'] =
              teachingDocs.first.content ?? '';
        }
      } else if (documentType == 'course_summary') {
        final students = await db.query('users', limit: 100);
        final scores = await db.query('achievement_scores', limit: 100);
        context['students'] = students;
        context['scores'] = scores;
      } else if (documentType == 'teaching_schedule') {
        final syllabusRows = await db.query('syllabus_items', limit: 50);
        context['syllabus_items'] = syllabusRows;
        // Also fetch existing teaching_task and course_schedule
        final taskDocs = await _dao.getDocuments(
          period: 'beginning',
          courseType: 'exam',
          documentType: 'teaching_task',
        );
        if (taskDocs.isNotEmpty) {
          context['teaching_task_content'] = taskDocs.first.content ?? '';
        }
        final scheduleDocs = await _dao.getDocuments(
          period: 'beginning',
          courseType: 'exam',
          documentType: 'course_schedule',
        );
        if (scheduleDocs.isNotEmpty) {
          context['course_schedule_content'] = scheduleDocs.first.content ?? '';
        }
      } else if (documentType == 'courseware') {
        final rows = await db.query('resource_files', limit: 100);
        context['resource_files'] = rows;
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveAgent._collectContext', stack: st);
    }
    return context;
  }

  Future<String> reviewDocument(ArchiveDocument doc) async {
    final prompt = '''请审核以下教学归档文档，从以下几个方面给出评价（每条一行，用 Markdown 列表格式）：

1. **内容完整性**：是否覆盖了应包含的全部要素
2. **格式规范性**：是否符合教学文档的格式要求
3. **数据准确性**：内容中涉及的数据是否合理
4. **改进建议**：如有问题请给出具体修改建议

文档标题：${doc.title}
文档类型：${doc.documentType}
教学阶段：${doc.period}

文档内容：
${doc.content ?? '（无内容）'}''';
    final messages = [
      {'role': 'system', 'content': '你是一位教学文档审核专家，请根据学校规范严格审核。'},
      {'role': 'user', 'content': prompt},
    ];
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return result.content;
  }

  String _buildPrompt(
    String title,
    String documentType,
    String period,
    String courseType, {
    String? templateRef,
    Map<String, dynamic>? context,
  }) {
    final buf = StringBuffer();
    buf.writeln('请生成以下教学归档文档：');
    buf.writeln('- 标题：$title');
    buf.writeln('- 文档类型：$documentType');
    buf.writeln('- 教学阶段：$period');
    final courseTypeLabel = courseType == 'exam' ? '考试' : '考查';
    buf.writeln('- 课程类型：$courseTypeLabel');
    if (templateRef != null) buf.writeln('- 参考模板：$templateRef');

    // Extract real teacher name and course info from context dynamically
    String teacherName = '(从参考数据中提取实际教师名)';
    String courseName = '移动应用开发';
    String classInfo = '软件231,软件232';
    const semesterLabel = '2025-2026学年第二学期';
    String totalHours = '96';
    String theoryHours = '24';
    String labHours = '72';
    if (context != null && context.containsKey('teaching_task_content')) {
      final task = context['teaching_task_content'] as String;
      final tMatch = RegExp(r'\*\*教师\*\*[：:]\s*(.+?)[\n|]').firstMatch(task);
      if (tMatch != null) teacherName = tMatch.group(1)!.trim();
      final cMatch = RegExp(r'课程名称[：:]\s*(.+?)[\n|]').firstMatch(task);
      if (cMatch != null) courseName = cMatch.group(1)!.trim();
      final clsMatch =
          RegExp(r'教学班级[：:]\s*(.+?)[\n|]').firstMatch(task);
      if (clsMatch != null) classInfo = clsMatch.group(1)!.trim();
      final hMatch = RegExp(r'总学时[：:]\s*(\d+)').firstMatch(task);
      if (hMatch != null) totalHours = hMatch.group(1)!.trim();
      final lecMatch = RegExp(r'讲授[：:]\s*(\d+)').firstMatch(task);
      if (lecMatch != null) theoryHours = lecMatch.group(1)!.trim();
      final labMatch =
          RegExp(r'(?:实验|实践)[：:]\s*(\d+)').firstMatch(task);
      if (labMatch != null) labHours = labMatch.group(1)!.trim();
    } else if (context != null &&
        context.containsKey('course_schedule_content')) {
      final sched = context['course_schedule_content'] as String;
      final tMatch = RegExp(r'\*\*教师\*\*[：:]\s*(.+?)[\n|]').firstMatch(sched);
      if (tMatch != null) teacherName = tMatch.group(1)!.trim();
    }

    // Build course info block (NOT for calendar - calendar is school-wide)
    if (documentType != 'calendar') {
      buf.writeln('\n=== 课程基本信息（重要：所有数据必须与参考数据严格一致）===');
      buf.writeln('课程名称：$courseName');
      buf.writeln('班级：$classInfo');
      buf.writeln('教师：$teacherName');
      buf.writeln('学期：$semesterLabel');
      buf.writeln('总学时：${totalHours}（理论${theoryHours}/实验${labHours}）');
      buf.writeln('课程类型：$courseTypeLabel（考试或考查，与选择的类型一致）');
    }

    // Type-specific format requirements
    final typePrompts = <String, String>{
      'calendar': '''
=== 校历格式要求 ===
**重要：这是全校通用校历，不含任何特定课程、教师或班级信息！**
请以学年学期维度生成校历：

# 校 历

**学年学期：** $semesterLabel

### 一、教学周历
| 周次 | 日期范围 | 教学周说明 | 备注 |
|------|----------|----------|------|

### 二、节假日安排
列出本学期所有法定节假日及调课说明

### 三、作息时间
- 第1-10周：冬季作息
- 第11周起：夏季作息

### 四、关键节点
- 缓补考试周
- 期末考试周
- 暑假开始时间''',
      'teaching_schedule': '''
=== 教学进度表格式要求 ===
请根据参考数据生成完整的教学进度表。
**重要：教师姓名必须从参考数据中提取，使用真实姓名不要编造！**

格式：

# 教 学 进 度 表

**课程名称：** $courseName
**教师：** $teacherName（必须与参考数据一致！）
**班级：** $classInfo
**总学时：** $totalHours学时 （理论${theoryHours}学时 / 实验${labHours}学时）
**课程类型：** $courseTypeLabel

### 理论教学进度
| 周次 | 日期 | 章节 | 教学内容 | 学时 | 教学方式 | 地点 |

### 实验教学进度
| 周次 | 日期 | 班级 | 实验内容 | 学时 | 地点 |''',
      'lesson_plan': '''
=== 教学教案格式要求 ===
参考已有的 lesson_plans 表数据和教学进度表，生成规范的教学教案。
**重要：教师姓名必须从参考数据中提取，使用真实姓名不要编造！**

格式：

# 教 学 教 案

**课程名称：** $courseName
**教师：** $teacherName（必须与参考数据一致！）
**课程类型：** $courseTypeLabel
**授课章节：** 第__章 ________

### 一、教学目标
### 二、教学重点与难点
### 三、教学内容与过程
### 四、教学方法
### 五、课后作业
### 六、教学反思''',
      'syllabus': '''
=== 教学大纲格式要求 ===
根据 syllabus_items 表数据生成完整的教学大纲。

格式：

# 教 学 大 纲

**课程名称：** $courseName
**课程编号：** ________
**课程类别：** ________
**学时/学分：** ${totalHours}学时 / ____学分
**课程类型：** $courseTypeLabel

### 一、课程简介
### 二、课程目标
### 三、教学内容与学时分配
### 四、教学方法与手段
### 五、考核方式
### 六、参考教材''',
      'courseware': '''
=== 教学课件格式要求 ===
根据 resource_files 表数据列出本课程的教学课件清单。

格式：

# 教 学 课 件

**课程名称：** $courseName

### 课件清单
| 章节 | 资源名称 | 类型 | 说明 |
|------|----------|------|------|''',
    };

    if (typePrompts.containsKey(documentType)) {
      buf.writeln(typePrompts[documentType]!);
    }

    if (context != null && context.isNotEmpty) {
      buf.writeln('\n=== 参考数据（严格使用，不要编造）===');
      context.forEach((k, v) {
        if (v is List && v.isNotEmpty) {
          buf.writeln('\n--- $k (${v.length}条记录) ---');
          for (final item in v) {
            if (item is Map) {
              final lines = item.entries
                  .where((e) => e.value != null)
                  .map((e) => '  ${e.key}: ${e.value}')
                  .join('\n');
              if (lines.isNotEmpty) buf.writeln(lines);
            }
            buf.writeln('---');
          }
        } else if (v is String && v.isNotEmpty) {
          buf.writeln('\n--- $k ---');
          buf.writeln(v.length > 2000 ? '${v.substring(0, 2000)}...（截断）' : v);
        }
      });
    }

    buf.writeln('\n=== 输出要求（必须遵守）===');
    buf.writeln(
        '1. 用 Markdown 格式输出完整的文档内容，包含标题和正式表格。');
    buf.writeln(
        '2. **教师名称必须使用参考数据中的真实姓名，禁止编造或猜测。**');
    buf.writeln(
        '3. 课程类型（$courseTypeLabel）必须与给定的类型一致。');
    buf.writeln(
        '4. 教学日历是全校校历，不涉及任何课程、教师或班级。');
    return buf.toString();
  }
}
