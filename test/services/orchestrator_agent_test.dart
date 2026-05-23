import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/agent/agent_model.dart';
import 'package:knowledge_graph_app/services/agent/orchestrator_agent.dart';

/// OrchestratorAgent 不依赖网络/DB 的纯结构化测试。
///
/// 这里覆盖：
/// 1. 调用链找不到 agent 时跳过但继续
/// 2. chainId 真生成（非空、唯一、可预期前缀）
/// 3. OrchestratorResult.finalOutput 在 fallback 时返回提示文案
///
/// 真实的 agent 流程（含 BaseAgent.safeAiChatWithMeta 写日志）需要 sqflite
/// + AiService，留给集成测试，本文件保持快速。
void main() {
  group('OrchestratorAgent.runChain', () {
    test('全部 Agent 找不到时返回 fallback 输出', () async {
      final orch = OrchestratorAgent();
      final result = await orch.runChain(
        userMessage: 'test',
        session: AgentSession(),
        agentChain: ['nope_a', 'nope_b'],
      );
      expect(result.steps.length, 2);
      expect(result.steps.every((s) => s.skipped), isTrue);
      expect(result.finalOutput, contains('所有 Agent 均跳过'));
    });

    test('chainId 非空且为 chn- 前缀（可被 agent_call_logs 索引追溯）', () async {
      final orch = OrchestratorAgent();
      final result = await orch.runChain(
        userMessage: 't',
        session: AgentSession(),
        agentChain: ['nope_a'],
      );
      expect(result.chainId.startsWith('chn-'), isTrue,
          reason: 'chainId 必须有 chn- 前缀以便 SQL like 查询');
      expect(result.chainId.length, greaterThan(8));
    });

    test('两次 runChain 的 chainId 不同（基于 microsecondsSinceEpoch）', () async {
      final orch = OrchestratorAgent();
      final r1 = await orch.runChain(
        userMessage: 'a',
        session: AgentSession(),
        agentChain: ['nope'],
      );
      await Future.delayed(const Duration(microseconds: 2));
      final r2 = await orch.runChain(
        userMessage: 'b',
        session: AgentSession(),
        agentChain: ['nope'],
      );
      expect(r1.chainId, isNot(equals(r2.chainId)));
    });
  });
}
