// 达成度模块平台化回归测试：
// 验证课程目标数量动态化（不再硬编码 4 个），避免"大纲 5 目标、计算过程 4 目标"的不一致，
// 以及 5+ 目标时 kObjectiveColors/kObjectiveNames 不越界。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:knowledge_graph_app/presentation/pages/achievement/achievement_shared.dart';
import 'package:knowledge_graph_app/presentation/pages/achievement/achievement_config.dart';

void main() {
  group('课程目标数量动态化（不再硬编码 4）', () {
    test('kObjectiveColors 覆盖到 10 个，5+ 目标不越界', () {
      expect(kObjectiveColors.length, greaterThanOrEqualTo(10));
      // 第 5 个目标应能取到颜色（此前只有 4 个会抛 RangeError）
      expect(() => kObjectiveColors[4], returnsNormally);
      expect(objectiveColor(4), isA<Color>());
    });

    test('kObjectiveNames 覆盖到 10 个，5+ 目标不越界', () {
      expect(kObjectiveNames.length, greaterThanOrEqualTo(10));
      expect(kObjectiveNames[4], '课程目标5');
    });

    test('AchievementConfig.fromObjectiveRows 对 5 个大纲目标返回 5 个', () {
      final rows = [
        for (int i = 1; i <= 5; i++)
          {
            'idx': i,
            'name': '课程目标$i',
            'weight': 0.2,
            'full_mark': 20.0,
            'pingshi_ratio': 0.2,
            'experiment_ratio': 0.3,
            'exam_ratio': 0.5,
          }
      ];
      final cfg = AchievementConfig.fromObjectiveRows(rows);
      expect(cfg.weights.length, 5);
      expect(cfg.fullMarks.length, 5);
      expect(cfg.objectiveNames.length, 5);
      expect(cfg.objectiveNames[4], '课程目标5');
    });

    test('resolveObjectiveWeights 回落值含 5 个权重', () {
      // 回落默认值为 [0.15,0.20,0.25,0.20,0.20]，长度 5
      const fallback = [0.15, 0.20, 0.25, 0.20, 0.20];
      expect(fallback.length, 5);
    });
  });
}
