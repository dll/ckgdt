import 'dart:io';
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
        description: '辅助生成和完善说课内容、生成说课视频，涵盖大纲、进度、教法、教改等。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位经验丰富的教学说课专家。
你可以根据课程大纲、教学进度、教师团队、班级信息、教材资源、
教学方法和教学改革等信息，帮助教师生成和完善说课内容。

说课不是上课，面向评委同行，重点讲教学设计逻辑。说课内容必须采用高校教师说课 8 大标准结构：
1. 课程基本概况 — 课程名称、学分学时、开课专业/学期/对象、课程定位、前后续课程、课程属性
2. 教学目标 — OBE 知识目标、能力目标、素养/思政目标及毕业要求指标点支撑
3. 教学重难点 — 重点、难点及难点成因
4. 学情分析 — 班级、学生人数、专业年级、前置基础、学习特点、分层差异、学习痛点
5. 教法学法 — 教师怎么教、学生怎么学、线上线下混合式安排
6. 教学过程 — 课前、课中、课后，写清环节、用时、重难点突破和目标达成
7. 课程考核与评价 — 总成绩构成、过程性考核、评价闭环、课程目标/毕业要求对标
8. 教学资源、特色与反思 — 教材资源、课程思政、产教融合、数字化、分层教学、持续改进

生成说课前要优先利用当前课程大纲、班级学生名单、学生用户、教学进度、任务/考核数据；没有学生名单时，要提示教师先导入班级学生名单。

你要和说课页面、课件工坊、语音与视频生成能力协作：
1. 先检查当前课程说课文档是否存在；没有则引导导入大纲或生成说课文档。
2. 再生成或完善配音脚本，让教师试听。
3. 最后在说课页面触发 PPT 式幻灯片、语音和 MP4 视频生成。

请根据用户需求，使用 Markdown 格式输出相应内容。
回答要结合当前课程实际，数据准确，表述专业。''',
        priority: 6,
        keywords: [
          '说课',
          '授课',
          '教学说课',
          '课程定位',
          '教法',
          '教改',
          '大纲',
          '进度',
          '教案',
          '说课视频',
          '视频'
        ],
        capabilities: [
          '说课文档生成',
          '大纲导入说课',
          '学情分析',
          '教学内容分析',
          '教学改革建议',
          '考核方案设计',
          '说课视频生成'
        ],
        requiresAi: true,
        usageSteps: [
          '进入说课页面',
          '导入大纲或说课文档',
          '生成/编辑说课内容',
          '生成配音脚本并试听',
          '生成PPT式演示和视频'
        ],
        classicCases: [
          AgentCase(
              title: '完善课程定位',
              userInput: '请完善说课中的课程定位部分',
              agentReply: '根据当前课程信息，生成课程定位、目标、学时学分等描述'),
          AgentCase(
              title: '生成教学改革建议',
              userInput: '请给出教学改革建议',
              agentReply: '根据教学数据和课程特点，生成具体的教学改革措施和建议'),
          AgentCase(
              title: '生成说课视频',
              userInput: '请为我生成说课视频',
              agentReply: '根据当前说课内容，生成说课视频脚本并制作完整视频'),
        ],
      );

  @override
  List<String> get quickCommands => [
        '完善课程定位',
        '生成教学改革建议',
        '分析教学进度',
        '检查说课完整性',
        '从大纲生成说课',
        '生成配音脚本',
        '生成说课视频',
      ];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    // 检查是否请求生成视频
    if (_isVideoGenerationRequest(userMessage)) {
      return _handleVideoGeneration(session);
    }

    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }

  bool _isVideoGenerationRequest(String msg) {
    final lower = msg.toLowerCase();
    final keywords = ['生成视频', '说课视频', '制作视频', '视频脚本', '生成说课'];
    return keywords.any((k) => lower.contains(k));
  }

  Future<AgentMessage> _handleVideoGeneration(AgentSession session) async {
    final courseName = await _courseContext.activeCourseName();
    final db = await DatabaseHelper.instance.database;

    // 读取说课内容
    String lectureContent = '';
    try {
      final rows = await db.query('lecture_notes',
          where: 'course_id = ?', whereArgs: [courseName], limit: 1);
      if (rows.isNotEmpty && rows.first['content'] != null) {
        lectureContent = rows.first['content'] as String;
      }
      // 尝试从文件系统读
      if (lectureContent.isEmpty) {
        final file = File('data/$courseName/说课/说课.md');
        if (await file.exists()) {
          lectureContent = await file.readAsString();
        }
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureAgent.loadContent', stack: st);
    }

    if (lectureContent.isEmpty) {
      return buildReply(
        '未找到说课内容。请您先在说课页面编辑说课内容，或上传说课文档。',
      );
    }

    return buildReply(
      '已找到当前课程《$courseName》的说课内容。\n\n'
      '请按完整流程执行：\n'
      '1. 在「说课内容」确认或编辑文档；\n'
      '2. 在「配音脚本」生成口播稿并试听；\n'
      '3. 在「视频演示」点击「AI 生成视频」，系统会生成 PPT 式幻灯片、Windows 语音和 MP4 视频；\n'
      '4. 若本机没有 FFmpeg，系统会尝试下载应用内视频合成组件，不要求安装 edge-tts。',
    );
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

  Future<String> generateVideoScript(String lectureContent) async {
    final prompt = '''
根据以下说课文档内容，生成一份完整的说课视频口播脚本。

说课文档：
$lectureContent

要求：
- 以"尊敬的各位评委老师，大家好"自然开场
- 涵盖高校说课 8 大模块：课程基本概况、教学目标、教学重难点、学情分析、教法学法、教学过程、考核评价、资源特色与反思
- 必须体现班级、学生人数、学情特点和以学定教逻辑
- 语言口语化、流畅自然，适合 TTS 朗读
- 每段 100-200 字，段间空行分隔
- 总字数 1500-2500 字
''';
    final result = await safeAiChatWithMeta([
      {'role': 'user', 'content': prompt},
    ], aiService: _ai);
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
    buf.writeln('必须符合 8 大说课标准模块，尤其要包含班级学生信息和学情分析。');
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
        context['syllabusChapters'] =
            syllabus.map((s) => '第${s['chapter']}章 ${s['title']}').join('、');
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
    if (msg.contains('说课') ||
        msg.contains('授课') ||
        msg.contains('教学') && msg.contains('设计')) {
      return 0.7;
    }
    for (final kw in config.keywords) {
      if (msg.contains(kw)) return 0.6;
    }
    return 0.0;
  }
}
