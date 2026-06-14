import '../../../core/error_handler.dart';
import 'package:sqflite/sqflite.dart';
import '../base_agent.dart';
import '../agent_model.dart';
import '../../ai_service.dart';
import '../../archive_template_loader.dart';
import '../../archive_context_service.dart';
import '../../../core/constants/archive_periods.dart' as periods;
import '../../../data/local/archive_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/archive_document_model.dart';

class ArchiveAgent extends BaseAgent {
  final _dao = ArchiveDao();
  final _ai = AiService();
  final _ctx = ArchiveContextService();

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
          AgentCase(
              title: '生成期末课程总结',
              userInput: '请生成期末课程总结',
              agentReply: '生成包含教学概况、成绩分析、经验反思的课程总结报告'),
          AgentCase(
              title: '生成试卷审核表',
              userInput: '请生成试卷审核表',
              agentReply: '生成包含命题质量、难度分布、审核意见的试卷审核表'),
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
    final contextData =
        await _collectContext(db, documentType, courseType: courseType);

    // 三段式增强：[REFERENCE] 历届模板（few-shot 风格学习材料）+ [SYSTEM_FACTS] 系统事实
    // 这两段只在能拿到时才注入；拿不到（assets 缺 / DB 没数据）走原有 prompt 逻辑不变。
    final periodZh = periods.periodLabel(period); // beginning -> 期初
    final referenceMd = await ArchiveTemplateLoader.loadPrimary(
      periodZh: periodZh,
      docType: documentType,
    );
    String? systemFacts;
    try {
      systemFacts = await _ctx.collectForPrompt();
    } catch (e, st) {
      swallowDebug(e, tag: 'ArchiveAgent.collectForPrompt', stack: st);
    }

    final prompt = _buildPrompt(title, documentType, period, courseType,
        templateRef: templateRef,
        context: contextData,
        referenceMd: referenceMd,
        systemFacts: systemFacts);
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

