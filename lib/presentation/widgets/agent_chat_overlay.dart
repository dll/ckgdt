import 'package:flutter/material.dart';
import '../../services/agent/agent_model.dart';
import '../../services/agent/agent_registry.dart';
import '../../services/navigation_service.dart';
import '../../services/tts_flutter_service.dart';
import '../../services/voice_service.dart';

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
        TtsFlutterService.instance.speak(reply.content);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name · AI 助手',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
              // TTS 开关
              IconButton(
                icon: Icon(
                  _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                  color: _ttsEnabled ? theme.colorScheme.primary : Colors.grey,
                  size: 20,
                ),
                tooltip: _ttsEnabled ? '关闭语音朗读' : '开启语音朗读',
                onPressed: () {
                  setState(() => _ttsEnabled = !_ttsEnabled);
                  if (!_ttsEnabled) {
                    TtsFlutterService.instance.stop();
                  }
                },
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
    final configs = _registry.allConfigs;
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
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
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
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
            child: SelectableText(
              msg.content,
              style: TextStyle(fontSize: 14, color: textColor, height: 1.5),
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
              color: Colors.black.withValues(alpha: 0.05),
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
                      : theme.colorScheme.primary.withValues(alpha: 0.1),
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
