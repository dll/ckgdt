import 'package:flutter/material.dart';

/// 章节映射工具 — 全局统一的章节标识转换
class ChapterHelper {
  ChapterHelper._();

  /// 章节名称映射
  static const Map<int, String> chapterNames = {
    1: '移动应用开发技术体系全景',
    2: 'Android与iOS原生开发基础',
    3: 'Flutter等混合开发技术',
    4: '微信小程序开发流程',
    5: 'HarmonyOS多端应用开发',
    6: '综合开发实践',
  };

  /// 章节简称
  static const Map<int, String> chapterShortNames = {
    1: '技术体系',
    2: 'Android/iOS',
    3: 'Flutter混合开发',
    4: '微信小程序',
    5: 'HarmonyOS',
    6: '综合实践',
  };

  /// 章节关联的技术Logo文字标识（用于图谱蒙版水印渲染）
  static const Map<int, List<String>> chapterLogos = {
    1: ['Mobile', 'App', 'PWA', 'Web'],
    2: ['Android', 'iOS', 'Kotlin', 'Swift'],
    3: ['Flutter', 'Dart', 'RN', 'MAUI', 'C#'],
    4: ['WeChat', '小程序', 'WXML', 'Taro'],
    5: ['鸿蒙', 'ArkTS', 'ArkUI', 'DevEco'],
    6: ['MVVM', 'SQLite', 'Git', 'CI/CD'],
  };

  /// 章节对应的 Material 图标
  static const Map<int, IconData> chapterIcons = {
    1: Icons.phone_android,
    2: Icons.android,
    3: Icons.flutter_dash,
    4: Icons.chat,
    5: Icons.devices_other,
    6: Icons.integration_instructions,
  };

  /// 章节主题色
  static const Map<int, Color> chapterColors = {
    1: Color(0xFF667eea),
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
    if (directInt != null && directInt >= 1 && directInt <= 6) return directInt;

    final arabicMatch = RegExp(r'第(\d+)章').firstMatch(input);
    if (arabicMatch != null) return int.tryParse(arabicMatch.group(1)!);

    const cnDigits = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6};
    final cnMatch = RegExp(r'第([一二三四五六])章').firstMatch(input);
    if (cnMatch != null) return cnDigits[cnMatch.group(1)];

    final chMatch = RegExp(r'ch(\d+)', caseSensitive: false).firstMatch(input);
    if (chMatch != null) return int.tryParse(chMatch.group(1)!);

    final lower = input.toLowerCase();
    if (lower.contains('flutter') || lower.contains('react native') ||
        lower.contains('混合')) return 3;
    if (lower.contains('android') || lower.contains('ios') ||
        lower.contains('原生')) return 2;
    if (lower.contains('harmonyos') || lower.contains('鸿蒙')) return 5;
    if (lower.contains('小程序') || lower.contains('微信')) return 4;
    if (lower.contains('综合') || lower.contains('实践')) return 6;
    if (lower.contains('体系') || lower.contains('全景')) return 1;

    return null;
  }

  /// 构建用于 resource_files 查询的 LIKE 模式
  static String resourceQueryPattern(int chapter) => '%第$chapter章%';

  /// 获取所有章节号列表
  static List<int> get allChapters => [1, 2, 3, 4, 5, 6];
}