  Future<Map<String, dynamic>> _collectContext(Database db, String documentType,
      {String courseType = 'assess'}) async {
    final context = <String, dynamic>{};
    try {
      if (documentType == 'syllabus') {
        final rows = await db.query('syllabus_items', limit: 50);
        context['syllabus_items'] = rows;
      } else if (documentType == 'lesson_plan') {
        final rows = await db.query('lesson_plans', limit: 50);
        context['lesson_plans'] = rows;
        final teachingDocs = await _dao.getDocuments(
          period: 'beginning',
          courseType: courseType,
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
        final taskDocs = await _dao.getDocuments(
          period: 'beginning',
          courseType: courseType,
          documentType: 'teaching_task',
        );
        if (taskDocs.isNotEmpty) {
          context['teaching_task_content'] = taskDocs.first.content ?? '';
        }
        final scheduleDocs = await _dao.getDocuments(
          period: 'beginning',
          courseType: courseType,
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
    final checklist = _reviewChecklist(doc.documentType);
    final courseTypeLabel = doc.courseType == 'exam' ? '考试' : '考查';
    final prompt =
        '''你是一位严谨的教学归档审核专家。请严格按照以下标准逐项审核，每项给出 ✅ 通过 / ⚠️ 建议修改 / ❌ 不通过 并说明理由。

=== 文档基本信息 ===
- **标题**：${doc.title}
- **文档类型**：${_docTypeLabel(doc.documentType)}
- **教学阶段**：${periods.periodLabel(doc.period)}
- **课程类型**：$courseTypeLabel

=== 通用审核标准 ===
1. **内容完整性**：文档是否覆盖了该类型应包含的全部要素，是否存在明显缺失
2. **格式规范性**：是否符合教学文档的标准格式，Markdown 表格/标题/列表是否正确
3. **数据准确性**：课程名称、教师姓名、学时数、班级等信息是否具体明确，无占位符（如"________"）
4. **语言规范性**：表述是否正式规范，无口语化或模糊表达
5. **一致性**：文档内部的课程类型、学期等信息是否前后一致

=== 专项审核标准（$checklist）===

=== 审核结论 ===
请在最后给出总体评价：
- **综合评级**：优秀 / 良好 / 需修改 / 不合格
- **必须修改项**：列出必须修改的关键问题
- **建议改进项**：列出可选的改进建议

=== 待审文档 ===
${doc.content ?? '（文档无内容）'}''';
    final messages = [
      {'role': 'system', 'content': '你是一位严谨的教学归档审核专家，请严格按照标准逐项审核，给出客观评价。'},
      {'role': 'user', 'content': prompt},
    ];
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return result.content;
  }

  String _docTypeLabel(String dt) {
    const labels = {
      'teaching_task': '教学任务书',
      'syllabus': '教学大纲',
      'calendar': '校历',
      'course_schedule': '课程课表',
      'teaching_schedule': '教学进度表',
      'lesson_plan': '教学教案',
      'courseware': '教学课件',
      'roll_call': '学生点名册',
      'midterm_progress_check': '课程进度执行检查',
      'midterm_homework_review': '作业与批阅次数统计',
      'midterm_exam': '期中试卷',
      'midterm_analysis': '期中成绩分析',
      'midterm_check': '期中检查表',
      'teaching_log': '教学日志',
      'final_exam': '期末试卷',
      'final_analysis': '期末成绩分析',
      'course_summary': '课程总结',
      'exam_review_form': '试卷审核表',
      'final_assessment': '期末考核材料',
      'assessment_review_form': '考核审核表',
      'print_report': '印刷审批表',
      'archive_form': '归档确认表',
    };
    return labels[dt] ?? dt;
  }

  String _reviewChecklist(String dt) {
    const checklists = {
      'teaching_task': '''
- 教师姓名是否与教学任务书原始数据一致
- 课程名称、总学时、讲授/实验学时是否完整
- 教学班级、计划人数是否填写
- 院（系）/教研室主任签章栏是否预留''',
      'syllabus': '''
- 课程简介是否清晰说明课程定位与目标
- 教学内容与学时分配是否合理，各章节学时之和是否等于总学时
- 考核方式是否明确（考试/考查），成绩构成比例是否具体
- 参考教材是否列出书名、作者、出版社''',
      'calendar': '''
- 是否不包含任何课程、教师、班级等课程专属信息（必须是全校通用校历）
- 教学周历是否覆盖完整学期（周次、日期范围、说明）
- 节假日安排是否完整（法定假日、调课说明）
- 作息时间是否分冬季/夏季标注
- 关键节点是否包含（考试周、暑假等）''',
      'course_schedule': '''
- 理论课与实验课是否区分清晰
- 实验分组是否合理，每组时间/地点是否明确
- 周次、星期、节次是否连续无冲突''',
      'teaching_schedule': '''
- 理论教学进度与实验教学进度是否分别列出
- 周次、日期、章节、教学内容是否完整对应
- 教学方式是否多样化（讲授/讨论/实践等）
- 与教学大纲的学时分配是否一致''',
      'lesson_plan': '''
- 每份教案的教学目标是否具体可衡量
- 教学重点与难点是否明确
- 教学内容与过程是否详细，时间分配是否合理
- 教学方法是否针对内容特点选择
- 课后作业是否与教学目标对应
- 教学反思栏是否预留''',
      'courseware': '''
- 课件清单是否覆盖全部章节
- 资源类型标注是否清晰（PPT/视频/文档等）
- 是否与教学进度表章节对应''',
      'midterm_progress_check': '''
- 是否明确依据教学进度表核对期中前课程执行情况
- 是否覆盖周次、章节、理论/实验学时和实践任务
- 是否标明进度滞后、超前、调课或补课情况
- 对进度偏差是否给出原因和后续改进安排''',
      'midterm_homework_review': '''
- 是否列出期中前作业布置次数和批阅次数
- 批阅记录是否覆盖教学班级和主要学生提交
- 是否说明未批、迟批或反馈不足情况
- 是否有后续批阅改进措施''',
      'midterm_exam': '''
- 期中考试或阶段考核材料是否完整
- 考核内容是否覆盖期中前核心知识点和能力目标
- 是否有评分标准、成绩记录或质量分析
- 是否说明阶段考核结果对后续教学的改进作用''',
    };
    return checklists[dt] ??
        '''
- 文档结构是否完整，各要素是否齐全
- 内容是否与教学阶段、课程类型匹配
- 各项数据是否合理、具体''';
  }

  String _buildPrompt(
    String title,
    String documentType,
    String period,
    String courseType, {
    String? templateRef,
    Map<String, dynamic>? context,
    String? referenceMd,
    String? systemFacts,
  }) {
    final buf = StringBuffer();

    // [REFERENCE] 历届模板（首选）—— LLM 学结构 + 风格，不是抄字段
    if (referenceMd != null && referenceMd.isNotEmpty) {
      buf.writeln('=== [REFERENCE] 历届同类材料（仅供学习结构和行文风格，事实数据以下方系统事实为准）===');
      // 太长会挤占其它段；截 3500 字（中文约 ~7000 token），保大头去尾。
      final ref = referenceMd.length > 3500
          ? '${referenceMd.substring(0, 3500)}\n...（截断，原文更长）'
          : referenceMd;
      buf.writeln(ref);
      buf.writeln('=== [REFERENCE] 结束 ===\n');
    }

    // [SYSTEM_FACTS] 当前系统事实清单（最高权威）
    if (systemFacts != null && systemFacts.isNotEmpty) {
      buf.writeln('=== [SYSTEM_FACTS] 系统当前事实（与上方模板冲突时以此为准）===');
      buf.writeln(systemFacts);
      buf.writeln('=== [SYSTEM_FACTS] 结束 ===\n');
    }

    // [TASK] 后续是原有的指令（基本信息 / 类型专项 / 参考数据 / 输出要求）
    buf.writeln('=== [TASK] 生成指令 ===');
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
      final clsMatch = RegExp(r'教学班级[：:]\s*(.+?)[\n|]').firstMatch(task);
      if (clsMatch != null) classInfo = clsMatch.group(1)!.trim();
      final hMatch = RegExp(r'总学时[：:]\s*(\d+)').firstMatch(task);
      if (hMatch != null) totalHours = hMatch.group(1)!.trim();
      final lecMatch = RegExp(r'讲授[：:]\s*(\d+)').firstMatch(task);
      if (lecMatch != null) theoryHours = lecMatch.group(1)!.trim();
      final labMatch = RegExp(r'(?:实验|实践)[：:]\s*(\d+)').firstMatch(task);
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
      buf.writeln('总学时：$totalHours（理论$theoryHours/实验$labHours）');
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
**总学时：** $totalHours学时 （理论$theoryHours学时 / 实验$labHours学时）
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
**学时/学分：** $totalHours学时 / ____学分
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
    buf.writeln('1. 用 Markdown 格式输出完整的文档内容，包含标题和正式表格。');
    buf.writeln(
        '2. **教师姓名 / 班级 / 专业 / 学期 / 学时 / 学分 / 课程类型** —— 必须使用 [SYSTEM_FACTS] 段的真实数据，与 [REFERENCE] 不一致时**优先用 [SYSTEM_FACTS]**，禁止照抄历届模板里的旧值。');
    buf.writeln(
        '3. **章节标题 / 章节数 / 实验项目编号** —— 必须使用 [SYSTEM_FACTS] 第 3、4 段的真实数据，禁止编造。');
    buf.writeln(
        '4. **课程目标条数 / 毕业要求映射** —— 沿用 [REFERENCE] 模板的 OBE 框架（教育部规范），不可改条数。');
    buf.writeln(
        '5. **章节内容详细描述 / 教学重难点 / 思政元素** —— 你可以发挥专业判断创作，但必须与本章主题契合（如鸿蒙章谈民族品牌 ✓，跨平台章谈民族品牌 ✗）。');
    buf.writeln('6. **教学日历是全校校历，不涉及任何课程、教师或班级**。');
    buf.writeln('7. 系统数据缺失时，**用专业判断补全并标 [推断]**，禁止编造数字（学时 / 分数 / 题量等）。');
    return buf.toString();
  }
}
