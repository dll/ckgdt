import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/local/ai_history_dao.dart';
import '../../data/local/knowledge_graph_dao.dart';
import '../../services/agent/agent_model.dart';
import '../../services/agent/agent_registry.dart';
import '../../services/ai_service.dart';
import '../../services/auth_service.dart';
import '../../services/navigation_service.dart';
import '../../services/tts_flutter_service.dart';
import '../../services/voice_service.dart';
import '../pages/profile/chat_history_page.dart';
import 'markdown_bubble.dart';

/// 多智能体对话浮层 — 全局 BottomSheet 对话面板
///
/// 布局结构：
/// ┌──────────────────────────────────────────┐
/// │  标题栏（当前智能体 emoji + 名称 + 关闭） │
/// ├──────────────────────────────────────────┤
/// │  智能体快捷切换（横向滚动 Chip）          │
/// ├──────────────────────────────────────────┤
/// │  消息列表 / 欢迎页                       │
/// │  快捷指令 Chip                           │
/// ├──────────────────────────────────────────┤
/// │  🎤 │ 输入框 │ 发送 ▶                    │
/// └──────────────────────────────────────────┘
class AgentChatOverlay extends StatefulWidget {
  /// 初始激活的智能体 ID（可选）
  final String? initialAgentId;

  const AgentChatOverlay({super.key, this.initialAgentId});

  /// 便捷打开方法
  static Future<void> show(BuildContext context, {String? agentId}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AgentChatOverlay(initialAgentId: agentId),
    );
  }

  @override
  State<AgentChatOverlay> createState() => _AgentChatOverlayState();
}

class _AgentChatOverlayState extends State<AgentChatOverlay> {
  final AgentRegistry _registry = AgentRegistry.instance;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isLoading = false;
  bool _ttsEnabled = false;
  bool _isVoiceListening = false;
  bool _agentPanelExpanded = false;

