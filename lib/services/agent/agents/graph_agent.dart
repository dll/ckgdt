import '../../../data/local/knowledge_graph_dao.dart';
import '../../../data/local/graph_dao.dart';
import '../../ai_service.dart';
import '../special_agent_tools.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 🕸️ 图谱智能体 — 知识图谱生成/扩展/查询
class GraphAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => AgentConfig(
        id: 'graph',
        name: '图谱专家',
        emoji: '🕸️',
        description: '构建和分析知识图谱，梳理概念关系。',
        persona: '''你是知识图谱设计专家"图谱大师"，精通知识工程和本体建模方法论。
你服务于《移动应用开发》课程，覆盖 Android/iOS/Flutter/React Native/小程序/HarmonyOS 六大技术栈。

## 核心能力
1. **概念提取**：从任何技术主题中识别核心概念、辅助概念和边缘概念，标注难度等级（基础/进阶/高级）和所属章节（1-6章）。
2. **关系建模**：构建概念间的语义关系，支持 8 种关系类型：prerequisite（前置）、related_to（关联）、part_of（组成）、compared_with（对比）、applied_in（应用于）、builds_upon（进阶）、alternative_to（替代）、extends（扩展）。
3. **层级构建**：按认知难度和依赖关系组织多层级图谱，确保从基础到进阶的渐进性。
4. **图谱分析**：识别已有图谱中的孤立节点、缺失关系、知识空白区域。

## 输出规范
- 使用 Markdown 格式，结构清晰
- 概念列表用表格展示（名称 | 类型 | 难度 | 章节 | 简述）
- 关系用箭头表示：`概念A --[关系类型]--> 概念B`
- 每次回答包含：核心概念（5-10个）、关系图（5-15条）、推荐学习顺序
- 如果用户提供已有概念，在此基础上扩展而非重建

## 质量标准
- 概念不重叠、不遗漏，覆盖主题的核心知识点
- 关系准确、有依据，避免牵强附会
- 层级合理，前置知识不跳级
- 与课程 6 章内容对齐

## Few-shot 示例

用户：帮我生成 Flutter 状态管理的知识图谱
助手：
| 概念 | 类型 | 难度 | 章节 | 说明 |
|------|------|------|------|------|
| setState | 基础概念 | 基础 | 3 | 最简单的状态管理方式 |
| InheritedWidget | 核心概念 | 进阶 | 3 | 跨组件数据传递机制 |
| Provider | 框架 | 进阶 | 3 | 官方推荐的状态管理方案 |
| Riverpod | 框架 | 高级 | 3 | Provider 的改进版 |
| Bloc/Cubit | 模式 | 高级 | 3 | 事件驱动的状态管理 |

关系：
- setState --[builds_upon]--> InheritedWidget
- InheritedWidget --[builds_upon]--> Provider
- Provider --[alternative_to]--> Riverpod
- Provider --[alternative_to]--> Bloc/Cubit

学习顺序：setState → InheritedWidget → Provider → Riverpod 或 Bloc''',
        priority: 7,
        keywords: ['图谱', '概念', '节点', '关系', '知识点', '知识结构', '脉络', '体系'],
        capabilities: ['生成知识图谱', '扩展概念', '查询节点', '分析关系'],
        requiresAi: true,
        useRag: true,
        tools: [
          AgentTool(
            name: 'search_concepts',
            description: '搜索课程知识概念库',
            parameters: {'keyword': '搜索关键词'},
            execute: (params) async {
              final kw = params['keyword'] as String? ?? '';
              if (kw.isEmpty) return '请提供搜索关键词';
              final dao = KnowledgeGraphDao();
              final results = await dao.searchConcepts(kw);
              if (results.isEmpty) return '未找到与"$kw"相关的概念';
              return results
                  .take(10)
                  .map((c) => '- ${c['concept_name']}（${c['concept_type']}）'
                      '[第${c['chapter']}章] ${c['description'] ?? ''}')
                  .join('\n');
            },
          ),
          AgentTool(
            name: 'get_graph_list',
            description: '获取所有知识图谱列表',
            parameters: {},
            execute: (params) async {
              final dao = GraphDao();
              final graphs = await dao.getAllGraphs();
              if (graphs.isEmpty) return '暂无知识图谱';
              return graphs
                  .map((g) => '- ${g.title}（${g.graphType ?? "通用"}）')
                  .join('\n');
            },
          ),
          AgentTool(
            name: 'get_concept_relations',
            description: '获取某个概念的所有关联关系',
            parameters: {'concept_id': '概念 ID（数字）'},
            execute: (params) async {
              final id = int.tryParse('${params['concept_id']}');
              if (id == null) return '请提供有效的概念 ID';
              final dao = KnowledgeGraphDao();
              final concept = await dao.getConceptById(id);
              if (concept == null) return '概念 #$id 不存在';
              final rels = await dao.getRelationsForConcept(id);
              if (rels.isEmpty) return '"${concept['concept_name']}" 暂无关联关系';
              // 获取关联概念的名称
              final buf = StringBuffer('"${concept['concept_name']}" 的关系：\n');
              for (final r in rels) {
                final srcId = r['source_concept_id'] as int;
                final tgtId = r['target_concept_id'] as int;
                final otherId = srcId == id ? tgtId : srcId;
                final other = await dao.getConceptById(otherId);
                final otherName = other?['concept_name'] ?? '#$otherId';
                final relType = r['relation_type'] ?? 'related_to';
                if (srcId == id) {
                  buf.writeln(
                      '- ${concept['concept_name']} --[$relType]--> $otherName');
                } else {
                  buf.writeln(
                      '- $otherName --[$relType]--> ${concept['concept_name']}');
                }
              }
              return buf.toString();
            },
          ),
        ],
        usageSteps: [
          '在对话面板中选择 🕸️ 图谱专家',
          '输入想要生成或查询的知识主题',
          '智能体返回概念节点和关系结构',
          '可继续追问扩展或细化图谱内容',
        ],
        classicCases: [
          const AgentCase(
              title: '生成技术图谱',
              userInput: '帮我生成 Flutter 状态管理的知识图谱',
              agentReply:
                  '## Flutter 状态管理知识图谱\n\n### 核心概念\n- setState（基础状态管理）\n- Provider（依赖注入）\n- Riverpod（改进版 Provider）\n- Bloc/Cubit（事件驱动）\n\n### 关系\n- setState → Provider（进阶替代）\n- Provider → Riverpod（演进）'),
          const AgentCase(
              title: '扩展已有图谱',
              userInput: '在 Android 开发图谱中补充 Jetpack Compose 相关概念',
              agentReply:
                  '为 Android 图谱补充以下概念：\n- Jetpack Compose（声明式 UI）\n- Composable 函数\n- State hoisting\n- remember/mutableStateOf'),
        ],
      );

  @override
  List<String> get quickCommands => ['生成Flutter图谱', '搜索概念', '分析概念关系', '图谱统计'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final tools = SpecialAgentTools.instance;
    if (tools.isGraphGenerationIntent(userMessage)) {
      try {
        final reply = await tools.generateKnowledgeGraph(
          userRequest: userMessage,
        );
        return buildReply(reply);
      } catch (e) {
        return buildReply('图谱生成失败：$e');
      }
    }

    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithTools(
      userMessage,
      messages,
      aiService: _ai,
    );
    return buildReplyFromResult(result);
  }
}
