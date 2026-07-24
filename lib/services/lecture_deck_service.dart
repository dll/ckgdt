import 'dart:io';

import '../core/error_handler.dart';
import 'courseware_service.dart';

class LectureDeckResult {
  final String pptxPath;
  final List<Map<String, dynamic>> slides;

  const LectureDeckResult({required this.pptxPath, required this.slides});
}

/// 说课专业 PPTX 生成服务。
///
/// 主链路必须产出真正的 PPTX，再由 Office/WPS 导出高清页图用于视频合成。
class LectureDeckService {
  final CoursewareService _courseware = CoursewareService();

  Future<LectureDeckResult?> generateDeck({
    required String courseName,
    required String teacherName,
    required String lectureContent,
    required List<Map<String, dynamic>> segments,
    required String outputDir,
  }) async {
    try {
      final slides = buildSlides(
        courseName: courseName,
        teacherName: teacherName,
        lectureContent: lectureContent,
        segments: segments,
      );
      final deckDir = Directory(outputDir)..createSync(recursive: true);
      final pptxPath = await _courseware.generatePptx(
        title: '《$courseName》说课汇报',
        slides: slides,
        chapter: '说课',
        outputDir: deckDir.path,
      );
      if (pptxPath == null || !File(pptxPath).existsSync()) return null;
      return LectureDeckResult(pptxPath: pptxPath, slides: slides);
    } catch (e, st) {
      swallowDebug(e, tag: 'LectureDeckService.generateDeck', stack: st);
      return null;
    }
  }

  List<Map<String, dynamic>> buildSlides({
    required String courseName,
    required String teacherName,
    required String lectureContent,
    required List<Map<String, dynamic>> segments,
  }) {
    final sectionBullets = _extractSections(lectureContent);
    final segmentMap = <String, Map<String, dynamic>>{
      for (final s in segments) '${s['title'] ?? ''}': s,
    };

    Map<String, dynamic> slide(String title, List<String> bullets,
        {String subtitle = '', String notes = ''}) {
      return {
        'title': title,
        'subtitle': subtitle,
        'bullets':
            bullets.map(_clean).where((v) => v.isNotEmpty).take(5).toList(),
        'notes': notes,
      };
    }

    List<String> pick(String key, List<String> fallback) {
      final fromSection = sectionBullets.entries
          .where((e) => e.key.contains(key) || key.contains(e.key))
          .expand((e) => e.value)
          .map(_clean)
          .where((v) => v.isNotEmpty)
          .take(5)
          .toList();
      if (fromSection.length >= 2) return fromSection;
      final fromSegment = segmentMap.entries
          .where((e) => e.key.contains(key) || key.contains(e.key))
          .expand((e) => (e.value['bullets'] as List?) ?? const [])
          .map((v) => _clean('$v'))
          .where((v) => v.isNotEmpty)
          .take(5)
          .toList();
      if (fromSegment.length >= 2) return fromSegment;
      return fallback;
    }

    final coverNote =
        segments.isNotEmpty ? '${segments.first['narration'] ?? ''}' : '';
    final closingNote =
        segments.isNotEmpty ? '${segments.last['narration'] ?? ''}' : '';

    return [
      slide(
        '《$courseName》说课汇报',
        [
          if (teacherName.isNotEmpty) '说课教师：$teacherName',
          '面向评委同行说明教学设计逻辑',
          '围绕目标、学情、过程、评价闭环展开',
        ],
        subtitle: '高校教师说课 · OBE 产出导向',
        notes: coverNote,
      ),
      slide(
          '一、课程基本概况',
          pick('课程基本概况', [
            '说明课程名称、学分学时和授课对象',
            '明确课程定位与人才培养衔接',
            '交代课程属性和线上线下安排',
          ])),
      slide(
          '二、教学目标',
          pick('教学目标', [
            '知识目标支撑核心概念和方法掌握',
            '能力目标聚焦分析实践和协作应用',
            '素养目标融入职业规范与课程思政',
            '目标对应毕业要求指标点',
          ])),
      slide(
          '三、教学重难点',
          pick('教学重难点', [
            '重点聚焦课程目标达成的关键内容',
            '难点来自抽象理解和综合迁移应用',
            '通过案例、任务和可视化逐步突破',
          ])),
      slide(
          '四、学情分析',
          pick('学情分析', [
            '结合班级人数和专业年级识别基础',
            '分析学生学习特点与分层差异',
            '围绕学习痛点设计支持策略',
            '体现以学定教和因材施教',
          ])),
      slide(
          '五、教法学法',
          pick('教法学法', [
            '教师采用讲授、案例、任务驱动组合',
            '学生开展预习、协作、训练和复盘',
            '形成课前课中课后混合式学习链路',
          ])),
      slide(
          '六、教学过程',
          pick('教学过程', [
            '课前推送资源并完成学情摸底',
            '课中导入、新知、互动、练习递进',
            '课后分层作业和实践任务巩固',
            '每个环节对标目标和重难点',
          ])),
      slide(
          '七、课程考核与评价',
          pick('课程考核与评价', [
            '过程性评价与终结性评价结合',
            '课堂表现、作业、实践和期末多元构成',
            '考核内容对标课程目标和毕业要求',
            '达成度数据反推教学持续改进',
          ])),
      slide(
          '八、资源特色与反思',
          pick('教学资源、特色与反思', [
            '教材、平台、题库和案例资源协同支撑',
            '课程思政自然融入知识与任务',
            '数字化工具支持证据采集和反馈',
            '基于教学问题持续优化设计',
          ])),
      slide(
          '感谢聆听',
          [
            '完整呈现目标、内容、方法、评价闭环',
            '欢迎各位评委老师批评指正',
          ],
          notes: closingNote),
    ];
  }

  Map<String, List<String>> _extractSections(String content) {
    final result = <String, List<String>>{};
    String current = '';
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('## ')) {
        current = _clean(line.replaceFirst(RegExp(r'^##+\s*'), ''));
        result.putIfAbsent(current, () => []);
        continue;
      }
      if (current.isEmpty) continue;
      if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          RegExp(r'^\d+[.、]').hasMatch(line)) {
        final text =
            _clean(line.replaceFirst(RegExp(r'^([-*]|\d+[.、])\s*'), ''));
        if (text.isNotEmpty) result[current]!.add(text);
      }
    }
    return result;
  }

  String _clean(String input) {
    var text = input.trim();
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'^#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'^[-*+]\s+'), '');
    text = text.replaceAll(RegExp(r'^\d+[.、)]\s*'), '');
    text = text.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'[*_~>|#`]+'), '');
    text = text.replaceAll(RegExp(r'\s*\|\s*'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 42) text = '${text.substring(0, 42)}...';
    return text;
  }
}
