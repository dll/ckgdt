import 'dart:io';
import 'package:path/path.dart' as p;
import 'ai_service.dart';

class LectureContentService {
  final AiService _ai = AiService();

  static String contentPath(String courseName) =>
      'data/$courseName/说课/说课.md';

  static String scriptPath(String courseName) =>
      'data/$courseName/说课/配音脚本.txt';

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
    int totalStudents = 0,
  }) async {
    final prompt = _buildContentPrompt(
      courseName: courseName,
      teacherName: teacherName,
      syllabus: syllabus,
      classes: classes,
      majorInfo: majorInfo,
      totalStudents: totalStudents,
    );

    final result = await _ai.chat(
      [{'role': 'user', 'content': prompt}],
      systemPrompt: '你是一位资深的教学督导和课程设计专家。善于根据课程信息生成规范、完整的说课文档。'
          '说课文档必须基于提供的课程信息生成，体现该课程的独特性，不得使用通用模板或套话。'
          '使用专业、规范的中文，Markdown 格式。',
    );

    return result.isNotEmpty ? result : _buildFallbackContent(
      courseName: courseName,
      teacherName: teacherName,
      classes: classes,
      majorInfo: majorInfo,
      totalStudents: totalStudents,
    );
  }

  String _buildContentPrompt({
    required String courseName,
    required String teacherName,
    required List<Map<String, dynamic>> syllabus,
    required List<Map<String, dynamic>> classes,
    required String majorInfo,
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
    buf.writeln();

    if (classes.isNotEmpty) {
      buf.writeln('### 授课班级');
      buf.writeln('| 班级 | 人数 |');
      buf.writeln('|------|:---:|');
      for (final c in classes) {
        final name = c['name'] as String? ?? '';
        final count = c['student_count'] as int? ?? 0;
        final major = c['major'] as String? ?? majorInfo;
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
    buf.writeln('请生成完整说课文档，包含以下章节（Markdown 格式）：');
    buf.writeln('1. 课程定位 — 课程性质、目标、面向对象、学时学分、考核方式');
    buf.writeln('2. 教学内容 — 章节体系（基于提供的教学大纲生成具体的课程内容描述）');
    buf.writeln('3. 教学方法与手段 — 适合该课程特点的教学方法');
    buf.writeln('4. 实践环节 — 实验/实践项目设计（根据课程类型决定：工程课→实验项目，文学课→研读实践，体育课→训练实践，艺术课→创作实践）');
    buf.writeln('5. 考核评价 — 考核方式、评价量规');
    buf.writeln('6. 教学改革与持续改进');
    buf.writeln('7. 教材与参考资源（使用通用书名，不要写具体不存在的书）');
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
    required int totalStudents,
  }) {
    final buf = StringBuffer();
    buf.writeln('# 《$courseName》说课');
    buf.writeln();
    if (teacherName.isNotEmpty) {
      buf.writeln('**说课教师**：$teacherName');
      buf.writeln();
    }
    if (classes.isNotEmpty) {
      buf.writeln('## 授课班级');
      buf.writeln();
      buf.writeln('| 班级 | 人数 |');
      buf.writeln('|------|:---:|');
      for (final c in classes) {
        buf.writeln('| ${c['name']} | ${c['student_count'] ?? 0} |');
      }
      buf.writeln('| **合计** | **$totalStudents** |');
      buf.writeln();
    }
    buf.writeln('## 课程定位');
    buf.writeln();
    buf.writeln('《$courseName》是面向${majorInfo.isNotEmpty ? majorInfo : "相关专业"}学生的专业课程。');
    buf.writeln('课程注重理论与实践相结合，培养学生的专业素养和创新能力。');
    buf.writeln();
    buf.writeln('## 教学内容');
    buf.writeln();
    buf.writeln('课程内容系统全面，涵盖该领域的核心知识与技能，通过循序渐进的教学设计，');
    buf.writeln('帮助学生构建完整的知识体系。');
    buf.writeln();
    buf.writeln('## 教学方法');
    buf.writeln();
    buf.writeln('采用案例教学、项目驱动、课堂讲授与互动讨论相结合的教学方法，');
    buf.writeln('充分利用数字化教学平台提升教学效果。');
    buf.writeln();
    buf.writeln('## 实践环节');
    buf.writeln();
    buf.writeln('课程设置多个实践项目，让学生在实际操作中巩固所学知识，');
    buf.writeln('培养解决实际问题的能力。');
    buf.writeln();
    buf.writeln('## 考核评价');
    buf.writeln();
    buf.writeln('采用过程性评价与终结性评价相结合的方式，全面客观地评价学生学习成效。');
    buf.writeln();
    buf.writeln('## 教学改革');
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
- 涵盖：开场介绍、课程定位、教学内容、教学方法、实践环节、考核评价、教学改革、结语
- 每个段落 100-200 字，段落之间用空行分隔
- 总字数 1500-2500 字
- 必须基于以下具体内容，不可使用通用模板

说课文档：
$content
''';

    final result = await _ai.chat(
      [{'role': 'user', 'content': prompt}],
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
