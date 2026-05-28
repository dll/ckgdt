import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/review_result.dart';

void main() {
  group('ReviewResult.toJson / fromJson roundtrip', () {
    test('empty review', () {
      final r = ReviewResult(overall: 'pending');
      final back = ReviewResult.fromJson(r.toJson());
      expect(back.overall, 'pending');
      expect(back.errors, isEmpty);
      expect(back.warnings, isEmpty);
      expect(back.passed, isEmpty);
      expect(back.confidence, 0.0);
    });

    test('full review with all sections', () {
      final r = ReviewResult(
        overall: 'needs_revision',
        confidence: 0.92,
        latencyMs: 1234,
        errors: [
          Finding(
            key: 'syllabus.hours_total',
            dimension: '学时加和',
            level: '❌ 错误',
            evidence: '24+22 != 48',
            suggestion: '修正某章学时',
            layer: 'numerical',
          ),
        ],
        warnings: [
          Finding(
            key: 'syllabus.思政_章4',
            dimension: '思政元素',
            level: '⚠️ 建议',
            evidence: '与本章主题不符',
            suggestion: '改写',
          ),
        ],
        passed: [
          Finding(
            key: 'syllabus.OBE',
            dimension: 'OBE 框架',
            level: '✅ 通过',
            evidence: '4 条目标 → 4 条毕业要求',
            suggestion: '保持',
          ),
        ],
        ignoredKeys: ['syllabus.cosmetic_warning'],
      );

      final back = ReviewResult.fromJson(r.toJson());
      expect(back.overall, 'needs_revision');
      expect(back.confidence, 0.92);
      expect(back.latencyMs, 1234);
      expect(back.errors, hasLength(1));
      expect(back.errors.first.dimension, '学时加和');
      expect(back.errors.first.layer, 'numerical');
      expect(back.warnings, hasLength(1));
      expect(back.passed, hasLength(1));
      expect(back.ignoredKeys, ['syllabus.cosmetic_warning']);
    });
  });

  group('ReviewResult.fromJson resilience', () {
    test('empty string returns pending', () {
      final r = ReviewResult.fromJson('');
      expect(r.overall, 'pending');
    });

    test('garbage string returns pending without throwing', () {
      final r = ReviewResult.fromJson('not json at all');
      expect(r.overall, 'pending');
    });
  });

  group('ReviewResult flags', () {
    test('isApproved requires both overall=approved AND no errors', () {
      // case 1: approved + no errors → true
      final r1 = ReviewResult(overall: 'approved');
      expect(r1.isApproved, isTrue);

      // case 2: approved but has errors → false (defensive)
      final r2 = ReviewResult(
        overall: 'approved',
        errors: [
          Finding(
              key: 'k',
              dimension: 'd',
              level: '❌ 错误',
              evidence: 'e',
              suggestion: 's'),
        ],
      );
      expect(r2.isApproved, isFalse);

      // case 3: needs_revision → false
      final r3 = ReviewResult(overall: 'needs_revision');
      expect(r3.isApproved, isFalse);
    });

    test('hasBlockers reflects errors only', () {
      final r1 = ReviewResult(overall: 'needs_revision', warnings: [
        Finding(
            key: 'k',
            dimension: 'd',
            level: '⚠️ 建议',
            evidence: 'e',
            suggestion: 's'),
      ]);
      expect(r1.hasBlockers, isFalse);

      final r2 = ReviewResult(overall: 'needs_revision', errors: [
        Finding(
            key: 'k',
            dimension: 'd',
            level: '❌ 错误',
            evidence: 'e',
            suggestion: 's'),
      ]);
      expect(r2.hasBlockers, isTrue);
    });
  });

  group('ReviewResult.toMarkdown', () {
    test('renders all sections with table headers', () {
      final r = ReviewResult(
        overall: 'needs_revision',
        confidence: 0.85,
        latencyMs: 999,
        errors: [
          Finding(
              key: 'k1',
              dimension: '学时',
              level: '❌ 错误',
              evidence: 'e1',
              suggestion: 's1',
              layer: 'numerical'),
        ],
        warnings: [
          Finding(
              key: 'k2',
              dimension: '思政',
              level: '⚠️ 建议',
              evidence: 'e2',
              suggestion: 's2'),
        ],
      );
      final md = r.toMarkdown(title: '测试审核表');

      expect(md, contains('# 测试审核表'));
      expect(md, contains('⚠️ 需修订'));
      expect(md, contains('置信度**：85%'));
      expect(md, contains('999ms'));
      expect(md, contains('## ❌ 必须修改（1 项）'));
      expect(md, contains('## ⚠️ 建议改进（1 项）'));
      expect(md, contains('| 维度 | 等级 | 证据 | 修订建议 |'));
      expect(md, contains('学时'));
      expect(md, contains('思政'));
    });

    test('escapes pipe and newline in cell text', () {
      final r = ReviewResult(
        overall: 'needs_revision',
        errors: [
          Finding(
            key: 'k',
            dimension: '维度|含管道',
            level: '❌ 错误',
            evidence: '换行\n会破坏表格',
            suggestion: 'OK',
          ),
        ],
      );
      final md = r.toMarkdown();
      // 管道符必须转义，否则破坏 markdown 表格
      expect(md, contains('维度\\|含管道'));
      // 换行变空格
      expect(md, contains('换行 会破坏表格'));
      // 表格行不应包含原始换行
      final rowLine = md
          .split('\n')
          .firstWhere((l) => l.contains('维度\\|含管道'), orElse: () => '');
      expect(rowLine.contains('\n'), isFalse);
    });
  });

  group('Finding roundtrip', () {
    test('preserves all fields', () {
      final f = Finding(
        key: 'syllabus.hours',
        dimension: '学时加和',
        level: '❌ 错误',
        evidence: '24+22=46≠48',
        suggestion: '修正',
        layer: 'numerical',
      );
      final back = Finding.fromMap(f.toMap());
      expect(back.key, f.key);
      expect(back.dimension, f.dimension);
      expect(back.level, f.level);
      expect(back.evidence, f.evidence);
      expect(back.suggestion, f.suggestion);
      expect(back.layer, f.layer);
    });

    test('default layer is structural', () {
      final f = Finding.fromMap({
        'key': 'k',
        'dimension': 'd',
        'level': '✅ 通过',
        'evidence': 'e',
        'suggestion': 's',
      });
      expect(f.layer, 'structural');
    });
  });
}
