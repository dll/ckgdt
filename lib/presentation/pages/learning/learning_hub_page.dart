import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/design/noir_tokens.dart';
import '../../widgets/noir_page_shell.dart';
import '../../../core/constants/chapter_sorter.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/ai_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/course_context_service.dart';
import '../../../services/courseware_service.dart';
import '../../../services/slide_generator_service.dart';
import '../../../services/file_opener_service.dart';
import '../../../services/courseware_download_service.dart';
import '../../../data/local/ai_config_dao.dart';
import '../materials/courseware_workshop_page.dart';
import '../materials/ai_settings_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/error_handler.dart';
import '../../../data/local/hot_video_dao.dart';
import '../../widgets/agent_entry_button.dart';
import '../../widgets/inner_tab_request_mixin.dart';
import '../../widgets/markdown_bubble.dart';
import '../admin/data_import_page.dart';
import '../quiz/quiz_page.dart';
import 'video_player_page.dart';
import 'pdf_viewer_page.dart';

/// 学习中心页面 — 合并原"视频"和"课件"菜单
/// 4 个 Tab：视频、PPT、PDF、AI助手
class LearningHubPage extends StatefulWidget {
  final int initialTab;

  const LearningHubPage({super.key, this.initialTab = 0});

  @override
  State<LearningHubPage> createState() => _LearningHubPageState();
}

