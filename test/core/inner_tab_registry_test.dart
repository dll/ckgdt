import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/constants/inner_tab_registry.dart';
import 'package:knowledge_graph_app/core/constants/archive_periods.dart';

/// 守护内层 Tab 单一来源 [kInnerTabRegistry] 与各页声明的一致性。
///
/// 语音导航的"父页面+内层 Tab"指令依赖 VoiceAgent prompt 里的 tab 清单，
/// 而该清单从 [kInnerTabRegistry] 生成。各页面 `innerTabLabels()` 若新增/改名
/// tab 却忘了同步注册表，语音就点不开 —— 历史上 archive 整段缺失正是此故。
///
/// 本测试把"各页实际声明的 labels"复刻一份（与页面源码对齐），逐一断言
/// 它们都登记在注册表中。任何一方漂移，CI 立即红，而非线上语音静默失灵。
void main() {
  // 各 page 的内层 tab 标签全集（教师 + 学生角色并集），必须与页面
  // InnerTabRequestMixin.innerTabLabels() 的两支并集逐字对齐。
  final pageDeclaredLabels = <String, List<String>>{
    'assessment': [
      '分组',
      '项目',
      '贡献',
      '材料',
      '答辩',
      '报告',
      '成绩',
      'AI批阅',
    ],
    'works': ['我的作品', '成绩', '作品展示', '作品记录', '排行榜', 'AI批阅'],
    'achievement': [
      '达成度概览',
      '成绩管理',
      '平时达成',
      '实验达成',
      '考核达成',
      '计算过程',
      '报告生成',
      '持续改进',
    ],
    'classroom': ['在线状态', '课堂签到', '课堂互动', '课堂工具', '课堂提问'],
    'lab': [
      '任务列表',
      '我的提交',
      '成绩',
      '提交管理',
      '实验报告',
      '实验材料',
      '任务管理',
      'AI批阅',
      '仓库报表',
    ],
    'learning': ['视频', 'PPT', 'PDF', '测验', '助手', '成绩', '平时成绩'],
    'archive': archivePeriodLabels,
  };

  group('kInnerTabRegistry SSOT', () {
    test('每个使用语音内层导航的页面都已登记', () {
      for (final pageKey in pageDeclaredLabels.keys) {
        expect(
          kInnerTabRegistry.containsKey(pageKey),
          isTrue,
          reason: 'pageKey "$pageKey" 未登记到 kInnerTabRegistry',
        );
      }
    });

    test('各页声明的 tab labels 全部登记在注册表（无漂移）', () {
      pageDeclaredLabels.forEach((pageKey, labels) {
        final unregistered = unregisteredInnerTabs(pageKey, labels);
        expect(
          unregistered,
          isEmpty,
          reason: '页面 "$pageKey" 的 tab $unregistered 未登记到 kInnerTabRegistry',
        );
      });
    });

    test('注册表中的 tab labels 均存在于页面声明（无反向漂移）', () {
      pageDeclaredLabels.forEach((pageKey, labels) {
        final declared = labels.toSet();
        final extraRegistered = (kInnerTabRegistry[pageKey] ?? const [])
            .where((label) => !declared.contains(label))
            .toList();
        expect(
          extraRegistered,
          isEmpty,
          reason: 'kInnerTabRegistry "$pageKey" 的 tab $extraRegistered 未在页面声明',
        );
      });
    });

    test('每个登记的 pageKey 都有对应朗读名 kInnerTabPageLabels', () {
      for (final pageKey in kInnerTabRegistry.keys) {
        expect(
          kInnerTabPageLabels.containsKey(pageKey),
          isTrue,
          reason: 'pageKey "$pageKey" 缺少 kInnerTabPageLabels 朗读名',
        );
      }
    });

    test('archive 页内层 tab 已纳入注册表（历史漂移回归守护）', () {
      // archive 曾整段缺失于 VoiceAgent prompt，导致语音点不开归档子页。
      final unregistered =
          unregisteredInnerTabs('archive', archivePeriodLabels);
      expect(unregistered, isEmpty);
    });

    test('unregisteredInnerTabs 对未登记 page 返回全部 labels', () {
      final result = unregisteredInnerTabs('__nonexistent__', ['x', 'y']);
      expect(result, ['x', 'y']);
    });
  });
}
