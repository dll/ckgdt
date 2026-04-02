/// 章节排序工具
///
/// 中文章节名（如"第一章 xxx1"）按 Unicode 字典序排列时顺序错误
/// （三 < 二 < 五 < 六 < 四 < 一），需要提取章节编号进行数值排序。
class ChapterSorter {
  ChapterSorter._();

  /// 中文数字 → 阿拉伯数字映射
  static const _cnDigits = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    '十一': 11, '十二': 12, '十三': 13, '十四': 14, '十五': 15,
    '十六': 16, '十七': 17, '十八': 18, '十九': 19, '二十': 20,
  };

  /// 从章节名中提取排序键：(章号, 子序号)
  ///
  /// 例如：
  /// - "第一章 移动应用开发技术体系1" → (1, 1)
  /// - "第三章 混合开发技术2"        → (3, 2)
  /// - "第五章 华为多端应用开发3"     → (5, 3)
  static (int, int) _extractKey(String chapter) {
    // 匹配 "第X章" 中的 X（中文数字）
    final chapterMatch = RegExp(r'第(.{1,2})章').firstMatch(chapter);
    int chapterNum = 999;
    if (chapterMatch != null) {
      final cnNum = chapterMatch.group(1)!;
      chapterNum = _cnDigits[cnNum] ?? 999;
    }

    // 匹配末尾的阿拉伯数字作为子序号
    final subMatch = RegExp(r'(\d+)\s*$').firstMatch(chapter);
    int subNum = 0;
    if (subMatch != null) {
      subNum = int.tryParse(subMatch.group(1)!) ?? 0;
    }

    return (chapterNum, subNum);
  }

  /// 比较两个章节名的排序顺序
  static int compare(String a, String b) {
    final keyA = _extractKey(a);
    final keyB = _extractKey(b);
    final cmp = keyA.$1.compareTo(keyB.$1);
    if (cmp != 0) return cmp;
    return keyA.$2.compareTo(keyB.$2);
  }

  /// 对含有 'chapter' 字段的 Map 列表进行排序（就地排序）
  static void sortByChapter(List<Map<String, dynamic>> list,
      {String field = 'chapter'}) {
    list.sort((a, b) {
      final ca = a[field] as String? ?? '';
      final cb = b[field] as String? ?? '';
      return compare(ca, cb);
    });
  }
}
