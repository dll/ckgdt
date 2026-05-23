import 'agent_model.dart';
import 'agent_registry.dart';

/// 多 Agent 串联编排器。
///
/// **使用场景**：当一个任务需要多个 Agent 协作时（例如批阅作业 = safety 审查 →
/// 主批阅 → ethics 评论），用此编排器，避免在前端拼调用链。
///
/// **典型用法**：
/// ```dart
/// final orchestrator = OrchestratorAgent();
/// final result = await orchestrator.runChain(
///   userMessage: '请批阅以下实验报告...',
///   session: session,
///   agentChain: ['safety', 'lab_grading', 'ethics'],
/// );
/// ```
///
/// 链式输出：每个 Agent 的回复作为下一个 Agent 的输入。最终返回完整对话历史。
///
/// **设计权衡**：当前是顺序串联。复杂的 DAG / 辩论模式留给将来。
class OrchestratorAgent {
  /// 顺序串联调用 [agentChain] 中的 Agent，把上一个 Agent 的回复作为下一个的输入。
  ///
  /// 失败时（找不到 agent / Agent 抛错）会跳过该步并继续，最终结果会标注哪些步跳过。
  Future<OrchestratorResult> runChain({
    required String userMessage,
    required AgentSession session,
    required List<String> agentChain,
  }) async {
    final steps = <OrchestratorStep>[];
    String currentInput = userMessage;

    for (final agentId in agentChain) {
      final agent = AgentRegistry.instance.getAgent(agentId);
      if (agent == null) {
        steps.add(OrchestratorStep(
          agentId: agentId,
          agentName: '(unknown)',
          input: currentInput,
          output: null,
          skipped: true,
          error: 'Agent not registered',
        ));
        continue;
      }

      try {
        final reply = await agent.handleMessage(currentInput, session);
        steps.add(OrchestratorStep(
          agentId: agent.config.id,
          agentName: agent.config.name,
          input: currentInput,
          output: reply.content,
          skipped: false,
        ));
        currentInput = reply.content;
      } catch (e) {
        steps.add(OrchestratorStep(
          agentId: agent.config.id,
          agentName: agent.config.name,
          input: currentInput,
          output: null,
          skipped: true,
          error: e.toString(),
        ));
      }
    }

    return OrchestratorResult(
      steps: steps,
      finalOutput: steps.lastWhere(
        (s) => !s.skipped && s.output != null,
        orElse: () => OrchestratorStep(
          agentId: '',
          agentName: '',
          input: userMessage,
          output: '所有 Agent 均跳过，未产生有效输出。',
          skipped: true,
        ),
      ).output,
    );
  }
}

class OrchestratorStep {
  final String agentId;
  final String agentName;
  final String input;
  final String? output;
  final bool skipped;
  final String? error;

  const OrchestratorStep({
    required this.agentId,
    required this.agentName,
    required this.input,
    required this.output,
    required this.skipped,
    this.error,
  });
}

class OrchestratorResult {
  /// 完整调用历史（含被跳过的）
  final List<OrchestratorStep> steps;

  /// 最后一个非跳过 Agent 的输出
  final String? finalOutput;

  const OrchestratorResult({required this.steps, required this.finalOutput});

  /// 调试用：打印整条链路
  String prettyPrint() {
    final buf = StringBuffer();
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      buf.writeln('━━━ Step ${i + 1}: ${s.agentName} (${s.agentId}) ━━━');
      if (s.skipped) {
        buf.writeln('SKIPPED: ${s.error ?? "no reason"}');
      } else {
        buf.writeln('< ${s.input.length > 100 ? "${s.input.substring(0, 100)}…" : s.input}');
        buf.writeln('> ${s.output?.length != null && s.output!.length > 200 ? "${s.output!.substring(0, 200)}…" : s.output}');
      }
    }
    return buf.toString();
  }
}

/// 注意：本类**不是 BaseAgent 的子类** —— 它是更高层次的调度器，
/// 不需要自己有 persona 或 handleMessage。如果将来要用 Director 自动选择
/// 是否走编排，可以再写一个 wrapper Agent 包装它。

/// 预定义编排链 — 业务页面调用方便。
class OrchestratorChains {
  OrchestratorChains._();

  /// 实验/作业批阅链：safety 审查 → 主批阅 → ethics 学术伦理建议。
  /// 调用方传入"待批阅内容"，返回最终批阅结果（含 ethics 评论）。
  static const List<String> labGrading = ['safety', 'lab_grading', 'ethics'];

  /// 项目考核批阅链
  static const List<String> assessmentGrading = [
    'safety',
    'assessment_grading',
    'ethics'
  ];

  /// 学生作品批阅链
  static const List<String> worksGrading = ['safety', 'works_grading', 'ethics'];

  /// 答疑链：先安全审查再答疑
  static const List<String> tutoring = ['safety', 'tutor'];
}
