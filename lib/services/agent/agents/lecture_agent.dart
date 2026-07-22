import '../../../core/error_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../base_agent.dart';
import '../agent_model.dart';
import '../../ai_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/course_context_service.dart';

class LectureAgent extends BaseAgent {
  final _ai = AiService();
  final _courseContext = CourseContextService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'lecture',
        name: '说课助手',
        emoji: '🎤',
        description: '辅助生成和完善说课内容，涵盖大纲、进度、教法、教改等。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位经验丰富的教学说课专家。
你可以根据课程大纲、教学进度、教师团队、班级信息、教材资源、
教学方法和教学改革等信息，帮助教师生成和完善说课内容。

说课内容包括：
1. 课程定位与目标 — 课程性质、学时学分、考核方式、面向专业
2. 教学大纲 — 理论教学和实践教学的内容体系
3. 教学进度 — 学期周次的教学安排
4. 教师团队 — 师资队伍情况
5. 班级信息 — 授课班级和分组情况
6. 教材与资源 — 使用教材和课程资源清单
7. 教学方法 — 采用的教学方法和教学手段
8. 教学改革 — 持续改进机制和已实施改革
9. 考核方案 — 考核方式和评价量规

请根据用户需求，使用 Markdown 格式输出相应内容。
回答要结合当前课程实际，数据准确，表述专业。''',
        priority: 6,
        keywords: ['说课', '授课', '教学说课', '课程定位', '教法', '教改', '大纲', '进度', '教案'],
        capabilities: ['说课文档生成', '教学内容分析', '教学改革建议', '考核方案设计'],
        requiresAi: true,
        usageSteps: ['进入说课页面查看当前说课内容', '点击"说课助手"智能体进行对话', '输入需要补充或修改的说课内容'],
        classicCases: [
          AgentCase(
              title: '完善课程定位',
              userInput: '请完善说课中的课程定位部分',
              agentReply: '根据当前课程信息，生成课程定位、目标、学时学分等描述'),
          AgentCase(
              title: '生成教学改革建议',
              userInput: '请给出教学改革建议',
              agentReply: '根据教学数据和课程特点，生成具体的教学改革措施和建议'),
        ],
      );

  @override
  List<String> get quickCommands => [
        '完善课程定位',
        '生成教学改革建议',
        '分析教学进度',
        '检查说课完整性',
      ];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }

  Future<String> generateLectureContent({
    required String section,
    String? currentContent,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final contextData = await _collectContext(db);

    final prompt = _buildPrompt(section, currentContent, context: contextData);
    final messages = [
      {'role': 'system', 'content': config.persona},
      {'role': 'user', 'content': prompt},
    ];
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return result.content;
  }

  String _buildPrompt(String section, String? currentContent,
      {required Map<String, dynamic> context}) {
    final buf = StringBuffer();
    buf.writeln('## 任务');
    buf.writeln('请生成或完善说课文档中的「$section」部分。');
    if (currentContent != null && currentContent.isNotEmpty) {
      buf.writeln('\n### 当前内容');
      buf.writeln(currentContent);
    }
    buf.writeln('\n### 当前课程上下文');
    for (final entry in context.entries) {
      buf.writeln('- **${entry.key}**: ${entry.value}');
    }
    buf.writeln('\n请用 Markdown 格式输出，结构清晰，数据准确。');
    return buf.toString();
  }

  Future<Map<String, dynamic>> _collectContext(Database db) async {
    final context = <String, dynamic>{};
    try {
      final course = await _courseContext.getActiveCourse();
      context['courseName'] = course.name;
      context['courseId'] = course.id;

      final syllabus = await db.query(
        'syllabus_items',
        where: 'course_name = ?',
        whereArgs: [course.name],
        limit: 20,
      );
      if (syllabus.isNotEmpty) {
        context['syllabusChapters'] = syllabus.length;
        context['syllabusChapters'] = syllabus.map((s) => '第${s['chapter']}章 ${s['title']}').join('、');
      }

      final labTasks = await db.query(
        'lab_tasks',
        where: 'course_id = ?',
        whereArgs: [course.id],
        limit: 10,
      );
      context['labTaskCount'] = labTasks.length;

      final progress = await db.query(
        'teaching_progress',
        where: 'course_name = ?',
        whereArgs: [course.name],
        limit: 30,
      );
      context['progressItems'] = progress.length;
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureAgent._collectContext', stack: st);
    }
    return context;
  }

  @override
  double matchScore(String userMessage, AgentSession session) {
    if (session.activeAgentId == config.id) return 0.8;
    final msg = userMessage.toLowerCase();
    if (msg.contains('说课') || msg.contains('授课') || msg.contains('教学') && msg.contains('设计')) return 0.7;
    for (final kw in config.keywords) {
      if (msg.contains(kw)) return 0.6;
    }
    return 0.0;
  }
}
