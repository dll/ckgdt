import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../data/local/learning_path_dao.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/local/knowledge_graph_dao.dart';
import '../../../data/models/learning_path_model.dart';
import '../../../data/models/node_model.dart';
import '../learning/video_page.dart';
import '../materials/resource_viewer_page.dart';

/// 学习路径页面 — 替代原"学习计划"
/// 列表模式: 显示所有路径卡片
/// 详情模式: 上半部路径图形，下半部节点属性列表
class LearningPlanPage extends StatefulWidget {
  const LearningPlanPage({super.key});

  @override
  State<LearningPlanPage> createState() => _LearningPlanPageState();
}

class _LearningPlanPageState extends State<LearningPlanPage> {
  final _authService = AuthService();
  final _learningPathDao = LearningPathDao();
  final _graphDao = GraphDao();
  final _kgDao = KnowledgeGraphDao();

  List<LearningPathModel> _paths = [];
  bool _isLoading = true;

  // 详情模式
  LearningPathModel? _selectedPath;
  List<_UnifiedNode> _pathNodes = []; // 路径中各节点的完整信息
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    setState(() => _isLoading = true);
    try {
      final userId = _authService.getCurrentUserId();
      if (userId != null) {
        final paths = await _learningPathDao.getPathsByUser(userId);
        setState(() {
          _paths = paths;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openPathDetail(LearningPathModel path) async {
    setState(() {
      _selectedPath = path;
      _loadingDetail = true;
    });
    try {
      final nodes = <_UnifiedNode>[];
      for (final nid in path.nodeIds) {
        if (nid.startsWith('c_')) {
          // New concept-based node
          final conceptId = int.tryParse(nid.substring(2));
          if (conceptId != null) {
            final concept = await _kgDao.getConceptById(conceptId);
            if (concept != null) {
              nodes.add(_UnifiedNode.fromConcept(concept));
            }
          }
        } else {
          // Old tree-based node
          final node = await _graphDao.getNode(nid);
          if (node != null) {
            nodes.add(_UnifiedNode.fromNodeModel(node));
          }
        }
      }
      setState(() {
        _pathNodes = nodes;
        _loadingDetail = false;
      });
    } catch (e) {
      setState(() => _loadingDetail = false);
    }
  }

  void _closeDetail() {
    setState(() {
      _selectedPath = null;
      _pathNodes = [];
    });
  }

  void _deletePath(LearningPathModel path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除路径「${path.title}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && path.id != null) {
      await _learningPathDao.deletePath(path.id!);
      if (_selectedPath?.id == path.id) _closeDetail();
      _loadPaths();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除「${path.title}」')),
        );
      }
    }
  }

  // ── 路径颜色 ───────────────────────────────────────────────────────────
  Color _pathColor(LearningPathModel path) {
    const colors = [
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFF8E24AA),
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFF00897B),
    ];
    return colors[(path.id ?? 0) % colors.length];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // 详情模式
    if (_selectedPath != null) {
      return _buildDetailView();
    }
    // 列表模式
    return _buildListView();
  }

  // ── 列表模式 ───────────────────────────────────────────────────────────

  Widget _buildListView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_paths.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('暂无学习路径',
                style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('在知识图谱中点击概念 → 生成学习路径',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loadPaths,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPaths,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _paths.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildSummaryCard();
          return _buildPathCard(_paths[index - 1]);
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total = _paths.length;
    final totalNodes =
        _paths.fold<int>(0, (sum, p) => sum + p.nodeIds.length);
    final avgProgress = _paths.isEmpty
        ? 0.0
        : _paths.map((p) => p.progress).reduce((a, b) => a + b) / total;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _summaryItem(Icons.route, '$total', '路径'),
            _summaryDivider(),
            _summaryItem(Icons.circle, '$totalNodes', '总节点'),
            _summaryDivider(),
            _summaryItem(Icons.speed, '${avgProgress.toInt()}%', '平均进度'),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _summaryDivider() {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  Widget _buildPathCard(LearningPathModel path) {
    final color = _pathColor(path);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openPathDetail(path),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.route, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(path.title,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        if (path.description != null &&
                            path.description!.isNotEmpty)
                          Text(path.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  // 节点数徽章
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${path.nodeIds.length}节点',
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 18, color: Colors.grey[400]),
                    onSelected: (v) {
                      if (v == 'delete') _deletePath(path);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 进度条
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: path.progress / 100,
                        minHeight: 6,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${path.progress.toInt()}%',
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 详情模式 ───────────────────────────────────────────────────────────

  Widget _buildDetailView() {
    final path = _selectedPath!;
    final color = _pathColor(path);

    return Column(
      children: [
        // 顶部标题栏
        Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.15))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _closeDetail,
              ),
              Icon(Icons.route, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(path.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Text('${_pathNodes.length}/${path.nodeIds.length} 节点',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),

        if (_loadingDetail)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else ...[
          // 上半部: 路径图形
          SizedBox(
            height: 180,
            child: _pathNodes.length >= 2
                ? CustomPaint(
                    painter: _PathGraphPainter(
                      nodes: _pathNodes,
                      color: color,
                    ),
                    size: Size.infinite,
                  )
                : Center(
                    child: Text(
                      _pathNodes.isEmpty ? '路径节点不可用' : '需要至少 2 个节点绘制路径',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
          ),

          Divider(height: 1, color: Colors.grey[200]),

          // 下半部: 节点属性列表
          Expanded(
            child: _pathNodes.isEmpty
                ? Center(
                    child: Text('无有效节点数据',
                        style: TextStyle(color: Colors.grey[400])))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _pathNodes.length,
                    itemBuilder: (ctx, i) =>
                        _buildNodeTile(_pathNodes[i], i, color),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildNodeTile(_UnifiedNode node, int index, Color pathColor) {
    final isFirst = index == 0;
    final isLast = index == _pathNodes.length - 1;
    final nodeColor = _parseColor(node.color) ?? pathColor;

    return InkWell(
      onTap: () => _showNodeInfo(node),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左侧时间线
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    // 上连接线
                    Expanded(
                      child: Container(
                        width: isFirst ? 0 : 2,
                        color: pathColor.withValues(alpha: 0.3),
                      ),
                    ),
                    // 圆点
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: nodeColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: nodeColor, width: 2),
                      ),
                      child: Center(
                        child: Text('${index + 1}',
                            style: TextStyle(
                                fontSize: 9,
                                color: nodeColor,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    // 下连接线
                    Expanded(
                      child: Container(
                        width: isLast ? 0 : 2,
                        color: pathColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 节点信息卡片
              Expanded(
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题行
                        Row(
                          children: [
                            Expanded(
                              child: Text(node.title,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            // Level 标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: nodeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('L${node.level}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: nodeColor,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 属性行
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _attrChip(Icons.category,
                                node.isConcept ? _conceptTypeLabel(node.conceptType) : _nodeTypeLabel(node.nodeType), Colors.grey),
                            if (isFirst)
                              _attrChip(Icons.play_arrow, '起点',
                                  Colors.green),
                            if (isLast)
                              _attrChip(
                                  Icons.flag, '终点', Colors.red),
                            if (node.isConcept && node.importance != null)
                              _attrChip(
                                Icons.star,
                                node.importance == 'core' ? '核心' : node.importance == 'important' ? '重要' : '补充',
                                node.importance == 'core' ? Colors.red : node.importance == 'important' ? Colors.orange : Colors.grey,
                              ),
                            if (node.chapter != null)
                              _attrChip(Icons.book, '第${node.chapter}章', Colors.indigo),
                          ],
                        ),
                        // 内容摘要
                        if (node.content != null &&
                            node.content!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            node.content!.length > 80
                                ? '${node.content!.substring(0, 80)}…'
                                : node.content!,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attrChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _nodeTypeLabel(String? type) {
    const labels = {
      'root': '根节点',
      'category': '分类',
      'file': '文件',
      'section': '章节',
      'concept': '概念',
      'topic': '主题',
    };
    return labels[type] ?? type ?? '节点';
  }

  String _conceptTypeLabel(String? type) {
    const labels = {
      'concept': '概念',
      'technology': '技术',
      'tool': '工具',
      'framework': '框架',
      'language': '语言',
      'platform': '平台',
      'pattern': '模式',
    };
    return labels[type] ?? type ?? '概念';
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  /// 节点到章节的映射 — 根据节点标题模糊匹配章节名
  String? _matchChapterByTitle(String title, String? content) {
    const chapterKeywords = {
      '移动应用开发技术': '第一章',
      '技术体系': '第一章',
      '原生开发': '第二章',
      'Android': '第二章',
      'iOS': '第二章',
      '混合开发': '第三章',
      'Flutter': '第三章',
      'React Native': '第三章',
      '跨平台': '第三章',
      '小程序': '第四章',
      '微信': '第四章',
      'UniApp': '第四章',
      '华为': '第五章',
      'HarmonyOS': '第五章',
      '鸿蒙': '第五章',
      '综合开发': '第六章',
      '综合实践': '第六章',
      '实战': '第六章',
    };

    final c = content ?? '';

    for (final entry in chapterKeywords.entries) {
      if (title.contains(entry.key) || c.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  void _showNodeInfo(_UnifiedNode node) {
    String? chapter;
    if (node.isConcept && node.chapter != null) {
      const chapterNames = {1: '第一章', 2: '第二章', 3: '第三章', 4: '第四章', 5: '第五章', 6: '第六章'};
      chapter = chapterNames[node.chapter];
    } else {
      chapter = _matchChapterByTitle(node.title, node.content);
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (_parseColor(node.color) ?? Colors.blue)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('L${node.level}',
                        style: TextStyle(
                            color: _parseColor(node.color) ?? Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(node.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 节点属性信息
            _infoRow('ID', node.isConcept ? '概念 ${node.id.substring(2)}' : node.id),
            _infoRow('类型', node.isConcept ? _conceptTypeLabel(node.conceptType) : _nodeTypeLabel(node.nodeType)),
            _infoRow('层级', 'Level ${node.level}'),
            if (chapter != null)
              _infoRow('关联章节', chapter),
            if (node.keywords != null)
              _infoRow('关键词', node.keywords!),

            if (node.content != null && node.content!.isNotEmpty) ...[
              const Divider(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 80),
                child: SingleChildScrollView(
                  child: Text(node.content!,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.5)),
                ),
              ),
            ],

            const Divider(),
            const SizedBox(height: 4),

            // 资源操作按钮行
            Row(
              children: [
                Expanded(
                  child: _resourceButton(
                    icon: Icons.play_circle,
                    label: '视频',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoListPage(
                            filterChapter: chapter,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _resourceButton(
                    icon: Icons.slideshow,
                    label: 'PPT',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResourceViewerPage(
                            fileType: 'ppt',
                            filterChapter: chapter,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _resourceButton(
                    icon: Icons.picture_as_pdf,
                    label: 'PDF',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResourceViewerPage(
                            fileType: 'pdf',
                            filterChapter: chapter,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PathGraphPainter — 路径图形可视化（参考 Python learning_path_tab.py）
// ══════════════════════════════════════════════════════════════════════════════

class _PathGraphPainter extends CustomPainter {
  final List<_UnifiedNode> nodes;
  final Color color;

  _PathGraphPainter({required this.nodes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 2) return;

    final n = nodes.length;
    final padding = 40.0;
    final usableWidth = size.width - padding * 2;
    final usableHeight = size.height - padding * 2;
    final centerY = size.height / 2;

    // 计算每个节点的位置（水平排列，自适应换行）
    final maxPerRow = (usableWidth / 90).floor().clamp(3, 8);
    final rows = (n / maxPerRow).ceil();
    final rowHeight = rows > 1 ? usableHeight / rows : 0.0;

    final positions = <Offset>[];
    for (int i = 0; i < n; i++) {
      final row = i ~/ maxPerRow;
      final col = i % maxPerRow;
      final itemsInRow = (row < rows - 1) ? maxPerRow : (n - row * maxPerRow);
      final colSpacing = usableWidth / (itemsInRow + 1);

      // 蛇形排列：偶数行左→右，奇数行右→左
      final actualCol = row.isOdd ? (itemsInRow - 1 - col) : col;
      final x = padding + colSpacing * (actualCol + 1);
      final y = rows == 1
          ? centerY
          : padding + rowHeight * 0.5 + row * rowHeight;
      positions.add(Offset(x, y));
    }

    // 绘制连接线
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final arrowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.fill;

    for (int i = 0; i < positions.length - 1; i++) {
      final from = positions[i];
      final to = positions[i + 1];
      canvas.drawLine(from, to, linePaint);

      // 箭头
      final dist = (to - from).distance;
      if (dist > 30) {
        final angle = (to - from).direction;
        final arrowEnd = Offset(
          to.dx - 16 * math.cos(angle),
          to.dy - 16 * math.sin(angle),
        );
        final p1 = Offset(
          arrowEnd.dx - 8 * math.cos(angle - 0.5),
          arrowEnd.dy - 8 * math.sin(angle - 0.5),
        );
        final p2 = Offset(
          arrowEnd.dx - 8 * math.cos(angle + 0.5),
          arrowEnd.dy - 8 * math.sin(angle + 0.5),
        );
        canvas.drawPath(
          Path()
            ..moveTo(arrowEnd.dx, arrowEnd.dy)
            ..lineTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..close(),
          arrowPaint,
        );
      }
    }

    // 绘制节点
    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final node = nodes[i];
      final isFirst = i == 0;
      final isLast = i == n - 1;
      final nodeColor = _parseHexColor(node.color) ?? color;
      final radius = isFirst || isLast ? 16.0 : 13.0;

      // 光晕
      if (isFirst || isLast) {
        final glowPaint = Paint()
          ..color = (isFirst ? Colors.green : Colors.red).withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(pos, radius + 6, glowPaint);
      }

      // 节点圆
      canvas.drawCircle(pos, radius, Paint()..color = nodeColor);
      // 白色内圈
      canvas.drawCircle(
          pos,
          radius - 3,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // 序号
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));

      // 节点标题
      final title = node.title.length > 6
          ? '${node.title.substring(0, 6)}…'
          : node.title;
      final titleTp = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(fontSize: 9, color: Colors.grey[700]),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 80);
      titleTp.paint(
          canvas, Offset(pos.dx - titleTp.width / 2, pos.dy + radius + 4));
    }
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  @override
  bool shouldRepaint(covariant _PathGraphPainter old) =>
      old.nodes != nodes || old.color != color;
}

/// Unified node representation for both old tree nodes and new semantic concepts
class _UnifiedNode {
  final String id;
  final String title;
  final String? content;
  final int level;
  final String? nodeType;
  final String? color;
  final int? chapter;
  final String? conceptType;
  final String? importance;
  final String? keywords;
  final bool isConcept;

  _UnifiedNode({
    required this.id,
    required this.title,
    this.content,
    this.level = 0,
    this.nodeType,
    this.color,
    this.chapter,
    this.conceptType,
    this.importance,
    this.keywords,
    this.isConcept = false,
  });

  /// Create from old NodeModel
  factory _UnifiedNode.fromNodeModel(NodeModel node) {
    return _UnifiedNode(
      id: node.id,
      title: node.title,
      content: node.content,
      level: node.level,
      nodeType: node.nodeType,
      color: node.color,
      isConcept: false,
    );
  }

  /// Create from concept map
  factory _UnifiedNode.fromConcept(Map<String, dynamic> concept) {
    // Map concept_type to a display color
    const typeColors = {
      'concept': '#9C27B0',
      'technology': '#1E88E5',
      'tool': '#FF9800',
      'framework': '#43A047',
      'language': '#E53935',
      'platform': '#00BCD4',
      'pattern': '#795548',
    };
    final cType = concept['concept_type'] as String? ?? 'concept';
    return _UnifiedNode(
      id: 'c_${concept['id']}',
      title: concept['concept_name'] as String? ?? '未命名概念',
      content: concept['description'] as String?,
      level: concept['importance'] == 'core' ? 0 : (concept['importance'] == 'important' ? 1 : 2),
      nodeType: cType,
      color: typeColors[cType] ?? '#667eea',
      chapter: concept['chapter'] as int?,
      conceptType: cType,
      importance: concept['importance'] as String?,
      keywords: concept['keywords'] as String?,
      isConcept: true,
    );
  }
}
