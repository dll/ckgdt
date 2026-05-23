import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/core/design/noir_tokens.dart';

/// noir 设计层的常量是 88 个页面共享的视觉契约 —— 改这些值会全局视觉漂移。
/// test 锁定这些常量与色板，未来重构时若有人手抖改了，CI 会炸。
void main() {
  group('NoirTokens 颜色板', () {
    test('ink / paper / accent 是固定 ARGB（视觉契约）', () {
      expect(NoirTokens.ink.toARGB32(), 0xFF0A0E1A);
      expect(NoirTokens.paper.toARGB32(), 0xFFF7F4EE);
      expect(NoirTokens.accent.toARGB32(), 0xFFF4B942);
    });

    test('inkAlpha 返回正确透明度', () {
      final c = NoirTokens.inkAlpha(0.5);
      expect(c.a, closeTo(0.5, 0.01));
      // 红绿蓝通道应保持
      expect(c.r, NoirTokens.ink.r);
    });
  });

  group('NoirTokens 字距与字号', () {
    test('caps 字距 4.0 — caps 编辑感的关键', () {
      expect(NoirTokens.letterCaps, 4.0);
    });

    test('radius 是极小圆角 2.0 — 编辑感的核心特征', () {
      expect(NoirTokens.radius, 2.0);
    });

    test('字号阶梯单调递增', () {
      expect(NoirTokens.fsSerial < NoirTokens.fsCaption, isTrue);
      expect(NoirTokens.fsCaption < NoirTokens.fsBody, isTrue);
      expect(NoirTokens.fsBody < NoirTokens.fsTitle, isTrue);
      expect(NoirTokens.fsTitle < NoirTokens.fsSection, isTrue);
      expect(NoirTokens.fsSection < NoirTokens.fsHero, isTrue);
    });

    test('间距阶梯单调递增', () {
      expect(NoirTokens.spaceXs < NoirTokens.spaceSm, isTrue);
      expect(NoirTokens.spaceSm < NoirTokens.spaceMd, isTrue);
      expect(NoirTokens.spaceMd < NoirTokens.spaceLg, isTrue);
      expect(NoirTokens.spaceLg < NoirTokens.spaceXl, isTrue);
      expect(NoirTokens.spaceXl < NoirTokens.spaceXxl, isTrue);
    });
  });

  group('NoirTokens TextStyle 工厂', () {
    test('caps() 默认色为 accent 琥珀', () {
      final s = NoirTokens.caps();
      expect(s.color?.toARGB32(), NoirTokens.accent.toARGB32());
      expect(s.letterSpacing, NoirTokens.letterCaps);
      expect(s.fontWeight, FontWeight.w700);
    });

    test('section() 默认色为 ink', () {
      final s = NoirTokens.section();
      expect(s.color?.toARGB32(), NoirTokens.ink.toARGB32());
      expect(s.fontSize, NoirTokens.fsSection);
    });
  });
}
