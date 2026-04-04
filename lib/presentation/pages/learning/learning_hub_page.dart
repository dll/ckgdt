import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/ai_service.dart';
import '../../../services/file_opener_service.dart';

/// 学习中心页面 — 合并原"视频"和"课件"菜单
/// 4 个 Tab：视频、PPT、PDF、AI助手
class LearningHubPage extends StatefulWidget {
  final int initialTab;

  const LearningHubPage({super.key, this.initialTab = 0});

  @override
  State<LearningHubPage> createState() => _LearningHubPageState();
}

class _LearningHubPageState extends State<LearningHubPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // 数据
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _pptFiles = [];
  List<Map<String, dynamic>> _pdfFiles = [];
  bool _videoLoading = true;
  bool _pptLoading = true;
  bool _pdfLoading = true;

  // AI 助手
  final List<_ChatMessage> _messages = [];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadVideos(),
      _loadPPTs(),
      _loadPDFs(),
    ]);
  }

  Future<void> _loadVideos() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['video'],
        orderBy: 'chapter',
      );
      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      if (!mounted) return;
      setState(() {
        _videos = sorted;
        _videoLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoLoading = false);
    }
  }

  Future<void> _loadPPTs() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['ppt'],
        orderBy: 'chapter',
      );
      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      if (!mounted) return;
      setState(() {
        _pptFiles = sorted;
        _pptLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pptLoading = false);
    }
  }

  Future<void> _loadPDFs() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final result = await db.query(
        'resource_files',
        where: 'file_type = ?',
        whereArgs: ['pdf'],
        orderBy: 'chapter',
      );
      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      if (!mounted) return;
      setState(() {
        _pdfFiles = sorted;
        _pdfLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pdfLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              setState(() {
                _videoLoading = true;
                _pptLoading = true;
                _pdfLoading = true;
              });
              _loadAllData();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primary,
          labelColor: primary,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(icon: const Icon(Icons.play_circle_outline), text: '视频 (${_videoLoading ? "..." : _videos.length})'),
            Tab(icon: const Icon(Icons.slideshow_outlined), text: 'PPT (${_pptLoading ? "..." : _pptFiles.length})'),
            Tab(icon: const Icon(Icons.picture_as_pdf_outlined), text: 'PDF (${_pdfLoading ? "..." : _pdfFiles.length})'),
            const Tab(icon: Icon(Icons.smart_toy_outlined), text: 'AI助手'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVideoTab(),
          _buildFileListTab(_pptFiles, _pptLoading, '🖼️', 'PPT', _loadPPTs),
          _buildFileListTab(_pdfFiles, _pdfLoading, '📄', 'PDF', _loadPDFs),
          _buildAiAssistTab(),
        ],
      ),
    );
  }

  // ── Tab 0：视频 ─────────────────────────────────────────────────────────────

  Widget _buildVideoTab() {
    if (_videoLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return _buildEmptyState(Icons.video_library, '暂无视频教程');
    }
    return RefreshIndicator(
      onRefresh: _loadVideos,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _videos.length,
        itemBuilder: (context, index) {
          final video = _videos[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.red,
                child: const Icon(Icons.play_arrow, color: Colors.white),
              ),
              title: Text(
                video['chapter'] ?? '视频',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('点击播放', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openFile(video),
            ),
          );
        },
      ),
    );
  }

  // ── Tab 1/2：PPT/PDF 文件列表 ──────────────────────────────────────────────

  Widget _buildFileListTab(
    List<Map<String, dynamic>> files,
    bool loading,
    String emoji,
    String type,
    Future<void> Function() onRefresh,
  ) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (files.isEmpty) {
      return _buildEmptyState(
        type == 'PPT' ? Icons.slideshow : Icons.picture_as_pdf,
        '暂无 $type 文件',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: files.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final file = files[index];
          final name = file['file_name'] as String? ?? '未命名';
          final chapter = file['chapter'] as String?;
          final desc = file['description'] as String?;

          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              [if (chapter != null) chapter, if (desc != null) desc].join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _openFile(file),
          );
        },
      ),
    );
  }

  // ── Tab 3：AI 助手 ─────────────────────────────────────────────────────────

  Widget _buildAiAssistTab() {
    final gradient = AppGradientTheme.of(context).linearGradient;

    return Column(
      children: [
        // 消息列表
        Expanded(
          child: _messages.isEmpty
              ? _buildAiWelcome(gradient)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return _buildMessageBubble(msg);
                  },
                ),
        ),

        // 输入区域
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
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
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: '输入问题，如：移动开发的技术栈有哪些？',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: _aiLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  onPressed: _aiLoading ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiWelcome(LinearGradient gradient) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text(
            'AI 学习助手',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '随时向我提问关于移动应用开发的问题',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 32),
          // 快捷问题
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildQuickQuestion('移动开发有哪些主流框架？'),
              _buildQuickQuestion('Flutter和React Native的区别？'),
              _buildQuickQuestion('如何搭建Android开发环境？'),
              _buildQuickQuestion('鸿蒙开发入门指南'),
              _buildQuickQuestion('跨平台开发的优缺点？'),
              _buildQuickQuestion('微信小程序开发流程'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickQuestion(String question) {
    return ActionChip(
      label: Text(question, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _inputController.text = question;
        _sendMessage();
      },
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.smart_toy, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: SelectableText(
                msg.text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey.shade300,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _aiLoading) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _inputController.clear();
      _aiLoading = true;
    });
    _scrollToBottom();

    try {
      final aiService = AiService();
      final reply = await aiService.chat(
        '你是一个移动应用开发课程的AI学习助手，帮助学生解答关于Android、iOS、Flutter、'
        'React Native、微信小程序、鸿蒙等移动开发技术的问题。请用中文简洁回答。\n\n'
        '学生问题：$text',
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: reply, isUser: false));
        _aiLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          text: '抱歉，AI 服务暂时不可用。请检查 AI 设置中的 API Key 配置。\n\n错误：$e',
          isUser: false,
        ));
        _aiLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── 通用工具 ──────────────────────────────────────────────────────────────

  void _openFile(Map<String, dynamic> file) {
    final filePath = file['file_path'] as String? ?? '';
    final fileName = file['file_name'] as String? ?? '${file['chapter']}';
    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件路径未设置')),
      );
      return;
    }
    FileOpenerService.openFile(context, filePath, fileName);
  }

  Widget _buildEmptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}
