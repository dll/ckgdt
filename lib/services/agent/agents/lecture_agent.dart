import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../core/error_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../base_agent.dart';
import '../agent_model.dart';
import '../../ai_service.dart';
import '../../lecture_video_service.dart';
import '../../output_path_service.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/course_context_service.dart';

class LectureAgent extends BaseAgent {
  final _ai = AiService();
  final _courseContext = CourseContextService();
  final _videoService = LectureVideoService();

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

你可以生成说课视频脚本和完整视频。
当用户要求"生成视频"或"说课视频"时，使用工具 generate_lecture_video。

请根据用户需求，使用 Markdown 格式输出相应内容。
回答要结合当前课程实际，数据准确，表述专业。''',
        priority: 6,
        keywords: ['说课', '授课', '教学说课', '课程定位', '教法', '教改', '大纲', '进度', '教案', '说课视频', '视频'],
        capabilities: ['说课文档生成', '教学内容分析', '教学改革建议', '考核方案设计', '说课视频生成'],
        requiresAi: true,
        usageSteps: ['进入说课页面查看当前说课内容', '点击"说课助手"智能体进行对话', '输入需要补充或修改的说课内容', '或要求生成说课视频'],
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
    String teacherName = '';
    try {
      final rows = await db.query('lecture_notes',
          where: 'course_id = ?', whereArgs: ['default'], limit: 1);
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
    } catch (_) {}

    if (lectureContent.isEmpty) {
      return buildReply(
        '未找到说课内容。请您先在说课页面编辑说课内容，或上传说课文档。',
      );
    }

    try {
      final outDir = await _getOutputDir();
      final result = await _videoService.generateVideo(
        lectureContent: lectureContent,
        courseName: courseName,
        teacherName: teacherName,
        outputDir: outDir,
        onProgress: (current, total, message) {},
      );

      if (result != null) {
        return buildReply(
          '✅ 说课视频已生成！\n\n'
              '📹 视频文件：${result.videoPath}\n'
              '📝 字幕文件：${result.srtPath}\n'
              '📄 幻灯片：${result.pdfPath}\n\n'
              '视频位于 "说课" 页面的视频演示选项卡中，可点击播放。\n\n'
              '如需重新生成，请说"重新生成说课视频"。',
          action: AgentAction(
            type: 'agent_result',
            data: {
              'videoPath': result.videoPath,
              'srtPath': result.srtPath,
              'pdfPath': result.pdfPath,
            },
          ),
        );
      } else {
        return buildReply(
          '视频生成失败，请检查：\n'
              '1. FFmpeg 是否正常安装\n'
              '2. edge-tts 是否可用（pip install edge-tts）\n'
              '3. 说课内容是否完整',
        );
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureAgent.generateVideo', stack: st);
      return buildReply('视频生成出错：$e');
    }
  }

  Future<String> _getOutputDir() async {
    final outRoot = await OutputPathService.getOutputDirectory();
    final dir = Directory(p.join(outRoot.path, '说课', 'ai_generated'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir.path;
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
- 涵盖：课程定位、教学内容、教学方法、实践环节、考核评价、教学改革、结语
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
        context['syllabusChapters'] = syllabus
            .map((s) => '第${s['chapter']}章 ${s['title']}')
            .join('、');
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
    if (msg.contains('说课') || msg.contains('授课') ||
        msg.contains('教学') && msg.contains('设计')) {
      return 0.7;
    }
    for (final kw in config.keywords) {
      if (msg.contains(kw)) return 0.6;
    }
    return 0.0;
  }
}