  @override
  void initState() {
    super.initState();
    _registry.initialize();

    // 设置回调
    _registry.onMessage = (msg) {
      if (mounted) setState(() {});
      _scrollToBottom();
    };
    _registry.onAction = _handleAction;
    _registry.onAgentSwitch = (agentId) {
      if (mounted) setState(() {});
    };

    // 如果指定了初始智能体，切换到它
    if (widget.initialAgentId != null) {
      _registry.switchTo(widget.initialAgentId!);
    } else if (_registry.session.messages.isEmpty) {
      // 添加欢迎消息
      final welcome = _registry.getWelcomeMessage();
      _registry.session.messages.add(welcome);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _registry.onMessage = null;
    _registry.onAction = null;
    _registry.onAgentSwitch = null;
    // 离开页面时停止语音播报
    if (_ttsEnabled) {
      TtsFlutterService.instance.stop();
    }
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 消息处理
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _sendMessage([String? text]) async {
    final content = text ?? _inputController.text.trim();
    if (content.isEmpty || _isLoading) return;

    _inputController.clear();
    setState(() => _isLoading = true);

    try {
      final reply = await _registry.dispatch(content);

      // TTS 朗读回复
      if (_ttsEnabled && !reply.isLoading) {
        final tts = TtsFlutterService.instance;
        await tts.speak(reply.content);
        // 如果 TTS 不可用，提示用户并自动关闭 TTS 开关
        if (!tts.isAvailable && mounted) {
          setState(() => _ttsEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tts.lastError ?? '语音合成不可用'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('AgentChatOverlay: 发送失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleAction(AgentAction action) {
    switch (action.type) {
      case 'navigate_tab':
        final keyword = action.params['keyword'] as String?;
        if (keyword != null) {
          NavigationService.instance.navigateByKeyword(keyword);
          if (mounted) Navigator.of(context).pop(); // 关闭面板
        }
        break;
      case 'navigate_home':
        NavigationService.instance.switchToTab(0);
        if (mounted) Navigator.of(context).pop();
        break;
      case 'navigate_login':
        if (mounted) Navigator.of(context).pop();
        break;
      default:
        break;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 语音输入
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _startVoiceInput() async {
    // Web 平台不支持语音录制
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Web 平台暂不支持语音输入'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final configured = await VoiceService.isConfigured();
    if (!configured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先在系统设置中配置讯飞语音参数'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isVoiceListening = true);
    try {
      final voice = VoiceService();
      voice.onResult = (text) {
        if (mounted && text.isNotEmpty) {
          setState(() {
            _inputController.text = text;
          });
        }
      };
      voice.onComplete = (finalText) {
        if (mounted) {
          setState(() => _isVoiceListening = false);
          if (finalText.trim().isNotEmpty) {
            _sendMessage(finalText.trim());
          }
        }
      };
      voice.onError = (error) {
        debugPrint('语音输入错误: $error');
        if (mounted) setState(() => _isVoiceListening = false);
      };
      await voice.startListening();
    } catch (e) {
      debugPrint('语音输入错误: $e');
      if (mounted) setState(() => _isVoiceListening = false);
    }
  }

  void _stopVoiceInput() {
    VoiceService().stopListening();
    if (mounted) setState(() => _isVoiceListening = false);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 菜单操作
  // ═════════════════════════════════════════════════════════════════════════

  void _handleMenuAction(String action) {
    switch (action) {
      case 'star':
        _starCurrentSession();
        break;
      case 'history':
        Navigator.of(context).pop(); // 先关闭对话面板
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ChatHistoryPage()),
        );
        break;
      case 'clear':
        _clearConversation();
        break;
      case 'save_kb':
        _saveToKnowledgeBase();
        break;
      case 'gen_graph':
        _generateQaGraph();
        break;
    }
  }

  Future<void> _starCurrentSession() async {
    final sessionId = _registry.session.id;
    final dao = AiHistoryDao();
    await dao.toggleStar(sessionId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已收藏当前对话'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearConversation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('确定清空当前对话内容吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      _registry.session.messages.clear();
      // 添加新的欢迎消息
      final welcome = _registry.getWelcomeMessage();
      _registry.session.messages.add(welcome);
      setState(() {});
    }
  }

  /// 将当前对话存入知识库（knowledge_concepts 表）
  Future<void> _saveToKnowledgeBase() async {
    final messages = _registry.session.messages
        .where((m) => m.role != MessageRole.system)
        .toList();
    if (messages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前对话为空，无法存入知识库')),
        );
      }
      return;
    }

    // 构建对话摘要
    final qaPairs = <String>[];
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prefix = m.role == MessageRole.user ? 'Q' : 'A';
      qaPairs.add('$prefix: ${m.content}');
    }
    final dialogText = qaPairs.join('\n');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在通过 AI 提取知识点...')),
    );

    try {
      final aiService = AiService();
      final response = await aiService.chat(
        [
          {
            'role': 'user',
            'content': '''请从以下对话中提取关键知识点，输出 JSON 数组，每个元素格式为：
{"name": "概念名称", "description": "概念描述", "keywords": "关键词1,关键词2"}

对话内容：
$dialogText

要求：
1. 提取 3-8 个核心知识点
2. name 简洁（2-8字）
3. description 一句话概括
4. keywords 用逗号分隔

只输出 JSON 数组，不要其他文字。''',
          },
        ],
      );

      // 解析 AI 返回的 JSON
      final jsonStr = response.replaceAll(RegExp(r'```json?\s*'), '').replaceAll('```', '').trim();
      final List<dynamic> concepts = _tryParseJsonArray(jsonStr);

      if (concepts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未能从对话中提取知识点'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final kgDao = KnowledgeGraphDao();
      int saved = 0;
      for (final c in concepts) {
        if (c is Map<String, dynamic>) {
          await kgDao.addConcept({
            'concept_name': c['name'] ?? '',
            'concept_type': 'qa_extracted',
            'description': c['description'] ?? '',
            'keywords': c['keywords'] ?? '',
            'importance': 'important',
          });
          saved++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已提取 $saved 个知识点存入知识库'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('存入知识库失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 从对话生成问答图谱
  Future<void> _generateQaGraph() async {
    final messages = _registry.session.messages
        .where((m) => m.role != MessageRole.system)
        .toList();
    if (messages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前对话为空，无法生成图谱')),
        );
      }
      return;
    }

    final qaPairs = <String>[];
    for (final m in messages) {
      final prefix = m.role == MessageRole.user ? 'Q' : 'A';
      qaPairs.add('$prefix: ${m.content}');
    }
    final dialogText = qaPairs.join('\n');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在通过 AI 生成问答图谱...')),
    );

    try {
      final aiService = AiService();
      final response = await aiService.chat(
        [
          {
            'role': 'user',
            'content': '''请从以下问答对话中提取知识概念和它们之间的关系，输出 JSON，格式为：
{
  "concepts": [
    {"name": "概念名", "description": "描述", "keywords": "关键词"}
  ],
  "relations": [
    {"source": "概念A名", "target": "概念B名", "type": "关系类型", "label": "关系标签"}
  ]
}

关系类型可选：prerequisite（前置）, extends（扩展）, related（相关）, part_of（组成）, example_of（示例）

对话内容：
$dialogText

要求：
1. 提取 3-10 个核心概念
2. 建立概念间有意义的关系
3. 只输出 JSON，不要其他文字''',
          },
        ],
      );

      final jsonStr = response.replaceAll(RegExp(r'```json?\s*'), '').replaceAll('```', '').trim();
      Map<String, dynamic>? parsed;
      try {
        parsed = _tryParseJsonMap(jsonStr);
      } catch (_) {}

      if (parsed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AI 返回格式异常，无法解析图谱'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final kgDao = KnowledgeGraphDao();
      final conceptList = (parsed['concepts'] as List?) ?? [];
      final relationList = (parsed['relations'] as List?) ?? [];

      // 存储概念并记录 name → id 映射
      final nameToId = <String, int>{};
      for (final c in conceptList) {
        if (c is Map<String, dynamic>) {
          final name = c['name'] as String? ?? '';
          if (name.isEmpty) continue;
          final id = await kgDao.addConcept({
            'concept_name': name,
            'concept_type': 'qa_graph',
            'description': c['description'] ?? '',
            'keywords': c['keywords'] ?? '',
            'importance': 'important',
          });
          nameToId[name] = id;
        }
      }

      // 存储关系
      int relCount = 0;
      for (final r in relationList) {
        if (r is Map<String, dynamic>) {
          final sourceName = r['source'] as String? ?? '';
          final targetName = r['target'] as String? ?? '';
          final sourceId = nameToId[sourceName];
          final targetId = nameToId[targetName];
          if (sourceId != null && targetId != null) {
            await kgDao.addRelation({
              'source_concept_id': sourceId,
              'target_concept_id': targetId,
              'relation_type': r['type'] ?? 'related',
              'relation_label': r['label'] ?? '',
              'ai_generated': 1,
            });
            relCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '图谱生成完成：${nameToId.length} 个概念，$relCount 条关系'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成图谱失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 尝试解析 JSON 数组
  List<dynamic> _tryParseJsonArray(String text) {
    try {
      // 找到第一个 [ 和最后一个 ]
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start >= 0 && end > start) {
        final jsonStr = text.substring(start, end + 1);
        final result = _jsonDecode(jsonStr);
        if (result is List) return result;
      }
    } catch (_) {}
    return [];
  }

  /// 尝试解析 JSON 对象
  Map<String, dynamic>? _tryParseJsonMap(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final jsonStr = text.substring(start, end + 1);
        final result = _jsonDecode(jsonStr);
        if (result is Map<String, dynamic>) return result;
      }
    } catch (_) {}
    return null;
  }

  dynamic _jsonDecode(String text) {
    return jsonDecode(text);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // 智能体信息面板
  // ═════════════════════════════════════════════════════════════════════════

  /// 显示智能体详细信息面板
  void _showAgentInfo(AgentConfig config) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) {
          final theme = Theme.of(ctx);
          return Column(
            children: [
              // 拖拽指示器
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(config.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            config.description,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              // 内容
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 能力标签
                      if (config.capabilities.isNotEmpty) ...[
                        _infoSectionTitle('能力标签', Icons.label_outline),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: config.capabilities.map((cap) {
                            return Chip(
                              label: Text(cap, style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 使用步骤
                      if (config.usageSteps.isNotEmpty) ...[
                        _infoSectionTitle('使用步骤', Icons.format_list_numbered),
                        const SizedBox(height: 8),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: config.usageSteps.asMap().entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${entry.key + 1}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          entry.value,
                                          style: const TextStyle(fontSize: 13, height: 1.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 经典案例
                      if (config.classicCases.isNotEmpty) ...[
                        _infoSectionTitle('经典案例', Icons.lightbulb_outline),
                        const SizedBox(height: 8),
                        ...config.classicCases.map((c) {
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              leading: const Icon(Icons.chat_bubble_outline, size: 18),
                              title: Text(c.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              children: [
                                // 用户输入
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('用户输入', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(c.userInput, style: const TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                // 智能体回复
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('智能体回复', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(c.agentReply, style: const TextStyle(fontSize: 13, height: 1.4)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // 发送按钮
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx); // 关闭信息面板
                                      _sendMessage(c.userInput); // 发送案例输入
                                    },
                                    icon: const Icon(Icons.send, size: 14),
                                    label: const Text('发送这条消息', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: theme.colorScheme.primary,
                                      side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.5)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],

                      // 关键词
                      if (config.keywords.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _infoSectionTitle('触发关键词', Icons.tag),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: config.keywords.map((kw) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(kw, style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 信息面板的小节标题
  Widget _infoSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // UI
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, _) => Column(
          children: [
            // ── 拖拽指示器 + 标题栏 ──
            _buildHeader(theme, isDark),

            // ── 智能体切换栏 ──
            _buildAgentChips(theme),

            const Divider(height: 1),

            // ── 消息列表 ──
            Expanded(
              child: _registry.session.messages.isEmpty
                  ? _buildWelcome(theme)
                  : _buildMessageList(theme, isDark),
            ),

            // ── 快捷指令 ──
            _buildQuickCommands(theme),

            // ── 输入栏 ──
            _buildInputBar(theme, isDark),
          ],
        ),
      ),
    );
  }

  /// 标题栏
  Widget _buildHeader(ThemeData theme, bool isDark) {
    final active = _registry.activeAgent;
    final emoji = active?.config.emoji ?? '🤖';
    final name = active?.config.name ?? '小知';

    return Column(
      children: [
        // 拖拽指示器
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[400],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (active != null) _showAgentInfo(active.config);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$name · AI 助手',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                        ],
                      ),
                      if (active != null)
                        Text(
                          active.config.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
              // TTS 开关
              IconButton(
                icon: Icon(
                  _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                  color: _ttsEnabled ? theme.colorScheme.primary : Colors.grey,
                  size: 20,
                ),
                tooltip: _ttsEnabled ? '关闭语音朗读' : '开启语音朗读',
                onPressed: () {
                  final tts = TtsFlutterService.instance;
                  if (!_ttsEnabled && !tts.isAvailable) {
                    // 尝试重新初始化 TTS
                    tts.reinitialize().then((_) {
                      if (mounted) {
                        if (tts.isAvailable) {
                          setState(() => _ttsEnabled = true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tts.lastError ?? '语音合成引擎不可用'),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    });
                    return;
                  }
                  setState(() => _ttsEnabled = !_ttsEnabled);
                  if (!_ttsEnabled) {
                    tts.stop();
                  }
                },
              ),
              // 更多操作菜单
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                onSelected: _handleMenuAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'star',
                    child: Row(
                      children: [
                        Icon(Icons.star_border, size: 18, color: Colors.amber),
                        SizedBox(width: 8),
                        Text('收藏对话'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 18),
                        SizedBox(width: 8),
                        Text('对话历史'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'save_kb',
                    child: Row(
                      children: [
                        Icon(Icons.save_alt, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('存入知识库'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'gen_graph',
                    child: Row(
                      children: [
                        Icon(Icons.account_tree, size: 18, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('生成问答图谱'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('清空对话', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
              // 关闭按钮
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// 智能体快捷切换 — 收起时一行滚动 + 展开按钮，展开时多行网格
  Widget _buildAgentChips(ThemeData theme) {
    final userRole = AuthService().currentUser?.role ?? 'student';
    final configs = _registry.configsForRole(userRole);
    final activeId = _registry.session.activeAgentId;

    if (_agentPanelExpanded) {
      // ── 展开态：多行 Wrap 网格 ──
      return Container(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行 + 收起按钮
              Row(
                children: [
                  Text(
                    '全部智能体（${configs.length}）',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _agentPanelExpanded = false),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('收起', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                          Icon(Icons.keyboard_arrow_up, size: 16, color: theme.colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 多行 Wrap
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: configs.map((cfg) {
                  final isActive = cfg.id == activeId;
                  return FilterChip(
                    selected: isActive,
                    label: Text(
                      '${cfg.emoji} ${cfg.name}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onSelected: (_) {
                      _registry.switchTo(cfg.id);
                      setState(() => _agentPanelExpanded = false);
                      _scrollToBottom();
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      );
    }

    // ── 收起态：一行横向滚动 + 展开按钮 ──
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: configs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final cfg = configs[index];
                final isActive = cfg.id == activeId;

                return FilterChip(
                  selected: isActive,
                  label: Text(
                    '${cfg.emoji} ${cfg.name}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onSelected: (_) {
                    _registry.switchTo(cfg.id);
                    _scrollToBottom();
                  },
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
          // 展开按钮
          InkWell(
            onTap: () => setState(() => _agentPanelExpanded = true),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.grid_view, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 2),
                  Text(
                    '${configs.length}',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 欢迎页
  Widget _buildWelcome(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🤖', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              '你好！我是小知',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '你的 AI 学习助手，有什么可以帮你的？',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _quickChip('有哪些智能体', theme),
                _quickChip('帮我出几道题', theme),
                _quickChip('打开知识图谱', theme),
                _quickChip('学习进度如何', theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(String text, ThemeData theme) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () => _sendMessage(text),
    );
  }

  /// 消息列表
  Widget _buildMessageList(ThemeData theme, bool isDark) {
    final messages = _registry.session.messages;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        // 加载指示器
        if (index == messages.length) {
          return _buildTypingIndicator(theme, isDark);
        }

        final msg = messages[index];
        if (msg.role == MessageRole.system) {
          return _buildSystemBubble(msg, theme);
        }
        return _buildBubble(msg, theme, isDark);
      },
    );
  }

  /// 系统消息（智能体切换提示）
  Widget _buildSystemBubble(AgentMessage msg, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${msg.agentEmoji} ${msg.content}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// 聊天气泡
  Widget _buildBubble(AgentMessage msg, ThemeData theme, bool isDark) {
    final isUser = msg.role == MessageRole.user;
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isUser
        ? theme.colorScheme.primary
        : (isDark ? const Color(0xFF2A2A2A) : Colors.grey[100]!);
    final textColor = isUser
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isUser ? 16 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 16),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // 智能体名称标签（仅非用户消息）
          if (!isUser && msg.agentName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                '${msg.agentEmoji} ${msg.agentName}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
          // 气泡
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: borderRadius,
            ),
            child: isUser
                ? SelectableText(
                    msg.content,
                    style: TextStyle(fontSize: 14, color: textColor, height: 1.5),
                  )
                : MarkdownBubble(
                    content: msg.content,
                    provider: msg.modelProvider,
                    model: msg.modelName,
                    textColor: textColor,
                    compact: true,
                  ),
          ),
        ],
      ),
    );
  }

  /// 正在输入指示器
  Widget _buildTypingIndicator(ThemeData theme, bool isDark) {
    final active = _registry.activeAgent;
    final emoji = active?.config.emoji ?? '🤖';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$emoji 正在思考...',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 快捷指令 Chip
  Widget _buildQuickCommands(ThemeData theme) {
    final active = _registry.activeAgent;
    if (active == null) return const SizedBox.shrink();

    final commands = active.quickCommands;
    if (commands.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: commands.map((cmd) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(cmd, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: _isLoading ? null : () => _sendMessage(cmd),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 输入栏
  Widget _buildInputBar(ThemeData theme, bool isDark) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            // 语音按钮
            GestureDetector(
              onLongPressStart: (_) => _startVoiceInput(),
              onLongPressEnd: (_) => _stopVoiceInput(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _isVoiceListening
                      ? Colors.red
                      : theme.colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isVoiceListening ? Icons.mic : Icons.mic_none,
                  size: 18,
                  color: _isVoiceListening
                      ? Colors.white
                      : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 输入框
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: _isVoiceListening ? '正在聆听...' : '输入消息...',
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            // 发送按钮
            IconButton.filled(
              icon: const Icon(Icons.send, size: 18),
              onPressed: _isLoading ? null : () => _sendMessage(),
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
