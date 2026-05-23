import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/constants/chapter_sorter.dart';

/// 章节排序是教学场景的关键 — Unicode 字典序排出来 "三 < 二 < 五 < 六 < 四 < 一"
/// 直接展示给学生会很乱。这个排序器修正这个问题。
void main() {
  group('ChapterSorter.compare', () {
    test('一到六的中文章节按数值排序', () {
      final list = [
        '第三章 混合开发',
        '第一章 全景',
        '第六章 综合实践',
        '第二章 原生',
        '第五章 鸿蒙',
        '第四章 小程序',
      ];
      list.sort(ChapterSorter.compare);
      expect(list, [
        '第一章 全景',
        '第二章 原生',
        '第三章 混合开发',
        '第四章 小程序',
        '第五章 鸿蒙',
        '第六章 综合实践',
      ]);
    });

    test('章号相同时按末尾子序号排序', () {
      final list = ['第一章 题目3', '第一章 题目1', '第一章 题目2'];
      list.sort(ChapterSorter.compare);
      expect(list, ['第一章 题目1', '第一章 题目2', '第一章 题目3']);
    });

    test('未识别章号被放到最后（999）', () {
      final list = ['未知章', '第二章 X', '第一章 Y'];
      list.sort(ChapterSorter.compare);
      expect(list.first, '第一章 Y');
      expect(list.last, '未知章');
    });

    test('十一、十二等大于十的章号正确处理', () {
      final list = ['第十二章 后', '第十章 中', '第一章 前'];
      list.sort(ChapterSorter.compare);
      expect(list, ['第一章 前', '第十章 中', '第十二章 后']);
    });
  });

  group('ChapterSorter.sortByChapter', () {
    test('对 Map 列表按 chapter 字段就地排序', () {
      final list = [
        {'chapter': '第三章', 'count': 3},
        {'chapter': '第一章', 'count': 1},
        {'chapter': '第二章', 'count': 2},
      ];
      ChapterSorter.sortByChapter(list);
      expect(list[0]['count'], 1);
      expect(list[1]['count'], 2);
      expect(list[2]['count'], 3);
    });

    test('chapter 字段缺失时不抛错', () {
      final list = [
        {'count': 1},
        {'chapter': '第一章', 'count': 2},
      ];
      expect(() => ChapterSorter.sortByChapter(list), returnsNormally);
    });
  });
}
