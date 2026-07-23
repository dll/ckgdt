import 'dart:io';
import 'package:path/path.dart' as p;
import 'ai_service.dart';

class LectureContentService {
  final AiService _ai = AiService();

  static String contentPath(String courseName) => 'data/$courseName/说课/说课.md';

  static String scriptPath(String courseName) => 'data/$courseName/说课/配音脚本.txt';

  static String videoPath(String courseName) =>
      'data/$courseName/说课/说课演示_$courseName.mp4';

  bool hasContent(String courseName) {
    final file = File(contentPath(courseName));
    return file.existsSync() && file.readAsStringSync().trim().isNotEmpty;
  }

  Future<String> generateContent({
    required String courseName,
    required String teacherName,
    required List<Map<String, dynamic>> syllabus,
    required List<Map<String, dynamic>> classes,
    String majorInfo = '',
    String studentProfile = '',
    int totalStudents = 0,
  }) async {
    final prompt = _buildContentPrompt(
      courseName: courseName,
      teacherName: teacherName,
      syllabus: syllabus,
      classes: classes,
      majorInfo: majorInfo,
      studentProfile: studentProfile,
      totalStudents: totalStudents,
    );

    final result = await _ai.chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: '你是一位资深的教学督导和课程设计专家。善于根据课程信息生成规范、完整的说课文档。'
          '说课文档必须基于提供的课程信息生成，体现该课程的独特性，不得使用通用模板或套话。'
          '使用专业、规范的中文，Markdown 格式。',
    );

