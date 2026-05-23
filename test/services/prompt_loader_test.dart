import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/agent/prompt_loader.dart';

void main() {
  setUp(() {
    PromptLoader.invalidate();
  });

  group('PromptLoader', () {
    test('未匹配的 agentId 返回 null', () async {
      final result = await PromptLoader.load('definitely_not_an_agent_id_xyz');
      expect(result, isNull);
    });

    test('null 结果会被缓存（避免反复尝试）', () async {
      await PromptLoader.load('not_exist_a');
      expect(PromptLoader.cacheSize, 1);
      await PromptLoader.load('not_exist_a');
      expect(PromptLoader.cacheSize, 1, reason: '同一个 id 二次访问不应增加缓存');
    });

    test('多个不存在的 agentId 各自缓存', () async {
      await PromptLoader.load('not_exist_a');
      await PromptLoader.load('not_exist_b');
      expect(PromptLoader.cacheSize, 2);
    });

    test('invalidate() 清空全部', () async {
      await PromptLoader.load('id1');
      await PromptLoader.load('id2');
      expect(PromptLoader.cacheSize, 2);
      PromptLoader.invalidate();
      expect(PromptLoader.cacheSize, 0);
    });

    test('invalidate(id) 仅清单条', () async {
      await PromptLoader.load('id1');
      await PromptLoader.load('id2');
      PromptLoader.invalidate('id1');
      expect(PromptLoader.cacheSize, 1);
    });
  });
}
