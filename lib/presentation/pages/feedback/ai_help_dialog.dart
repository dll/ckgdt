import 'package:flutter/material.dart';
import '../../../services/ai_service.dart';
import '../../../services/auth_service.dart';
import '../../widgets/markdown_bubble.dart';

/// AI 助手帮助对话框 — 使用集成的 AI API 回答用户常见问题
class AiHelpDialog extends StatefulWidget {
  const AiHelpDialog({super.key});

  /// 弹出 AI 帮助对话框
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AiHelpDialog(),
    );
  }

  @override
  State<AiHelpDialog> createState() => _AiHelpDialogState();
}

class _AiHelpDialogState extends State<AiHelpDialog> {
  final _aiService = AiService();
  final _authService = AuthService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_HelpMessage> _messages = [];
  bool _isLoading = false;

  // 常见问题快捷入口
  static const _quickQuestions = [
    '如何查看知识图谱？',
    '怎么生成学习路径？',
    '如何参加章节测验？',
    '怎么提交实验作业？',
    '如何查看学习进度？',
    '系统支持哪些功能？',
  ];

  static const _systemPrompt = '''你是"知识图谱教学平台"的 AI 助手。
请用简洁友好的中文回答用户关于本系统的使用问题。

本系统的主要功能包括：
1. 知识图谱：可视化浏览当前课程知识体系，支持全局视图、章节视图、关系视图、掩码视图、达成视图
2. 学习路径：从知识图谱中生成推荐学习路径，按顺序学习知识点
3. 学习资源：包含视频教程、PPT课件、PDF文档，按课程章节组织
4. 章节测验：选择题测验，支持错题本复习
5. 实验任务：实验作业提交和评分
6. 考核评估：课程考核和成绩管理
7. 作品管理：学生作品展示
8. AI 助手：在学习页面的AI助手tab中可以与AI对话
9. 数据同步：通过Gitee仓库同步学习数据
10. 课程达成：查看课程目标达成情况

操作指引：
- 底部导航栏可切换主要功能页面
- 首页有学习流程导航条：图谱→路径→学习→测验
- 右上角人物图标可进入系统设置、学习进度、手册等
- 知识图谱中点击概念节点可以查看详情、生成学习路径
- 学习页面包含视频、PPT、PDF、测验、AI助手五个标签页

请回答时：
- 简洁明了，每次回复不超过200字
- 如果问题不属于本系统范围，礼貌说明并引导用户提交反馈
- 态度亲切友好''';

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? quickQuestion]) async {
    final text = quickQuestion ?? _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    setState(() {
      _messages.add(_HelpMessage(text, true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      // 构建对话上下文（最近 6 条消息）
      final contextMessages = _messages
          .skip(_messages.length > 7 ? _messages.length - 7 : 0)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();

      final result = await _aiService.chatWithMeta(
        contextMessages,
        systemPrompt: _systemPrompt,
      );

      if (mounted) {
        setState(() {
          _messages.add(_HelpMessage(
            result.content,
            false,
            modelProvider: result.provider,
            modelName: result.model,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_HelpMessage(
            '抱歉，AI 助手暂时无法回复。\n请检查AI配置或稍后再试。\n\n错误信息：$e',
            false,
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, _) {
          return Column(
            children: [
              // 拖拽指示器 + 标题
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.support_agent,
                              color: primary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AI 助手',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: primary)),
                              Text('有什么问题都可以问我哦~',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                        // 关闭按钮
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                  ],
                ),
              ),

              // 消息列表
              Expanded(
                child: _messages.isEmpty
                    ? _buildWelcome(primary)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length && _isLoading) {
                            return _buildTypingIndicator(primary);
                          }
                          return _buildBubble(_messages[index], primary);
                        },
                      ),
              ),

              // 快捷问题栏（消息不多时显示）
              if (_messages.length < 4) _buildQuickBar(primary),

              // 输入框
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          maxLines: 2,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: '输入您的问题...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send, size: 20),
                        onPressed: _isLoading ? null : () => _sendMessage(),
                      ),
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

  Widget _buildWelcome(Color primary) {
    final user = _authService.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.support_agent, color: primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            '您好，${user?.realName ?? '同学'}！',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: primary),
          ),
          const SizedBox(height: 8),
          Text(
            '我是系统 AI 助手，可以帮您解答使用问题。\n试试点击下方常见问题，或直接输入提问。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _quickQuestions
                .map((q) => ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 13)),
                      avatar:
                          Icon(Icons.help_outline, size: 16, color: primary),
                      onPressed: () => _sendMessage(q),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBar(Color primary) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _quickQuestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          return ActionChip(
            label:
                Text(_quickQuestions[i], style: const TextStyle(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            onPressed: () => _sendMessage(_quickQuestions[i]),
          );
        },
      ),
    );
  }

  Widget _buildBubble(_HelpMessage msg, Color primary) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: msg.isUser ? primary : Colors.grey[100],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
        ),
        child: msg.isUser
            ? SelectableText(
                msg.text,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  height: 1.4,
                ),
              )
            : MarkdownBubble(
                content: msg.text,
                provider: msg.modelProvider,
                model: msg.modelName,
                textColor: Colors.black87,
                compact: true,
              ),
      ),
    );
  }

  Widget _buildTypingIndicator(Color primary) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: primary)),
            const SizedBox(width: 8),
            Text('正在思考...',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _HelpMessage {
  final String text;
  final bool isUser;
  final String? modelProvider;
  final String? modelName;
  const _HelpMessage(this.text, this.isUser,
      {this.modelProvider, this.modelName});
}
