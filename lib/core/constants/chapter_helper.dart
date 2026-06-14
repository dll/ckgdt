import 'package:flutter/material.dart';

/// 章节映射工具 — 全局统一的章节标识转换
class ChapterHelper {
  ChapterHelper._();

  /// 章节名称映射
  static const Map<int, String> chapterNames = {
    1: '课程导论与知识体系',
    2: '基础概念与核心原理',
    3: '方法技术与工具支撑',
    4: '分析设计与问题求解',
    5: '实践应用与综合训练',
    6: '评价改进与课程总结',
  };

  /// 章节简称
  static const Map<int, String> chapterShortNames = {
    1: '课程导论',
    2: '基础概念',
    3: '方法工具',
    4: '分析设计',
    5: '实践应用',
    6: '课程总结',
  };

  /// 章节关联的技术Logo文字标识（用于图谱蒙版水印渲染）
  static const Map<int, List<String>> chapterLogos = {
    1: ['Course', 'Map', 'Intro'],
    2: ['Concept', 'Theory', 'Core'],
    3: ['Method', 'Tool', 'Model'],
    4: ['Analysis', 'Design', 'Solve'],
    5: ['Practice', 'Case', 'Project'],
    6: ['Review', 'OBE', 'CQI'],
  };

  /// 章节对应的 Material 图标
  static const Map<int, IconData> chapterIcons = {
    1: Icons.school_outlined,
    2: Icons.psychology_alt_outlined,
    3: Icons.construction_outlined,
    4: Icons.schema_outlined,
    5: Icons.science_outlined,
    6: Icons.task_alt_outlined,
  };

  /// 章节主题色
  static const Map<int, Color> chapterColors = {
    1: Color(0xFF1677FF),
    2: Color(0xFF4CAF50),
    3: Color(0xFF027DFD),
    4: Color(0xFF07C160),
    5: Color(0xFFCE0E2D),
    6: Color(0xFFFF9800),
  };

  /// int → 完整章节标题 "第X章 XXX"
  static String fullTitle(int chapter) {
    final name = chapterNames[chapter] ?? '未知';
    return '第$chapter章 $name';
  }

  /// int → 短标题 "第X章"
  static String shortTitle(int chapter) => '第$chapter章';

  /// 从各种格式的章节字符串中提取章节号(int)
  static int? parseChapter(String? input) {
    if (input == null || input.isEmpty) return null;

    final directInt = int.tryParse(input.trim());
    if (directInt != null && directInt >= 1 && directInt <= 99)
      return directInt;

    final arabicMatch = RegExp(r'第(\d+)章').firstMatch(input);
    if (arabicMatch != null) return int.tryParse(arabicMatch.group(1)!);

    final cnMatch = RegExp(r'第([一二三四五六七八九十]+)章').firstMatch(input);
    if (cnMatch != null) return _parseChineseChapter(cnMatch.group(1)!);

    final chMatch = RegExp(r'ch(\d+)', caseSensitive: false).firstMatch(input);
    if (chMatch != null) return int.tryParse(chMatch.group(1)!);

    final lower = input.toLowerCase();
    if (lower.contains('flutter') ||
        lower.contains('react native') ||
        lower.contains('混合')) return 3;
    if (lower.contains('android') ||
        lower.contains('ios') ||
        lower.contains('原生')) return 2;
    if (lower.contains('harmonyos') || lower.contains('鸿蒙')) return 5;
    if (lower.contains('小程序') || lower.contains('微信')) return 4;
    if (lower.contains('综合') || lower.contains('实践')) return 6;
    if (lower.contains('体系') || lower.contains('全景')) return 1;

    return null;
  }

  static int? _parseChineseChapter(String value) {
    const digits = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) {
      return 10 + (digits[value.substring(1)] ?? 0);
    }
    if (value.endsWith('十')) {
      return (digits[value.substring(0, value.length - 1)] ?? 0) * 10;
    }
    final tenIndex = value.indexOf('十');
    if (tenIndex > 0) {
      final high = digits[value.substring(0, tenIndex)] ?? 0;
      final low = digits[value.substring(tenIndex + 1)] ?? 0;
      return high * 10 + low;
    }
    return digits[value];
  }

  /// 构建用于 resource_files 查询的 LIKE 模式
  static String resourceQueryPattern(int chapter) => '%第$chapter章%';

  /// 获取所有章节号列表
  static List<int> get allChapters => List.generate(12, (i) => i + 1);
}