    return result.isNotEmpty
        ? result
        : _buildFallbackContent(
            courseName: courseName,
            teacherName: teacherName,
            classes: classes,
            majorInfo: majorInfo,
            studentProfile: studentProfile,
            totalStudents: totalStudents,
          );
  }

  Future<String> generateContentFromSyllabusText({
    required String courseName,
    required String teacherName,
    required String syllabusText,
    required List<Map<String, dynamic>> classes,
    String majorInfo = '',
    String studentProfile = '',
    int totalStudents = 0,
  }) async {
    final buf = StringBuffer();
    buf.writeln('## 任务');
    buf.writeln('请根据教师上传或导入的课程大纲文本，生成一份完整、可用于教师交流汇报的说课文档。');
    buf.writeln();
    buf.writeln('## 课程信息');
    buf.writeln('- 课程名称：$courseName');
    if (teacherName.isNotEmpty) buf.writeln('- 说课教师：$teacherName');
    if (majorInfo.isNotEmpty) buf.writeln('- 涉及专业：$majorInfo');
    if (totalStudents > 0) buf.writeln('- 学生总数：$totalStudents 人');
    if (studentProfile.isNotEmpty) buf.writeln('- 学情摘要：$studentProfile');
    if (classes.isNotEmpty) {
      buf.writeln(
          '- 授课班级：${classes.map((c) => c['name'] ?? '').where((v) => '$v'.isNotEmpty).join('、')}');
    }
    buf.writeln();
    buf.writeln('## 导入大纲原文');
    buf.writeln(syllabusText);
    buf.writeln();
    buf.writeln('## 输出要求');
    buf.writeln('- Markdown 格式，可直接导出为 md/pdf 或转为 PPT/video');
    buf.writeln(
        '- 必须采用高校教师说课 8 大标准模块：课程基本概况、教学目标、教学重难点、学情分析、教法学法、教学过程、考核评价、资源特色与反思');
    buf.writeln('- 必须从大纲中提取课程定位、目标、章节体系、学时、实践/研读/训练/创作任务、考核方式');
    buf.writeln('- 必须写清班级、学生人数、专业/年级结构和学情分析，体现“以学定教”');
    buf.writeln('- 课程术语需适配课程类型，不得把所有课程写成工程实验课');
    buf.writeln('- 每个一级章节下使用 3-6 条要点，便于后续生成 PPT 和视频');
    buf.writeln('- 不得硬编码《移动应用开发》、CKGDT 或其他默认课程内容');

    final result = await _ai.chat(
      [
        {'role': 'user', 'content': buf.toString()}
      ],
      systemPrompt: '你是一位平台化课程说课专家，能从任意学科课程大纲生成规范说课文档。',
    );

    return result.isNotEmpty
        ? result
        : _buildFallbackContent(
            courseName: courseName,
            teacherName: teacherName,
            classes: classes,
            majorInfo: majorInfo,
            studentProfile: studentProfile,
            totalStudents: totalStudents,
          );
  }

  String _buildContentPrompt({
    required String courseName,
    required String teacherName,
    required List<Map<String, dynamic>> syllabus,
    required List<Map<String, dynamic>> classes,
    required String majorInfo,
    required String studentProfile,
    required int totalStudents,
  }) {
    final buf = StringBuffer();
    buf.writeln('## 任务');
    buf.writeln('根据以下课程信息，生成一份完整的教师说课文档（Markdown 格式）。');
    buf.writeln();
    buf.writeln('## 课程信息');
    buf.writeln('- 课程名称：$courseName');
    if (teacherName.isNotEmpty) buf.writeln('- 说课教师：$teacherName');
    if (majorInfo.isNotEmpty) buf.writeln('- 涉及专业：$majorInfo');
    if (totalStudents > 0) buf.writeln('- 学生总数：$totalStudents 人');
    if (studentProfile.isNotEmpty) buf.writeln('- 学情摘要：$studentProfile');
    buf.writeln();

    if (classes.isNotEmpty) {
      buf.writeln('### 授课班级');
      buf.writeln('| 班级 | 人数 |');
      buf.writeln('|------|:---:|');
      for (final c in classes) {
        final name = c['name'] as String? ?? '';
        final count = c['student_count'] as int? ?? 0;
        buf.writeln('| $name | $count |');
      }
      buf.writeln();
    }

    if (syllabus.isNotEmpty) {
      buf.writeln('### 教学大纲');
      buf.writeln('| 章 | 主题 | 学时 |');
      buf.writeln('|:--:|------|:---:|');
      for (final item in syllabus) {
        final ch = item['chapter_number'] ?? item['chapter'] ?? '';
        final title = item['title'] ?? '';
        final hours = item['hours'] ?? 2;
        buf.writeln('| $ch | $title | $hours |');
      }
      buf.writeln();
    }

    buf.writeln('## 输出要求');
    buf.writeln('请生成完整说课文档，严格采用以下 8 大模块（Markdown 格式）：');
    buf.writeln('1. 课程基本概况 — 课程名称、学分学时、开课专业/学期/对象、课程定位、前后续课程、课程属性');
    buf.writeln('2. 教学目标 — 按 OBE 写知识目标、能力目标、素养/思政目标，并说明毕业要求指标点支撑');
    buf.writeln('3. 教学重难点 — 重点、难点及难点成因');
    buf.writeln('4. 学情分析 — 班级、学生人数、专业年级、前置基础、学习特点、分层差异、学习痛点');
    buf.writeln('5. 教法学法 — 教师怎么教、学生怎么学、线上线下混合式安排');
    buf.writeln('6. 教学过程 — 课前、课中、课后，写清做什么、用时、解决哪一重难点、达成哪一目标');
    buf.writeln('7. 课程考核与评价 — 总成绩构成、过程性考核、评价闭环、课程目标/毕业要求对标');
    buf.writeln('8. 教学资源、特色与反思 — 教材资源、课程思政、产教融合、数字化、分层教学、持续改进');
    buf.writeln();
    buf.writeln('要求：');
    buf.writeln('- 语言流畅、专业规范');
    buf.writeln('- 必须基于提供的课程信息，体现该课程的独特性');
    buf.writeln('- 不得套用其他课程的内容模板');
    buf.writeln('- Markdown 格式，表格对齐规范');
    buf.writeln('- 总字数 800-1500 字');

    return buf.toString();
  }

  String _buildFallbackContent({
    required String courseName,
    required String teacherName,
    required List<Map<String, dynamic>> classes,
    required String majorInfo,
    required String studentProfile,
    required int totalStudents,
  }) {
    final buf = StringBuffer();
    buf.writeln('# 《$courseName》说课');
    buf.writeln();
    if (teacherName.isNotEmpty) {
      buf.writeln('**说课教师**：$teacherName');
      buf.writeln();
    }
    buf.writeln('## 一、课程基本概况');
    buf.writeln();
    if (classes.isNotEmpty) {
      buf.writeln('| 班级 | 人数 |');
      buf.writeln('|------|:---:|');
      for (final c in classes) {
        buf.writeln('| ${c['name']} | ${c['student_count'] ?? 0} |');
      }
      buf.writeln('| **合计** | **$totalStudents** |');
      buf.writeln();
    }
    buf.writeln(
        '《$courseName》是面向${majorInfo.isNotEmpty ? majorInfo : "相关专业"}学生的专业课程。');
    buf.writeln('课程注重理论与实践相结合，培养学生的专业素养和创新能力。');
    buf.writeln();
    buf.writeln('## 二、教学目标');
    buf.writeln('- 知识目标：掌握本课程核心概念、方法与规范。');
    buf.writeln('- 能力目标：形成分析问题、解决问题和综合应用能力。');
    buf.writeln('- 素养目标：培养职业规范、协作意识和持续学习能力。');
    buf.writeln();
    buf.writeln('## 三、教学重难点');
    buf.writeln('- 教学重点：课程核心知识体系与关键技能。');
    buf.writeln('- 教学难点：综合应用、迁移实践和真实任务解决。');
    buf.writeln();
    buf.writeln('## 四、学情分析');
    if (studentProfile.isNotEmpty) buf.writeln(studentProfile);
    if (totalStudents > 0) buf.writeln('本课程当前授课对象共 $totalStudents 人。');
    buf.writeln('学生整体具备一定前置基础，但在知识迁移、综合实践和自主规划方面存在差异，需要通过任务驱动和分层支持促进达成。');
    buf.writeln();
    buf.writeln('## 五、教法学法');
    buf.writeln('采用案例教学、任务驱动、课堂讲授与互动讨论相结合的教学方法，学生通过线上预习、小组合作、实践训练和复盘总结完成学习。');
    buf.writeln();
    buf.writeln('## 六、教学过程');
    buf.writeln();
    buf.writeln('课程内容系统全面，涵盖该领域的核心知识与技能，通过循序渐进的教学设计，');
    buf.writeln('帮助学生构建完整的知识体系。');
    buf.writeln();
    buf.writeln(
        '课前推送资料和预习任务，课中围绕重点精讲、案例分析、互动测验和实践操作展开，课后通过分层作业、答疑和项目任务完成巩固提升。');
    buf.writeln();
    buf.writeln('## 七、课程考核与评价');
    buf.writeln();
    buf.writeln('采用过程性评价与终结性评价相结合的方式，全面客观地评价学生学习成效。');
    buf.writeln();
    buf.writeln('## 八、教学资源、特色与反思');
    buf.writeln();
    buf.writeln('课程团队将持续进行教学改革与创新，不断提升课程质量。');
    return buf.toString();
  }

  Future<void> saveContent(String courseName, String content) async {
    final dir = Directory(p.dirname(contentPath(courseName)));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await File(contentPath(courseName)).writeAsString(content);
  }

  Future<String> loadContent(String courseName) async {
    final path = contentPath(courseName);
    if (await File(path).exists()) {
      return await File(path).readAsString();
    }
    return '';
  }

  Future<String> generateScript(String content) async {
    if (content.trim().isEmpty) return '';

    final prompt = '''
根据以下说课文档，生成一份口播配音脚本。

要求：
- 使用"尊敬的各位评委老师，大家好"开头
- 语言口语化、自然流畅，适合 TTS 朗读
- 涵盖高校教师说课 8 大模块：课程基本概况、教学目标、教学重难点、学情分析、教法学法、教学过程、考核评价、资源特色与反思
- 必须包含班级、学生人数和学情特点，体现“以学定教”
- 每个段落 100-200 字，段落之间用空行分隔
- 总字数 1500-2500 字
- 必须基于以下具体内容，不可使用通用模板

说课文档：
$content
''';

    final result = await _ai.chat(
      [
        {'role': 'user', 'content': prompt}
      ],
      systemPrompt: '你是一位教学督导专家，擅长撰写教师说课口播稿。',
    );

    return result;
  }

  Future<String> loadScript(String courseName) async {
    final path = scriptPath(courseName);
    if (await File(path).exists()) {
      return await File(path).readAsString();
    }
    return '';
  }

  Future<void> saveScript(String courseName, String script) async {
    final dir = Directory(p.dirname(scriptPath(courseName)));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await File(scriptPath(courseName)).writeAsString(script);
  }
}