class _LearningHubPageState extends State<LearningHubPage>
    with TickerProviderStateMixin, InnerTabRequestMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _courseContext = CourseContextService();

  bool get _isTeacherOrAdmin => _authService.isTeacher || _authService.isAdmin;

  // 数据
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _pptFiles = [];
  List<Map<String, dynamic>> _pdfFiles = [];
  bool _videoLoading = true;
  bool _pptLoading = true;
  bool _pdfLoading = true;

  // 资源模式：全部 / 预制 / 扩展 / 推荐
  String _resourceMode = 'all'; // 'all', 'preset', 'extended', 'recommend'

  // AI 推荐视频
  bool _recommendLoading = false;
  List<Map<String, dynamic>> _recommendedVideos = [];
  String? _recommendError;

  // AI 助手
  final List<_ChatMessage> _messages = [];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _aiLoading = false;
  String _aiProviderLabel = 'DeepSeek';
  String _aiModel = 'deepseek-v4-pro';
  String _courseName = '课程';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadAllData();
    bindInnerTabRequest();
  }

  @override
  String get innerTabPageKey => 'learning';
  @override
  String get innerTabSpeakLabel => '学习';
  @override
  TabController get innerTabController => _tabController;
  @override
  List<String> innerTabLabels() => const ['视频', 'PPT', 'PDF', '测验', '助手'];

  @override
  void dispose() {
    unbindInnerTabRequest();
    _tabController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadCourseContext(),
      _loadVideos(),
      _loadPPTs(),
      _loadPDFs(),
      _loadAiConfig(),
    ]);
  }

  Future<void> _loadCourseContext() async {
    try {
      final courseName = await _courseContext.activeCourseName(fallback: '课程');
      if (!mounted) return;
      setState(() => _courseName = courseName);
    } catch (e, st) {
      swallowDebug(e, tag: 'LearningHub.loadCourseContext', stack: st);
    }
  }

  Future<void> _loadVideos() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final whereParts = <String>['file_type = ?'];
      final whereArgs = <Object?>['video'];
      if (_resourceMode == 'preset') {
        whereParts.add("(source_type = 'preset' OR source_type IS NULL)");
      } else if (_resourceMode == 'extended') {
        whereParts.add("source_type = 'extended'");
      }
      final scope = await _courseContext.scopedWhere(
        extraWhere: whereParts.join(' AND '),
        extraArgs: whereArgs,
      );
      final result = await db.query(
        'resource_files',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'chapter',
      );
      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      if (!mounted) return;
      setState(() {
        _videos = sorted;
        _videoLoading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'LearningHub.loadVideos', stack: st);
      if (!mounted) return;
      setState(() => _videoLoading = false);
    }
  }

  Future<void> _loadPPTs() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final whereParts = <String>['file_type = ?'];
      final whereArgs = <Object?>['ppt'];
      if (_resourceMode == 'preset') {
        whereParts.add("(source_type = 'preset' OR source_type IS NULL)");
      } else if (_resourceMode == 'extended') {
        whereParts.add("source_type = 'extended'");
      }
      final scope = await _courseContext.scopedWhere(
        extraWhere: whereParts.join(' AND '),
        extraArgs: whereArgs,
      );
      final result = await db.query(
        'resource_files',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'chapter',
      );
      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      if (!mounted) return;
      setState(() {
        _pptFiles = sorted;
        _pptLoading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'LearningHub.loadPPTs', stack: st);
      if (!mounted) return;
      setState(() => _pptLoading = false);
    }
  }

  Future<void> _loadPDFs() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final whereParts = <String>['file_type = ?'];
      final whereArgs = <Object?>['pdf'];
      if (_resourceMode == 'preset') {
        whereParts.add("(source_type = 'preset' OR source_type IS NULL)");
      } else if (_resourceMode == 'extended') {
        whereParts.add("source_type = 'extended'");
      }
      final scope = await _courseContext.scopedWhere(
        extraWhere: whereParts.join(' AND '),
        extraArgs: whereArgs,
      );
      final result = await db.query(
        'resource_files',
        where: scope.where,
        whereArgs: scope.args,
        orderBy: 'chapter',
      );
      final sorted = List<Map<String, dynamic>>.from(result);
      ChapterSorter.sortByChapter(sorted);
      if (!mounted) return;
      setState(() {
        _pdfFiles = sorted;
        _pdfLoading = false;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'LearningHub.loadPDFs', stack: st);
      if (!mounted) return;
      setState(() => _pdfLoading = false);
    }
  }

  Future<void> _loadAiConfig() async {
    try {
      final config = await AiConfigDao().getConfig();
      if (!mounted) return;
      setState(() {
        _aiProviderLabel = config.providerLabel;
        _aiModel = config.model;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'LearningHub.loadAiConfig', stack: st);
    }
  }

  /// 加载推荐视频（DB 已有 + AI 推荐）
  Future<void> _loadRecommendedVideos() async {
    setState(() => _recommendLoading = true);
    try {
      final dao = HotVideoDao();
      final videos = await dao.getVideos(sortBy: 'latest', limit: 30);
      if (!mounted) return;
      setState(() {
        _recommendedVideos = videos.map((v) => v.toMap()).toList();
        _recommendLoading = false;
        _recommendError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recommendLoading = false;
        _recommendError = '加载推荐视频失败';
      });
    }
  }

  /// AI 智能推荐视频 — 从现有视频池中筛选最相关的推荐
  Future<void> _aiRecommendVideos() async {
    setState(() {
      _recommendLoading = true;
      _recommendError = null;
    });

    try {
      // 1. 加载视频池
      final dao = HotVideoDao();
      final allVideos = await dao.getVideos(sortBy: 'latest', limit: 50);
      if (allVideos.isEmpty) {
        if (mounted)
          setState(() {
            _recommendLoading = false;
            _recommendError = '视频池为空，请先添加视频';
          });
        return;
      }

      // 2. 构建视频列表给AI选择
      final buffer = StringBuffer();
      for (var i = 0; i < allVideos.length; i++) {
        final v = allVideos[i];
        buffer.writeln('[$i] ${v.title} — ${v.source}');
        if (v.description != null && v.description!.isNotEmpty) {
          buffer.writeln('   简介：${v.description}');
        }
        buffer.writeln('   平台：${v.platform}');
      }

      final courseName = await _courseContext.activeCourseName(fallback: '课程');

      // 3. AI从视频池中筛选最相关的当前课程视频
      final aiService = AiService();
      final result = await aiService.chat(
        [
          {
            'role': 'user',
            'content': '以下是视频池中的所有视频。请从中选出与"$courseName"最相关的8个高质量教学视频，'
                '返回所选视频的索引号JSON数组（仅返回数组，不要其他文字）：\n\n${buffer.toString()}'
          },
        ],
        systemPrompt:
            '你是$courseName课程的教学助手。请从视频池中选择最相关的教学视频。只返回JSON数组，如[0,3,5,7,2,9,1,4]。',
      );

      // 4. 解析AI返回的索引
      final match = RegExp(r'\[[\d,\s]*\]').firstMatch(result);
      if (match == null) {
        if (mounted)
          setState(() {
            _recommendLoading = false;
            _recommendError = 'AI 未返回有效筛选结果';
          });
        return;
      }

      final List<dynamic> indices =
          jsonDecode(match.group(0)!) as List<dynamic>;
      final allMaps = allVideos.map((v) => v.toMap()).toList();
      final filtered = <Map<String, dynamic>>[];
      for (final idx in indices) {
        final i = (idx as num).toInt();
        if (i >= 0 && i < allMaps.length) {
          filtered.add({...allMaps[i], 'is_ai_recommended': true});
        }
      }

      if (!mounted) return;
      setState(() {
        _recommendedVideos = filtered.isNotEmpty ? filtered : allMaps;
        _recommendLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recommendLoading = false;
        _recommendError = 'AI 推荐失败，请检查API配置后重试';
      });
    }
  }

  /// 推荐模式下的视频网格
  Widget _buildRecommendGrid() {
    if (_recommendLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_recommendError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(_recommendError!,
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadRecommendedVideos,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_recommendedVideos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('还没有推荐视频',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('点击右下角按钮让 AI 为你推荐',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : (constraints.maxWidth > 600 ? 3 : 2);
        final cardWidth =
            (constraints.maxWidth - (crossAxisCount + 1) * 12) / crossAxisCount;
        final cardHeight = cardWidth * 0.85 + 56;

        return Column(
          children: [
            // AI 推荐按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: Colors.purple.shade400),
                  const SizedBox(width: 6),
                  Text('推荐视频',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 14),
                    label:
                        const Text('AI 智能推荐', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _aiRecommendVideos,
                  ),
                ],
              ),
            ),
            // 视频网格
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: cardWidth / cardHeight,
                ),
                itemCount: _recommendedVideos.length,
                itemBuilder: (context, index) {
                  final v = _recommendedVideos[index];
                  return _RecommendVideoCard(video: v);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NoirTokens.ink,
      appBar: AppBar(
        backgroundColor: NoirTokens.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: NoirTokens.paper),
        title: Text(_isTeacherOrAdmin ? '教学资源管理' : '学习',
            style: const TextStyle(color: NoirTokens.paper)),
        actions: [
          if (_isTeacherOrAdmin) ...[
            IconButton(
              icon: const Icon(Icons.movie_creation_outlined),
              tooltip: '课件工坊',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CoursewareWorkshopPage()),
              ).then((_) => _loadAllData()),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: '资源管理',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DataImportPage()),
              ).then((_) => _loadAllData()),
            ),
          ],
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
          const AgentEntryButton(agentId: 'learning'),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: NoirTokens.accent,
          indicatorWeight: 2,
          labelColor: NoirTokens.paper,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5),
          unselectedLabelColor: NoirTokens.paper.withValues(alpha: 0.5),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: [
            Tab(
                icon: const Icon(Icons.play_circle_outline),
                text: '视频 (${_videoLoading ? "..." : _videos.length})'),
            Tab(
                icon: const Icon(Icons.slideshow_outlined),
                text: 'PPT (${_pptLoading ? "..." : _pptFiles.length})'),
            Tab(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                text: 'PDF (${_pdfLoading ? "..." : _pdfFiles.length})'),
            const Tab(icon: Icon(Icons.quiz_outlined), text: '测验'),
            const Tab(icon: Icon(Icons.assistant_outlined), text: '助手'),
          ],
        ),
      ),
      body: NoirBackground(
        child: Column(
          children: [
            // 预制/扩展 过滤条
            _buildResourceModeBar(),
            if (_resourceMode == 'recommend')
              Expanded(child: _buildRecommendGrid())
            else
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildVideoTab(),
                    _buildFileListTab(
                        _pptFiles, _pptLoading, '🖼️', 'PPT', _loadPPTs),
                    _buildFileListTab(
                        _pdfFiles, _pdfLoading, '📄', 'PDF', _loadPDFs),
                    const QuizPage(embedded: true),
                    _buildAiAssistTab(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 预制/扩展 过滤条 ─────────────────────────────────────────────────────
  Widget _buildResourceModeBar() {
    // 只在视频/PPT/PDF Tab 显示（索引 0-2）
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final tabIndex = _tabController.index;
        if (tabIndex > 2) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: NoirTokens.inkAlpha(0.08),
            border: Border(
              bottom:
                  BorderSide(color: NoirTokens.paper.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.filter_list,
                  size: 16, color: NoirTokens.paper.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('全部')),
                  ButtonSegment(value: 'preset', label: Text('预制')),
                  ButtonSegment(value: 'extended', label: Text('扩展')),
                  ButtonSegment(value: 'recommend', label: Text('推荐')),
                ],
                selected: {_resourceMode},
                onSelectionChanged: (Set<String> newSelection) {
                  final mode = newSelection.first;
                  setState(() {
                    _resourceMode = mode;
                    if (mode != 'recommend') {
                      _videoLoading = true;
                      _pptLoading = true;
                      _pdfLoading = true;
                    }
                  });
                  if (mode == 'recommend') {
                    _tabController.animateTo(0); // 切换到视频 Tab
                    _loadRecommendedVideos();
                  } else {
                    _loadAllData();
                  }
                },
                style: ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const Spacer(),
              if (_resourceMode == 'extended') ...[
                TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('生成课件', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: _generateExtendedResources,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.cleaning_services, size: 14),
                  label: const Text('清理', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                    foregroundColor: NoirTokens.paper.withValues(alpha: 0.5),
                  ),
                  onPressed: _cleanupEmptyExtended,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 清理空路径的扩展资源条目
  Future<void> _cleanupEmptyExtended() async {
    final db = await DatabaseHelper.instance.database;
    final scope = await _courseContext.scopedWhere(
      extraWhere:
          "source_type = 'extended' AND (file_path IS NULL OR file_path = '')",
    );
    final count = await db.rawQuery(
      'SELECT COUNT(*) as c FROM resource_files WHERE ${scope.where}',
      scope.args,
    );
    final emptyCount = count.first['c'] as int? ?? 0;

    if (emptyCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要清理的空条目')),
      );
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理空条目'),
        content: Text('发现 $emptyCount 条未生成文件的扩展资源条目。\n\n删除后不影响已生成的课件文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await db.delete(
      'resource_files',
      where: scope.where,
      whereArgs: scope.args,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已清理 $emptyCount 条空条目'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _videoLoading = true;
      _pptLoading = true;
      _pdfLoading = true;
    });
    _loadAllData();
  }

  /// 打开扩展课件生成对话框（用户自定义输入）
  void _generateExtendedResources() {
    // 根据当前 Tab 决定默认类型
    String defaultType = 'pdf';
    if (_tabController.index == 0) defaultType = 'video';
    if (_tabController.index == 1) defaultType = 'ppt';
    if (_tabController.index == 2) defaultType = 'pdf';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExtendedCoursewareSheet(
        defaultType: defaultType,
        onGenerated: () {
          setState(() {
            _videoLoading = true;
            _pptLoading = true;
            _pdfLoading = true;
          });
          _loadAllData();
        },
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
          final isExtended = video['source_type'] == 'extended';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isExtended ? Colors.purple : Colors.red,
                child: Icon(
                  isExtended ? Icons.auto_awesome : Icons.play_arrow,
                  color: Colors.white,
                ),
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
          final isExtended = file['source_type'] == 'extended';

          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    isExtended ? Colors.purple.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: isExtended
                    ? const Icon(Icons.auto_awesome,
                        size: 22, color: Colors.purple)
                    : Text(emoji, style: const TextStyle(fontSize: 24)),
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
        // 工具栏：模型指示器 + 操作按钮
        _buildAiToolbar(),

        // 快捷提问（消息列表非空时显示为紧凑条）
        if (_messages.isNotEmpty) _buildQuickPromptBar(),

        // 消息列表
        Expanded(
          child: _messages.isEmpty
              ? _buildAiWelcome(gradient)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length + (_aiLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _aiLoading) {
                      return _buildTypingIndicator();
                    }
                    return _buildMessageBubble(_messages[index]);
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

  /// AI 工具栏：模型指示 + 新会话 + 设置
  Widget _buildAiToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // 模型指示器
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy,
                    size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  _aiProviderLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _aiModel,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),

          const Spacer(),

          // 新会话
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新会话', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () {
              setState(() => _messages.clear());
            },
          ),

          // 清空
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '清空对话',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: _messages.isEmpty
                ? null
                : () {
                    setState(() => _messages.clear());
                  },
          ),

          // AI 设置
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: 'AI 设置',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiSettingsPage()),
              ).then((_) => _loadAiConfig());
            },
          ),
        ],
      ),
    );
  }

  /// 快捷提问条（对话进行中时显示）
  Widget _buildQuickPromptBar() {
    final prompts = [
      '${_courseName}核心知识点',
      '${_courseName}学习路线',
      '${_courseName}常见难点',
      '${_courseName}案例分析',
      '${_courseName}复习提纲',
      '${_courseName}章节测验建议',
    ];

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: prompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(prompts[index], style: const TextStyle(fontSize: 11)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: () {
              _inputController.text = prompts[index];
              _sendMessage();
            },
          );
        },
      ),
    );
  }

  /// "正在思考" 打字指示器
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.smart_toy, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '正在思考...',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
          Text(
            '随时向我提问关于$_courseName的问题',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 32),
          // 快捷问题
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildQuickQuestion('${_courseName}的核心知识体系是什么？'),
              _buildQuickQuestion('${_courseName}有哪些常见难点？'),
              _buildQuickQuestion('请生成$_courseName复习提纲'),
              _buildQuickQuestion('请设计$_courseName实践任务'),
              _buildQuickQuestion('如何准备$_courseName章节测验？'),
              _buildQuickQuestion('请举例说明$_courseName典型应用'),
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
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  child: isUser
                      ? SelectableText(
                          msg.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.5,
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
                const SizedBox(height: 2),
                Text(
                  msg.timeLabel,
                  style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                ),
              ],
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

      // 构建完整对话历史（最多保留最近 20 轮）
      final history = <Map<String, String>>[];
      final startIdx = _messages.length > 40 ? _messages.length - 40 : 0;
      for (int i = startIdx; i < _messages.length; i++) {
        history.add({
          'role': _messages[i].isUser ? 'user' : 'assistant',
          'content': _messages[i].text,
        });
      }

      final courseName = await _courseContext.activeCourseName(fallback: '课程');
      final result = await aiService.chatWithMeta(
        history,
        systemPrompt:
            '你是$courseName课程的AI学习助手，帮助学生围绕该课程的概念、案例、实践和测验进行学习。请用中文简洁回答。'
            '回答时可使用 Markdown 格式（标题、列表、代码块等）使内容更清晰。',
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          text: result.content,
          isUser: false,
          modelProvider: result.provider,
          modelName: result.model,
        ));
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

  /// 根据文件类型路由到应用内播放器
  void _openWithInAppViewer(String filePath, String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

    if (['mp4', 'avi', 'mov', 'wmv', 'mkv', 'flv'].contains(ext)) {
      // Android 无 media_kit 原生库，走系统播放器
      if (Platform.isAndroid || Platform.isIOS) {
        FileOpenerService.openExternalFile(context, filePath);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InAppVideoPlayerPage(
            filePath: filePath,
            title: fileName,
          ),
        ),
      );
    } else if (ext == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InAppPdfViewerPage(
            filePath: filePath,
            title: fileName,
          ),
        ),
      );
    } else if (['ppt', 'pptx'].contains(ext)) {
      // PPT/PPTX → 使用系统默认应用（PowerPoint/WPS/手机Office）打开
      // 自定义 XML 解析器无法忠实还原原始 PPT 排版
      FileOpenerService.openExternalFile(context, filePath);
    } else {
      // DOC 等其他格式 → 使用系统工具打开
      FileOpenerService.openExternalFile(context, filePath);
    }
  }

  void _openFile(Map<String, dynamic> file) async {
    final filePath = file['file_path'] as String? ?? '';
    final fileName = file['file_name'] as String? ?? '${file['chapter']}';
    final fileType = file['file_type'] as String? ?? '';
    final chapter = file['chapter'] as String? ?? '';
    final isExtended = file['source_type'] == 'extended';

    if (filePath.isEmpty) {
      if (isExtended) {
        // 扩展资源无文件 → 提供生成选项
        _showGenerateForExtendedItem(file);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件路径未设置')),
        );
      }
      return;
    }

    // 本地文件存在 → 直接打开
    if (!kIsWeb) {
      final localFile = File(filePath);
      if (await localFile.exists()) {
        if (!mounted) return;
        _openWithInAppViewer(filePath, fileName);
        return;
      }
    }

    // 本地不存在 → 检查是否可远程下载
    if (!mounted) return;

    if (!CoursewareDownloadService.isRemoteAvailable(fileType)) {
      // 该类型不支持远程下载
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(CoursewareDownloadService.getLocalOnlyMessage(fileType)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    await _downloadAndOpen(
      filePath: filePath,
      fileName: fileName,
      fileType: fileType,
      chapter: chapter,
    );
  }

  /// 显示下载进度对话框并从 Gitee 下载文件
  Future<void> _downloadAndOpen({
    required String filePath,
    required String fileName,
    required String fileType,
    required String chapter,
  }) async {
    final downloadService = CoursewareDownloadService();
    double progress = 0.0;
    bool cancelled = false;

    // 显示下载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('下载课件'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '正在从 Gitee 仓库下载...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 8),
                  if (progress > 0)
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );

    // 开始下载
    final resultPath = await downloadService.getLocalOrDownload(
      localPath: filePath,
      fileType: fileType,
      chapter: chapter,
      fileName: fileName,
      onProgress: (p) {
        progress = p;
        // Dialog 已通过 StatefulBuilder 管理，此处无法直接更新
        // 但进度在后台记录，用于日志
      },
    );

    if (cancelled || !mounted) return;

    // 关闭下载对话框
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (resultPath != null) {
      if (!mounted) return;
      _openWithInAppViewer(resultPath, fileName);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下载失败: $fileName\n请检查网络连接或联系管理员'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// 点击空路径扩展资源时 → 提供即时生成
  void _showGenerateForExtendedItem(Map<String, dynamic> file) {
    final chapter = file['chapter'] as String? ?? '扩展课件';
    final fileType = file['file_type'] as String? ?? 'pdf';
    final fileId = file['id'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(chapter,
                  style: const TextStyle(fontSize: 16),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Text(
          fileType == 'video'
              ? '该扩展视频尚未生成实际文件。\n\n建议前往「课件工坊」生成包含该主题的教学视频，或删除此占位条目。'
              : '该扩展课件尚未生成实际文件。\n\n点击「生成课件」将基于该主题，使用 AI 自动生成 PDF 课件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          if (fileId != null)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final db = await DatabaseHelper.instance.database;
                await db.delete('resource_files',
                    where: 'id = ?', whereArgs: [fileId]);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已删除占位条目')),
                );
                setState(() {
                  _videoLoading = true;
                  _pptLoading = true;
                  _pdfLoading = true;
                });
                _loadAllData();
              },
              child: const Text('删除条目', style: TextStyle(color: Colors.red)),
            ),
          if (fileType != 'video')
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _generateCoursewareForItem(file);
              },
              child: const Text('生成课件'),
            ),
        ],
      ),
    );
  }

  /// 为已有的扩展条目即时生成 PDF 课件
  Future<void> _generateCoursewareForItem(Map<String, dynamic> file) async {
    final chapter = file['chapter'] as String? ?? '扩展课件';
    final fileId = file['id'];

    // 显示生成进度
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在为「$chapter」生成课件...', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Text('AI 正在生成内容，请稍候',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );

    try {
      final aiService = AiService();
      final slideGen = SlideGeneratorService();

      final courseName = await _courseContext.activeCourseName(fallback: '课程');

      // 使用 SlideGeneratorService 生成 PDF
      final material = await slideGen.generateFromAI(
        aiService: aiService,
        topic: '$courseName - $chapter',
        chapter: chapter,
        slideCount: 10,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 关闭进度对话框

      if (material != null && material.filePath != null) {
        // 更新 resource_files 记录的 file_path
        if (fileId != null) {
          final db = await DatabaseHelper.instance.database;
          await db.update(
            'resource_files',
            {'file_path': material.filePath},
            where: 'id = ?',
            whereArgs: [fileId],
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('课件「$chapter」生成成功！'),
            backgroundColor: Colors.green,
          ),
        );

        // 刷新并打开文件
        setState(() {
          _pptLoading = true;
          _pdfLoading = true;
        });
        _loadAllData();
        _openWithInAppViewer(material.filePath!, '$chapter.pdf');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('课件生成失败，请检查 AI 配置'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('生成失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
          const SizedBox(height: 8),
          Text(
            '课件将从 Gitee 仓库自动获取',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  final String? modelProvider;
  final String? modelName;

  _ChatMessage(
      {required this.text,
      required this.isUser,
      DateTime? time,
      this.modelProvider,
      this.modelName})
      : time = time ?? DateTime.now();

  String get timeLabel {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 扩展课件生成表单 — 用户自定义输入，AI 动态生成实际 PDF 课件
// ═══════════════════════════════════════════════════════════════════════════════

class _ExtendedCoursewareSheet extends StatefulWidget {
  final String defaultType;
  final VoidCallback onGenerated;

  const _ExtendedCoursewareSheet({
    required this.defaultType,
    required this.onGenerated,
  });

  @override
  State<_ExtendedCoursewareSheet> createState() =>
      _ExtendedCoursewareSheetState();
}

class _ExtendedCoursewareSheetState extends State<_ExtendedCoursewareSheet> {
  final _courseContext = CourseContextService();
  final _topicCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();
  late String _selectedType;
  String? _selectedChapter;
  int _slideCount = 10;
  bool _isGenerating = false;
  String _progress = '';
  final List<String> _logs = [];

  // 当前课程信息
  String _courseName = '';
  String _courseId = '';
  List<String> _chapters = [];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.defaultType;
    _loadCourseInfo();
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCourseInfo() async {
    try {
      final course = await _courseContext.getActiveCourse();
      final chapters = await _courseContext.chapterTitles();
      if (!mounted) return;
      setState(() {
        _courseName = course.name;
        _courseId = course.id;
        _chapters = chapters;
      });
    } catch (e, st) {
      swallowDebug(e, tag: 'LearningHub.loadCourseInfo', stack: st);
    }
  }

  void _log(String msg) {
    if (!mounted) return;
    setState(() {
      _logs.add(msg);
      _progress = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomPadding + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖拽手柄
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 标题
            Text('生成扩展课件',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              '根据您的需求，AI 将生成实际的 PDF 课件文件',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 课件主题（必填）
            TextField(
              controller: _topicCtrl,
              decoration: InputDecoration(
                labelText: '课件主题 *',
                hintText: '例如：需求分析方法与建模实践',
                prefixIcon: const Icon(Icons.topic),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              enabled: !_isGenerating,
            ),
            const SizedBox(height: 16),

            // 所属章节（可选）
            DropdownButtonFormField<String>(
              value: _selectedChapter,
              decoration: InputDecoration(
                labelText: '关联章节（可选）',
                prefixIcon: const Icon(Icons.bookmark),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('不关联章节')),
                ..._chapters.map((ch) => DropdownMenuItem(
                      value: ch,
                      child: Text(ch,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: _isGenerating
                  ? null
                  : (v) => setState(() => _selectedChapter = v),
            ),
            const SizedBox(height: 16),

            // 资源类型
            Row(
              children: [
                const Icon(Icons.category, size: 20),
                const SizedBox(width: 8),
                const Text('课件类型：'),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pdf', label: Text('PDF')),
                      ButtonSegment(value: 'ppt', label: Text('PPT')),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: _isGenerating
                        ? null
                        : (s) => setState(() => _selectedType = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 幻灯片数量
            Row(
              children: [
                const Icon(Icons.format_list_numbered, size: 20),
                const SizedBox(width: 8),
                Text('页数：', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Slider(
                    value: _slideCount.toDouble(),
                    min: 6,
                    max: 20,
                    divisions: 14,
                    label: '$_slideCount 页',
                    onChanged: _isGenerating
                        ? null
                        : (v) => setState(() => _slideCount = v.toInt()),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$_slideCount',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 额外要求（可选）
            TextField(
              controller: _extraCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '额外要求（可选）',
                hintText: '例如：侧重实战案例，包含代码示例，难度为进阶级...',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.edit_note),
                ),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              enabled: !_isGenerating,
            ),
            const SizedBox(height: 24),

            // 生成进度
            if (_isGenerating || _logs.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(maxHeight: 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isGenerating)
                      Row(children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_progress,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              )),
                        ),
                      ]),
                    if (_logs.isNotEmpty) ...[
                      if (_isGenerating) const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          reverse: true,
                          itemCount: _logs.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              _logs[_logs.length - 1 - i],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 生成按钮
            FilledButton.icon(
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isGenerating ? '生成中...' : '开始生成课件'),
              onPressed: _isGenerating ? null : _doGenerate,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doGenerate() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入课件主题')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _logs.clear();
    });

    try {
      final aiService = AiService();
      final db = await DatabaseHelper.instance.database;
      final courseName = _courseName.isNotEmpty ? _courseName : '课程';
      final chapter = _selectedChapter ?? topic;
      final extra = _extraCtrl.text.trim();

      if (_selectedType == 'pdf') {
        await _generatePdf(
          aiService: aiService,
          db: db,
          topic: topic,
          courseName: courseName,
          chapter: chapter,
          extra: extra,
        );
      } else {
        await _generatePptPdf(
          aiService: aiService,
          db: db,
          topic: topic,
          courseName: courseName,
          chapter: chapter,
          extra: extra,
        );
      }

      widget.onGenerated();

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _log('生成失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  /// 使用 CoursewareService 生成增强版 PDF（教案驱动）
  Future<void> _generatePdf({
    required AiService aiService,
    required dynamic db,
    required String topic,
    required String courseName,
    required String chapter,
    required String extra,
  }) async {
    final coursewareService = CoursewareService();

    // Step 1: 生成教案
    _log('正在生成教案...');
    final lessonPlan = await coursewareService.generateLessonPlan(
      topic: topic,
      chapter: _selectedChapter,
      classHours: (_slideCount / 5).ceil().clamp(1, 4),
      additionalRequirements: extra.isNotEmpty
          ? '课程：$courseName。$extra'
          : '课程：$courseName。请确保内容专业、实用、包含代码示例和实践案例。',
    );
    _log('教案生成完成：${lessonPlan['title'] ?? topic}');

    // Step 2: 生成 PDF
    _log('正在生成 PDF 课件...');
    final pdfPath = await coursewareService.generateEnhancedPdf(
      lessonPlan: lessonPlan,
    );

    if (pdfPath == null) throw Exception('PDF 生成失败');
    _log('PDF 生成成功');

    // Step 3: 写入 resource_files 表
    _log('正在保存到资源库...');
    final safeName = topic.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    await db.insert('resource_files', {
      'course_id': _courseId.isNotEmpty
          ? _courseId
          : await _courseContext.activeCourseId(),
      'file_name': '扩展-$safeName.pdf',
      'file_path': pdfPath,
      'file_type': 'pdf',
      'chapter': chapter,
      'description': '${lessonPlan['objectives']?.take(2).join('；') ?? topic}',
      'source_type': 'extended',
    });
    _log('课件「$topic」生成完成！');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('扩展课件「$topic」(PDF) 生成成功！'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// PPT 类型：使用 SlideGeneratorService 生成 PDF 格式课件
  Future<void> _generatePptPdf({
    required AiService aiService,
    required dynamic db,
    required String topic,
    required String courseName,
    required String chapter,
    required String extra,
  }) async {
    final slideGen = SlideGeneratorService();

    // Step 1: AI 生成幻灯片内容
    _log('正在生成幻灯片内容（$_slideCount 页）...');

    final systemPrompt = '''你是一位资深的${courseName}课程讲师，擅长制作清晰、结构化的教学课件。
请用中文回复，回复必须是合法的 JSON 数组。
${extra.isNotEmpty ? '额外要求：$extra' : ''}''';

    final slidePrompt = '''
请为「$topic」${_selectedChapter != null ? '（$_selectedChapter）' : ''}生成 $_slideCount 张幻灯片的内容。

课程：$courseName

要求：
- 返回 JSON 数组，每项格式：{"title":"标题","bullets":["要点1","要点2","要点3"],"notes":"讲师备注"}
- 每张幻灯片 3-5 个要点，要点简洁（<=30字）
- 内容覆盖：背景介绍、核心概念、技术细节、代码示例说明、实践要点、总结
- 内容应专业深入，超越基础知识，体现"扩展"价值
- 仅返回 JSON，不要包含其他文字''';

    final raw = await aiService.chat(
      [
        {'role': 'user', 'content': slidePrompt}
      ],
      systemPrompt: systemPrompt,
    );

    // 解析 JSON 数组
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (jsonMatch == null) throw Exception('AI 返回格式不正确');

    final slides = (jsonDecode(jsonMatch.group(0)!) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    _log('幻灯片内容生成完成：${slides.length} 页');

    // Step 2: 生成 PDF
    _log('正在渲染 PDF...');
    final material = await slideGen.generatePdf(
      title: '$courseName - $topic',
      slides: slides,
      chapter: _selectedChapter ?? topic,
    );

    if (material == null || material.filePath == null) {
      throw Exception('PDF 渲染失败');
    }
    _log('PDF 渲染成功');

    // Step 3: 写入 resource_files 表
    _log('正在保存到资源库...');
    final safeName = topic.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    await db.insert('resource_files', {
      'course_id': _courseId.isNotEmpty
          ? _courseId
          : await _courseContext.activeCourseId(),
      'file_name': '扩展-$safeName.pptx',
      'file_path': material.filePath,
      'file_type': 'ppt',
      'chapter': chapter,
      'description': slides.isNotEmpty
          ? (slides.first['title'] as String? ?? topic)
          : topic,
      'source_type': 'extended',
    });
    _log('课件「$topic」生成完成！');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('扩展课件「$topic」(PPT) 生成成功！'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

// ── 推荐视频卡片（内联使用）────────────────────────────────────────────────

class _RecommendVideoCard extends StatelessWidget {
  final Map<String, dynamic> video;
  const _RecommendVideoCard({required this.video});

  static const _platformColors = {
    'bilibili': Color(0xFFFB7299),
    'youtube': Color(0xFFFF0000),
    'douyin': Color(0xFF000000),
    'twitter': Color(0xFF1DA1F2),
  };

  static const _platformNames = {
    'bilibili': 'B站',
    'youtube': 'YouTube',
    'douyin': '抖音',
    'twitter': '推特',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final platform = video['platform'] ?? 'bilibili';
    final accent = _platformColors[platform] ?? Colors.grey;
    final platformName = _platformNames[platform] ?? platform;
    final isAi = video['is_ai_recommended'] == true;
    final url = video['video_url'] ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (url.isNotEmpty) {
            try {
              await launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication);
            } catch (e, st) {
              swallowDebug(e, tag: 'LearningHub.launchUrl', stack: st);
            }
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图占位
            Expanded(
              child: Container(
                color: accent.withValues(alpha: 0.15),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_fill,
                          size: 32, color: accent.withValues(alpha: 0.6)),
                      if (isAi) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('AI推荐',
                              style:
                                  TextStyle(fontSize: 9, color: Colors.purple)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // 底部信息
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video['title'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(platformName,
                            style: TextStyle(fontSize: 9, color: accent)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          video['source'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
