import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_theme.dart';
import '../../../data/local/puml_dao.dart';
import '../../../data/models/puml_file_model.dart';
import '../../../services/ai_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/slide_generator_service.dart';
import '../../widgets/markdown_bubble.dart';

class AiAssistPage extends StatefulWidget {
  final String mode; // 'chat', 'script', 'uml'
  const AiAssistPage({super.key, this.mode = 'chat'});

  @override
  State<AiAssistPage> createState() => _AiAssistPageState();
}

class _AiAssistPageState extends State<AiAssistPage> {
  static const _diagramTypes = [
    'class',
    'sequence',
    'activity',
    'component',
    'usecase',
  ];

  static const _diagramTypeLabels = {
    'class': '类图',
    'sequence': '时序图',
    'activity': '活动图',
    'component': '组件图',
    'usecase': '用例图',
  };

  // 当前模式
  late String _mode;

  // 消息列表
  final List<_ChatMessage> _messages = [];

  // 控制器
  final _inputController = TextEditingController();
  final _topicController = TextEditingController();
  final _scrollController = ScrollController();

  // 状态
  bool _loading = false;
  String? _lastAiReply;
  String _courseName = '课程';
  List<String> _chapters = const ['第1章'];

  // 脚本/UML 模式参数
  String _selectedChapter = '第1章';
  String _selectedDiagramType = 'class';

  final AiService _aiService = AiService();
  final CourseContextService _courseContext = CourseContextService();
  final SlideGeneratorService _slideService = SlideGeneratorService();
  final PumlDao _pumlDao = PumlDao();

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _loadCourseContext();
    _addWelcomeMessage();
  }

  Future<void> _loadCourseContext() async {
    final courseName = await _courseContext.activeCourseName();
    final chapters = await _courseContext.shortChapterTitles();
    if (!mounted) return;
    setState(() {
      _courseName = courseName;
      _chapters = chapters.isEmpty ? const ['第1章'] : chapters;
      if (!_chapters.contains(_selectedChapter)) {
        _selectedChapter = _chapters.first;
      }
      _messages.clear();
      _addWelcomeMessage();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _topicController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── 初始化欢迎消息 ────────────────────────────────────────────────────────

  void _addWelcomeMessage() {
    final welcome = switch (_mode) {
      'script' =>
        '👋 你好！我是 AI 教学脚本助手。\n\n请选择章节并输入主题，我会为你生成适合视频讲解的教学脚本，包含时间节点标注，约 8-10 分钟讲解内容。',
      'uml' =>
        '👋 你好！我是 AI UML 助手。\n\n请选择图类型和章节，描述你想要绘制的内容，我将生成 PlantUML 代码供你直接渲染使用。',
      _ => '👋 你好！我是《$_courseName》课程 AI 助手。\n\n你可以问我课程概念、教学设计、题目解析、案例分析或学习建议。',
    };
    _messages.add(_ChatMessage(role: 'ai', content: welcome));
  }

  // ── 模式标题 ─────────────────────────────────────────────────────────────

  String get _modeTitle => switch (_mode) {
        'script' => '生成脚本',
        'uml' => '生成 UML',
        _ => 'AI 问答',
      };

  String get _modePlaceholder => switch (_mode) {
        'script' => '输入补充要求，或直接点击"生成脚本"…',
        'uml' => '描述图的具体内容（可选），或直接点击"生成 UML"…',
        _ => '输入你的问题…',
      };

  // ── 发送消息 ──────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();

    _addUserMessage(text);

    setState(() => _loading = true);
    try {
      final history = _messages
          .where((m) => m.role != 'loading')
          .map((m) => {
                'role': m.role == 'user' ? 'user' : 'assistant',
                'content': m.content
              })
          .toList();

      final systemPrompt = '你是一位《$_courseName》课程助手，回答必须围绕当前课程，'
          '表达清晰简洁；如课程内容涉及代码、模型、公式或流程，可给出适当示例。';

      final result =
          await _aiService.chatWithMeta(history, systemPrompt: systemPrompt);
      if (!mounted) return;
      _addAiMessage(result.content,
          modelProvider: result.provider, modelName: result.model);
      _lastAiReply = result.content;
    } catch (e) {
      if (!mounted) return;
      _addAiMessage('❌ $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 快捷生成（脚本模式） ──────────────────────────────────────────────────

  Future<void> _generateScript() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showSnack('请先输入主题');
      return;
    }

    final extra = _inputController.text.trim();
    _inputController.clear();

    final displayMsg =
        '生成脚本：$topic（$_selectedChapter）${extra.isNotEmpty ? '\n补充：$extra' : ''}';
    _addUserMessage(displayMsg);

    setState(() => _loading = true);
    try {
      final result = await _aiService.generateScript(
        topic,
        chapter: _selectedChapter,
        courseName: _courseName,
      );
      if (!mounted) return;
      _addAiMessage(result);
      _lastAiReply = result;
    } catch (e) {
      if (!mounted) return;
      _addAiMessage('❌ $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 快捷生成（UML模式） ───────────────────────────────────────────────────

  Future<void> _generateUml() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showSnack('请先输入主题/描述');
      return;
    }

    final displayMsg =
        '生成 ${_diagramTypeLabels[_selectedDiagramType]}：$topic（$_selectedChapter）';
    _addUserMessage(displayMsg);

    setState(() => _loading = true);
    try {
      final result = await _aiService.generatePuml(
        topic,
        diagramType: _selectedDiagramType,
      );
      if (!mounted) return;
      _addAiMessage(result, isCode: true);
      _lastAiReply = result;
    } catch (e) {
      if (!mounted) return;
      _addAiMessage('❌ $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 保存操作 ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_lastAiReply == null || _lastAiReply!.isEmpty) {
      _showSnack('暂无可保存的 AI 回复');
      return;
    }

    if (_mode == 'script') {
      final topic = _topicController.text.trim().isNotEmpty
          ? _topicController.text.trim()
          : '教学脚本';
      final result = await _slideService.saveScript(
        title: topic,
        script: _lastAiReply!,
        chapter: _selectedChapter,
      );
      if (!mounted) return;
      if (result != null) {
        _showSnack('✅ 脚本已保存到素材库', success: true);
      } else {
        _showSnack('❌ 保存失败，请重试');
      }
    } else if (_mode == 'uml') {
      final topic = _topicController.text.trim().isNotEmpty
          ? _topicController.text.trim()
          : 'AI 生成图';
      final puml = PumlFileModel(
        title: '$topic（$_selectedChapter）',
        content: _lastAiReply!,
        diagramType: _selectedDiagramType,
        chapter: _selectedChapter,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      try {
        await _pumlDao.insert(puml);
        if (!mounted) return;
        _showSnack('✅ UML 已保存到图谱库', success: true);
      } catch (e) {
        if (!mounted) return;
        _showSnack('❌ 保存失败：$e');
      }
    } else {
      // 聊天模式 — 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: _lastAiReply!));
      if (!mounted) return;
      _showSnack('✅ 已复制到剪贴板', success: true);
    }
  }

  // ── 消息管理 ──────────────────────────────────────────────────────────────

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
    });
    _scrollToBottom();
  }

  void _addAiMessage(String text,
      {bool isCode = false, String? modelProvider, String? modelName}) {
    setState(() {
      _messages.add(_ChatMessage(
          role: 'ai',
          content: text,
          isCode: isCode,
          modelProvider: modelProvider,
          modelName: modelName));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green.shade600 : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final gradient = AppGradientTheme.of(context).linearGradient;

    return Scaffold(
      appBar: AppBar(
        title: Text(_modeTitle),
        actions: [
          // 模式切换 PopupMenu
          PopupMenuButton<String>(
            icon: const Icon(Icons.swap_horiz_outlined),
            tooltip: '切换模式',
            initialValue: _mode,
            onSelected: (v) {
              if (v == _mode) return;
              setState(() {
                _mode = v;
                _messages.clear();
                _lastAiReply = null;
                _addWelcomeMessage();
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'chat', child: Text('🤖  AI 问答')),
              PopupMenuItem(value: 'script', child: Text('📝  生成脚本')),
              PopupMenuItem(value: 'uml', child: Text('🔷  生成 UML')),
            ],
          ),
          // 保存/复制按钮
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: _mode == 'chat' ? '复制最新回复' : '保存到素材库',
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          // 模式参数栏（脚本/UML专用）
          if (_mode == 'script') _buildScriptParamBar(primary, gradient),
          if (_mode == 'uml') _buildUmlParamBar(primary, gradient),

          // 消息列表
          Expanded(child: _buildMessageList(primary)),

          // 底部输入栏
          _buildInputBar(primary),
        ],
      ),
    );
  }

  // ── 脚本参数栏 ────────────────────────────────────────────────────────────

  Widget _buildScriptParamBar(Color primary, LinearGradient gradient) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        border:
            Border(bottom: BorderSide(color: primary.withValues(alpha: 0.15))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 章节
              Expanded(
                flex: 2,
                child: _buildDropdown(
                  value: _selectedChapter,
                  items: _chapters,
                  onChanged: (v) => setState(() => _selectedChapter = v!),
                  hint: '选择章节',
                ),
              ),
              const SizedBox(width: 10),
              // 主题输入
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _topicController,
                  decoration: InputDecoration(
                    hintText: '输入主题',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 生成按钮
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('生成脚本', style: TextStyle(fontSize: 12)),
                onPressed: _loading ? null : _generateScript,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── UML 参数栏 ────────────────────────────────────────────────────────────

  Widget _buildUmlParamBar(Color primary, LinearGradient gradient) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.05),
        border:
            Border(bottom: BorderSide(color: primary.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          // 图类型
          Expanded(
            flex: 2,
            child: _buildDropdown(
              value: _selectedDiagramType,
              items: _diagramTypes,
              labels: _diagramTypeLabels,
              onChanged: (v) => setState(() => _selectedDiagramType = v!),
              hint: '图类型',
            ),
          ),
          const SizedBox(width: 8),
          // 章节
          Expanded(
            flex: 2,
            child: _buildDropdown(
              value: _selectedChapter,
              items: _chapters,
              onChanged: (v) => setState(() => _selectedChapter = v!),
              hint: '章节',
            ),
          ),
          const SizedBox(width: 8),
          // 主题输入
          Expanded(
            flex: 3,
            child: TextField(
              controller: _topicController,
              decoration: InputDecoration(
                hintText: '图的主题/描述',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 生成按钮
          FilledButton.icon(
            icon: const Icon(Icons.account_tree_outlined, size: 16),
            label: const Text('生成', style: TextStyle(fontSize: 12)),
            onPressed: _loading ? null : _generateUml,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dropdown 通用 ─────────────────────────────────────────────────────────

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required void Function(String?) onChanged,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          items: items.map((item) {
            return DropdownMenuItem(
              value: item,
              child: Text(
                labels?[item] ?? item,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── 消息列表 ──────────────────────────────────────────────────────────────

  Widget _buildMessageList(Color primary) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _loading) {
          return _buildLoadingBubble();
        }
        final msg = _messages[index];
        return _buildMessageBubble(msg, primary);
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg, Color primary) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(isUser: false, primary: primary),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 16 : 4),
                      topRight: Radius.circular(isUser ? 4 : 16),
                      bottomLeft: const Radius.circular(16),
                      bottomRight: const Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isUser
                      ? SelectableText(
                          msg.content,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        )
                      : msg.isCode
                          ? _buildCodeContent(msg.content, isUser)
                          : MarkdownBubble(
                              content: msg.content,
                              provider: msg.modelProvider,
                              model: msg.modelName,
                              textColor:
                                  Theme.of(context).colorScheme.onSurface,
                              compact: true,
                            ),
                ),
                if (!isUser && msg.isCode)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制代码', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: msg.content));
                        _showSnack('已复制到剪贴板', success: true);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(isUser: true, primary: primary),
          ],
        ],
      ),
    );
  }

  Widget _buildCodeContent(String code, bool isUser) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(
        child: SelectableText(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
            color:
                isUser ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar({required bool isUser, required Color primary}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isUser
            ? primary.withValues(alpha: 0.15)
            : primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: isUser
              ? primary.withValues(alpha: 0.3)
              : primary.withValues(alpha: 0.2),
        ),
      ),
      child: Center(
        child: Text(
          isUser ? '我' : 'AI',
          style: TextStyle(
            fontSize: 11,
            color: primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(
              isUser: false, primary: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'AI 思考中…',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 底部输入栏 ────────────────────────────────────────────────────────────

  Widget _buildInputBar(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 模式 Chips（小提示）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _modeChip('🤖 问答', 'chat', primary),
                const SizedBox(width: 6),
                _modeChip('📝 脚本', 'script', primary),
                const SizedBox(width: 6),
                _modeChip('🔷 UML', 'uml', primary),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 输入行
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: _modePlaceholder,
                    hintStyle: const TextStyle(fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 8),
              // 发送按钮
              Material(
                color: primary,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _loading ? null : _sendMessage,
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, String mode, Color primary) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () {
        if (_mode == mode) return;
        setState(() {
          _mode = mode;
          _messages.clear();
          _lastAiReply = null;
          _addWelcomeMessage();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? primary : primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? primary : primary.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : primary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── 消息数据类 ─────────────────────────────────────────────────────────────────

class _ChatMessage {
  final String role; // 'user' | 'ai'
  final String content;
  final bool isCode;
  final String? modelProvider;
  final String? modelName;

  const _ChatMessage({
    required this.role,
    required this.content,
    this.isCode = false,
    this.modelProvider,
    this.modelName,
  });
}
