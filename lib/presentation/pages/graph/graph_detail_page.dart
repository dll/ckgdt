import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../data/local/favorite_dao.dart';
import '../../../data/local/learning_path_dao.dart';
import '../../../data/models/node_model.dart';
import '../../../data/models/edge_model.dart';
import '../../../data/models/learning_path_model.dart';
import '../../../services/graph_layout_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/clipboard_helper.dart';
import 'package:knowledge_graph_app/core/error_handler.dart';


// ── Painter 拆分到 parts/（part / part of 模式）─────────────
part 'parts/graph_detail_painter.dart';

class GraphDetailPage extends StatefulWidget {
  final String graphId;
  final String graphTitle;

  const GraphDetailPage({
    super.key,
    required this.graphId,
    required this.graphTitle,
  });

  @override
  State<GraphDetailPage> createState() => _GraphDetailPageState();
}

class _GraphDetailPageState extends State<GraphDetailPage>
    with SingleTickerProviderStateMixin {
  final _graphDao = GraphDao();
  final _learningPathDao = LearningPathDao();
  final _learningRecordDao = LearningRecordDao();
  final _favoriteDao = FavoriteDao();
  final _authService = AuthService();
  final _layoutService = GraphLayoutService();
  final _transformationController = TransformationController();

  List<NodeModel> _nodes = [];
  List<EdgeModel> _edges = [];
  bool _isLoading = true;
  NodeModel? _selectedNode;
  GraphLayout _currentLayout = GraphLayout.tree;
  List<PositionedNode> _positionedNodes = [];

  // ── 搜索 & 筛选 ──────────────────────────────────────────────────────────
  // ignore: unused_field
  String _searchQuery = '';
  bool _showSearch = false;
  Set<String> _highlightedNodeIds = {};
  String? _filterNodeType; // null = 全部
  Set<String> _availableNodeTypes = {};

  // ── 展开/折叠 ────────────────────────────────────────────────────────────
  final Set<String> _collapsedNodes = {}; // 被折叠的父节点 ID
  List<PositionedNode> _visiblePositionedNodes = [];

  // ── 邻居高亮 ────────────────────────────────────────────────────────────
  Set<String> _adjacentNodeIds = {}; // 选中节点的相邻节点

  // ── 节点拖拽 ────────────────────────────────────────────────────────────
  String? _draggingNodeId; // 正在拖拽的节点 ID
  final Map<String, Offset> _nodeOffsets = {}; // 节点自定义偏移（拖拽结果）
  bool _dragHasMoved = false; // 拖拽期间是否移动过
  NodeModel? _longPressedNode; // 长按的节点（用于区分拖拽和上下文菜单）

  // ── 学习路径覆盖 ──────────────────────────────────────────────────────────
  List<String> _learningPathNodeIds = []; // 当前显示的学习路径节点ID列表
  bool _showLearningPath = false;

  // ── 上溯/下钻路径 ────────────────────────────────────────────────────────
  List<NodeModel> _ancestorPath = []; // 从选中节点到根节点的路径
  List<NodeModel> _descendantLeaves = []; // 选中节点的所有叶子节点
  Set<String> _drillPathNodeIds = {}; // 上溯+下钻的全部节点ID（用于高亮）

  // ── 画布尺寸（由 _buildGraphView 设置，供缩放方法使用）──────────────────
  double _canvasW = 1000;
  double _canvasH = 1000;

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  Future<void> _loadGraphData() async {
    setState(() => _isLoading = true);
    try {
      final nodes = await _graphDao.getNodes(widget.graphId);
      final edges = await _graphDao.getEdges(widget.graphId);
      if (!mounted) return;
      _nodes = nodes;
      _edges = edges;
      _availableNodeTypes = nodes
          .where((n) => n.nodeType != null && n.nodeType!.isNotEmpty)
          .map((n) => n.nodeType!)
          .toSet();
      _calculatePositions();
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _calculatePositions() {
    final w = MediaQuery.of(context).size.width * 2.5;
    final h = MediaQuery.of(context).size.height * 2.5;

    // 应用筛选
    var filteredNodes = _nodes.toList();
    if (_filterNodeType != null) {
      filteredNodes =
          filteredNodes.where((n) => n.nodeType == _filterNodeType).toList();
    }

    // 应用折叠
    final hiddenIds = _getHiddenNodeIds();
    filteredNodes =
        filteredNodes.where((n) => !hiddenIds.contains(n.id)).toList();

    final filteredEdges = _edges
        .where((e) =>
            filteredNodes.any((n) => n.id == e.sourceId) &&
            filteredNodes.any((n) => n.id == e.targetId))
        .toList();

    _positionedNodes = _layoutService.calculateLayout(
      nodes: filteredNodes,
      edges: filteredEdges,
      layoutType: _currentLayout,
      canvasWidth: w,
      canvasHeight: h,
    );
    _visiblePositionedNodes = _positionedNodes;
  }

  Set<String> _getHiddenNodeIds() {
    if (_collapsedNodes.isEmpty) return {};
    final hidden = <String>{};
    for (final collapsedId in _collapsedNodes) {
      _collectDescendants(collapsedId, hidden);
    }
    return hidden;
  }

  void _collectDescendants(String parentId, Set<String> result) {
    for (final node in _nodes) {
      if (node.parentId == parentId && !result.contains(node.id)) {
        result.add(node.id);
        _collectDescendants(node.id, result);
      }
    }
  }

  bool _hasChildren(String nodeId) {
    return _nodes.any((n) => n.parentId == nodeId);
  }

  // ── 搜索 ─────────────────────────────────────────────────────────────────

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _highlightedNodeIds = {};
      } else {
        _highlightedNodeIds = _nodes
            .where((n) =>
                n.title.toLowerCase().contains(query.toLowerCase()) ||
                (n.content ?? '').toLowerCase().contains(query.toLowerCase()))
            .map((n) => n.id)
            .toSet();
      }
    });
  }

  void _scrollToNode(String nodeId) {
    final pNode = _visiblePositionedNodes
        .where((p) => p.node.id == nodeId)
        .firstOrNull;
    if (pNode == null) return;

    _animateCenterOnNode(pNode.x, pNode.y, scale: 1.5);
    setState(() => _selectNode(pNode.node));
  }

  /// 平滑动画居中到指定画布坐标
  void _animateCenterOnNode(double targetX, double targetY,
      {double scale = 1.5, int durationMs = 400}) {
    final screenSize = MediaQuery.of(context).size;

    final startMatrix = _transformationController.value.clone();
    final endMatrix = Matrix4.identity()
      ..scale(scale)
      ..translate(
        -targetX + screenSize.width / (2 * scale),
        -targetY + screenSize.height / (2 * scale),
      );

    // 使用简易 tween 动画
    final controller = AnimationController(
      duration: Duration(milliseconds: durationMs),
      vsync: this,
    );
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    animation.addListener(() {
      final t = animation.value;
      // 线性插值每个矩阵元素
      final m = Matrix4.zero();
      for (int i = 0; i < 16; i++) {
        m.storage[i] =
            startMatrix.storage[i] + (endMatrix.storage[i] - startMatrix.storage[i]) * t;
      }
      _transformationController.value = m;
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  // ── 布局 ─────────────────────────────────────────────────────────────────

  /// 统一设置选中节点，同时计算邻居
  void _selectNode(NodeModel? node) {
    _selectedNode = node;
    if (node == null) {
      _adjacentNodeIds = {};
    } else {
      _adjacentNodeIds = {};
      for (final e in _edges) {
        if (e.sourceId == node.id) _adjacentNodeIds.add(e.targetId);
        if (e.targetId == node.id) _adjacentNodeIds.add(e.sourceId);
      }
    }
  }

  // ── 学习路径覆盖 ────────────────────────────────────────────────────────

  void _toggleLearningPathOverlay() async {
    if (_showLearningPath) {
      setState(() {
        _showLearningPath = false;
        _learningPathNodeIds = [];
      });
      return;
    }

    final userId = _authService.getCurrentUserId();
    if (userId == null) return;

    try {
      final paths = await _learningPathDao.getPathsByUser(userId);
      if (paths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂无学习路径，请先生成')),
          );
        }
        return;
      }

      // 显示路径选择器
      if (!mounted) return;
      final selected = await showModalBottomSheet<LearningPathModel>(
        context: context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择学习路径',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...paths.map((path) => ListTile(
                    leading: const Icon(Icons.route, color: Colors.blue),
                    title: Text(path.title),
                    subtitle: Text('${path.nodeIds.length} 个节点'),
                    onTap: () => Navigator.pop(ctx, path),
                  )),
            ],
          ),
        ),
      );

      if (selected != null) {
        // 过滤出在当前图谱中实际存在的节点
        final existingIds = _nodes.map((n) => n.id).toSet();
        final validIds =
            selected.nodeIds.where((id) => existingIds.contains(id)).toList();
        setState(() {
          _learningPathNodeIds = validIds;
          _showLearningPath = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载学习路径失败: $e')),
        );
      }
    }
  }

  void _changeLayout(GraphLayout layout) {
    _currentLayout = layout;
    _calculatePositions();
    setState(() {});
  }

  void _showLayoutPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择布局',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: GraphLayout.values.map((layout) {
                return ChoiceChip(
                  label: Text(layout.label),
                  selected: _currentLayout == layout,
                  onSelected: (_) {
                    Navigator.pop(context);
                    _changeLayout(layout);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── 节点筛选 ─────────────────────────────────────────────────────────────

  void _showFilterPanel() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('节点筛选',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('当前显示 ${_visiblePositionedNodes.length}/${_nodes.length} 个节点',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _filterNodeType == null,
                  onSelected: (_) {
                    Navigator.pop(context);
                    setState(() {
                      _filterNodeType = null;
                      _calculatePositions();
                    });
                  },
                ),
                ..._availableNodeTypes.map((type) => ChoiceChip(
                      label: Text(_nodeTypeLabel(type)),
                      selected: _filterNodeType == type,
                      onSelected: (_) {
                        Navigator.pop(context);
                        setState(() {
                          _filterNodeType = type;
                          _calculatePositions();
                        });
                      },
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _nodeTypeLabel(String type) {
    const labels = {
      'root': '根节点',
      'category': '分类',
      'file': '文件',
      'section': '章节',
      'concept': '概念',
      'topic': '主题',
    };
    return labels[type] ?? type;
  }

  // ── 图谱分析（对标 Python graph_analyzer.py）───────────────────────────

  void _analyzeGraph() {
    final nodeCount = _nodes.length;
    final edgeCount = _edges.length;

    // 度分析
    final inDegree = <String, int>{};
    final outDegree = <String, int>{};
    for (final n in _nodes) {
      inDegree[n.id] = 0;
      outDegree[n.id] = 0;
    }
    for (final e in _edges) {
      outDegree[e.sourceId] = (outDegree[e.sourceId] ?? 0) + 1;
      inDegree[e.targetId] = (inDegree[e.targetId] ?? 0) + 1;
    }

    // 连通性分析
    final visited = <String>{};
    int componentCount = 0;
    for (final n in _nodes) {
      if (!visited.contains(n.id)) {
        componentCount++;
        _bfs(n.id, visited);
      }
    }

    // 中心度最高节点 (degree centrality)
    final totalDegree = <String, int>{};
    for (final n in _nodes) {
      totalDegree[n.id] =
          (inDegree[n.id] ?? 0) + (outDegree[n.id] ?? 0);
    }
    final sortedByDegree = totalDegree.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topNodes = sortedByDegree.take(5).toList();

    // 孤立节点
    final isolatedNodes =
        _nodes.where((n) => (totalDegree[n.id] ?? 0) == 0).toList();

    // 类型分布
    final typeDistribution = <String, int>{};
    for (final n in _nodes) {
      final t = n.nodeType ?? '未分类';
      typeDistribution[t] = (typeDistribution[t] ?? 0) + 1;
    }

    // 层级分布
    final levelDistribution = <int, int>{};
    for (final n in _nodes) {
      levelDistribution[n.level] = (levelDistribution[n.level] ?? 0) + 1;
    }

    final avgDegree = nodeCount > 0
        ? (edgeCount * 2 / nodeCount).toStringAsFixed(1)
        : '0';

    // 生成 Markdown 报告
    final report = StringBuffer();
    report.writeln('# 图谱分析报告：${widget.graphTitle}\n');
    report.writeln('## 基本统计');
    report.writeln('- 节点总数：$nodeCount');
    report.writeln('- 边总数：$edgeCount');
    report.writeln('- 平均度：$avgDegree');
    report.writeln('- 连通分量数：$componentCount');
    report.writeln('- 孤立节点数：${isolatedNodes.length}\n');

    report.writeln('## 中心度 Top 5');
    for (final entry in topNodes) {
      final name = _nodes.firstWhere((n) => n.id == entry.key).title;
      report.writeln('- $name（度=${entry.value}）');
    }

    report.writeln('\n## 类型分布');
    typeDistribution.forEach((type, count) {
      report.writeln('- ${_nodeTypeLabel(type)}：$count');
    });

    report.writeln('\n## 层级分布');
    final sortedLevels = levelDistribution.keys.toList()..sort();
    for (final level in sortedLevels) {
      report.writeln('- Level $level：${levelDistribution[level]} 个节点');
    }

    if (isolatedNodes.isNotEmpty) {
      report.writeln('\n## 孤立节点');
      for (final n in isolatedNodes) {
        report.writeln('- ${n.title}');
      }
    }

    final reportStr = report.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('图谱分析报告'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: Column(
            children: [
              // 统计卡片
              Row(
                children: [
                  _statCard('节点', '$nodeCount', Colors.blue),
                  _statCard('边', '$edgeCount', Colors.orange),
                  _statCard('连通', '$componentCount', Colors.green),
                  _statCard('孤立', '${isolatedNodes.length}', Colors.red),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    reportStr,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制报告'),
            onPressed: () {
              Navigator.pop(ctx);
              ClipboardHelper.copyWithToast(
                context,
                reportStr,
                message: '报告已复制到剪贴板',
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  void _bfs(String startId, Set<String> visited) {
    final queue = [startId];
    visited.add(startId);
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final e in _edges) {
        if (e.sourceId == current && !visited.contains(e.targetId)) {
          visited.add(e.targetId);
          queue.add(e.targetId);
        }
        if (e.targetId == current && !visited.contains(e.sourceId)) {
          visited.add(e.sourceId);
          queue.add(e.sourceId);
        }
      }
    }
  }

  // ── Markdown 导出 ───────────────────────────────────────────────────────

  void _exportMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# ${widget.graphTitle}\n');

    // 按层级分组
    final byLevel = <int, List<NodeModel>>{};
    for (final n in _nodes) {
      byLevel.putIfAbsent(n.level, () => []).add(n);
    }
    final sortedLevels = byLevel.keys.toList()..sort();
    for (final lv in sortedLevels) {
      buf.writeln('## Level $lv\n');
      for (final n in byLevel[lv]!) {
        buf.writeln('### ${n.title}');
        buf.writeln('- 类型: ${n.nodeType ?? "未知"}');
        if (n.content != null && n.content!.isNotEmpty) {
          buf.writeln('- 内容: ${n.content}');
        }
        buf.writeln();
      }
    }
    buf.writeln('## 关系\n');
    for (final e in _edges) {
      final srcName = _nodes.where((n) => n.id == e.sourceId).firstOrNull?.title ?? e.sourceId;
      final tgtName = _nodes.where((n) => n.id == e.targetId).firstOrNull?.title ?? e.targetId;
      buf.writeln('- $srcName → $tgtName ${e.label != null ? "(${e.label})" : ""}');
    }

    ClipboardHelper.copyWithToast(
      context,
      buf.toString(),
      message: 'Markdown 已复制到剪贴板',
    );
  }

  // ── 学习路径生成 ────────────────────────────────────────────────────────

  void _generateLearningPath(NodeModel node) async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) return;

    final pathNodeIds = <String>[];

    // 1. 上溯到根节点
    var current = node;
    final ancestors = <String>[node.id];
    while (current.parentId != null && current.parentId!.isNotEmpty) {
      final parent = _nodes.where((n) => n.id == current.parentId).firstOrNull;
      if (parent == null) break;
      if (ancestors.contains(parent.id)) break;
      ancestors.add(parent.id);
      current = parent;
    }
    pathNodeIds.addAll(ancestors.reversed); // root → ... → selected

    // 2. 收集所有子孙节点
    final descendants = <String>{};
    _collectDescendants(node.id, descendants);
    pathNodeIds.addAll(descendants);

    final path = LearningPathModel(
      userId: userId,
      title: '学习路径: ${node.title}',
      description: '从「${widget.graphTitle}」的「${node.title}」生成，包含 ${pathNodeIds.length} 个节点（根→选中→叶）',
      nodeIds: pathNodeIds,
    );
    await _learningPathDao.createPath(path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成学习路径（${pathNodeIds.length} 个节点）')),
      );
    }
  }

  // ── 上溯到根节点 ──────────────────────────────────────────────────────────

  void _traceAncestors(NodeModel node) {
    final path = <NodeModel>[node];
    var current = node;

    while (current.parentId != null && current.parentId!.isNotEmpty) {
      final parent = _nodes.where((n) => n.id == current.parentId).firstOrNull;
      if (parent == null) break;
      if (path.any((p) => p.id == parent.id)) break; // 防环
      path.add(parent);
      current = parent;
    }

    // 翻转：根 → ... → 选中节点
    _ancestorPath = path.reversed.toList();
    _descendantLeaves = [];
    _drillPathNodeIds = _ancestorPath.map((n) => n.id).toSet();

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上溯路径: ${_ancestorPath.length} 个节点（根→当前）')),
      );
    }
  }

  // ── 下钻到叶子节点 ────────────────────────────────────────────────────────

  void _drillToLeaves(NodeModel node) {
    final allDescendants = <String>{};
    _collectDescendants(node.id, allDescendants);

    // 筛选叶子节点（无子节点的）
    final leaves = allDescendants
        .where((id) => !_hasChildren(id))
        .map((id) => _nodes.firstWhere((n) => n.id == id))
        .toList();

    _descendantLeaves = leaves;
    _ancestorPath = [];
    _drillPathNodeIds = {node.id, ...allDescendants};

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '下钻: ${allDescendants.length} 个子节点，${leaves.length} 个叶节点')),
      );
    }
  }

  // ── 全路径（上溯+下钻）─────────────────────────────────────────────────

  void _traceFullPath(NodeModel node) {
    // 上溯
    final ancestorList = <NodeModel>[node];
    var current = node;
    while (current.parentId != null && current.parentId!.isNotEmpty) {
      final parent = _nodes.where((n) => n.id == current.parentId).firstOrNull;
      if (parent == null) break;
      if (ancestorList.any((p) => p.id == parent.id)) break;
      ancestorList.add(parent);
      current = parent;
    }
    _ancestorPath = ancestorList.reversed.toList();

    // 下钻
    final allDescendants = <String>{};
    _collectDescendants(node.id, allDescendants);
    _descendantLeaves = allDescendants
        .where((id) => !_hasChildren(id))
        .map((id) => _nodes.firstWhere((n) => n.id == id))
        .toList();

    // 合并高亮
    _drillPathNodeIds = {
      ..._ancestorPath.map((n) => n.id),
      ...allDescendants,
    };

    setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '全路径: ↑${_ancestorPath.length}个祖先 ↓${allDescendants.length}个后代')),
      );
    }
  }

  void _clearDrillPath() {
    setState(() {
      _ancestorPath = [];
      _descendantLeaves = [];
      _drillPathNodeIds = {};
    });
  }

  // ── 开始学习 / 收藏 ────────────────────────────────────────────────────

  void _startLearning(NodeModel node) async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) return;
    try {
      await _learningRecordDao.addRecord(userId: userId, nodeId: node.id, nodeTitle: node.title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已记录学习: ${node.title}')),
        );
      }
    } catch (e) { swallowDebug(e, tag: 'graph_detail_page'); }
  }

  void _toggleFavorite(NodeModel node) async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) return;
    try {
      final isFav = await _favoriteDao.isFavorite(userId, node.id);
      if (isFav) {
        await _favoriteDao.removeFavorite(userId, node.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已取消收藏: ${node.title}')),
          );
        }
      } else {
        await _favoriteDao.addFavorite(userId: userId, nodeId: node.id, nodeTitle: node.title);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已收藏: ${node.title}')),
          );
        }
      }
    } catch (e) { swallowDebug(e, tag: 'graph_detail_page'); }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索节点...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: _performSearch,
              )
            : Text(widget.graphTitle),
        actions: [
          // 搜索
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _performSearch('');
              });
            },
          ),
          // 筛选
          IconButton(
            icon: Badge(
              isLabelVisible: _filterNodeType != null,
              child: const Icon(Icons.filter_list),
            ),
            tooltip: '筛选',
            onPressed: _showFilterPanel,
          ),
          // 布局
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: '切换布局',
            onPressed: _showLayoutPicker,
          ),
          // 更多
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'analyze',
                child: ListTile(
                  leading: Icon(Icons.analytics),
                  title: Text('图谱分析'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_markdown',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('导出Markdown'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'reset_view',
                child: ListTile(
                  leading: Icon(Icons.center_focus_strong),
                  title: Text('重置视图'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'expand_all',
                child: ListTile(
                  leading: Icon(Icons.unfold_more),
                  title: Text('展开全部'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'learning_path',
                child: ListTile(
                  leading: Icon(Icons.route),
                  title: Text('学习路径叠加'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _nodes.isEmpty
              ? const Center(
                  child: Text('暂无图谱数据', style: TextStyle(color: Colors.grey)))
              : Column(
                  children: [
                    // 搜索结果提示条
                    if (_highlightedNodeIds.isNotEmpty)
                      _buildSearchResultBar(primary),
                    // 信息条
                    _buildInfoBar(primary),
                    // 上溯/下钻路径面包屑条
                    if (_drillPathNodeIds.isNotEmpty)
                      _buildDrillPathBar(),
                    // 图谱视图
                    Expanded(flex: 3, child: _buildGraphView()),
                    // 节点详情
                    if (_selectedNode != null)
                      Expanded(flex: 2, child: _buildNodeDetail()),
                  ],
                ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'analyze':
        _analyzeGraph();
        break;
      case 'export_markdown':
        _exportMarkdown();
        break;
      case 'reset_view':
        _transformationController.value = Matrix4.identity();
        setState(() => _selectNode(null));
        break;
      case 'expand_all':
        setState(() {
          _collapsedNodes.clear();
          _calculatePositions();
        });
        break;
      case 'learning_path':
        _toggleLearningPathOverlay();
        break;
    }
  }

  Widget _buildSearchResultBar(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: primary.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: primary),
          const SizedBox(width: 6),
          Text('找到 ${_highlightedNodeIds.length} 个匹配节点',
              style: TextStyle(fontSize: 13, color: primary)),
          const Spacer(),
          // 快速跳转按钮
          if (_highlightedNodeIds.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.my_location, size: 14),
              label: const Text('定位', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _scrollToNode(_highlightedNodeIds.first),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoBar(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          Text(
            '${_visiblePositionedNodes.length} 节点 · ${_edges.length} 边',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_currentLayout.label,
                style: TextStyle(fontSize: 10, color: primary)),
          ),
          if (_filterNodeType != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_nodeTypeLabel(_filterNodeType!),
                      style:
                          const TextStyle(fontSize: 10, color: Colors.orange)),
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => setState(() {
                      _filterNodeType = null;
                      _calculatePositions();
                    }),
                    child: const Icon(Icons.close, size: 12, color: Colors.orange),
                  ),
                ],
              ),
            ),
          ],
          if (_showLearningPath) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route, size: 10, color: Colors.green),
                  const SizedBox(width: 2),
                  Text('路径 ${_learningPathNodeIds.length}节点',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.green)),
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => setState(() {
                      _showLearningPath = false;
                      _learningPathNodeIds = [];
                    }),
                    child: const Icon(Icons.close, size: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          // 图例
          _legendDot(Colors.red.shade400, 'L0'),
          _legendDot(Colors.orange.shade400, 'L1'),
          _legendDot(Colors.green.shade400, 'L2'),
          _legendDot(Colors.blue.shade400, 'L3+'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 2),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  // ── 上溯/下钻路径面包屑条 ──────────────────────────────────────────────

  Widget _buildDrillPathBar() {
    final isAncestorMode = _ancestorPath.isNotEmpty;
    final isDescendantMode = _descendantLeaves.isNotEmpty;
    final color = isAncestorMode && isDescendantMode
        ? Colors.purple
        : isAncestorMode
            ? Colors.deepOrange
            : Colors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: color.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(
                isAncestorMode && isDescendantMode
                    ? Icons.account_tree
                    : isAncestorMode
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                isAncestorMode && isDescendantMode
                    ? '全路径 · ↑${_ancestorPath.length}祖先 ↓${_descendantLeaves.length}叶节点'
                    : isAncestorMode
                        ? '上溯路径 · ${_ancestorPath.length} 个节点'
                        : '下钻 · ${_drillPathNodeIds.length} 节点（${_descendantLeaves.length} 叶节点）',
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              InkWell(
                onTap: _clearDrillPath,
                child: Icon(Icons.close, size: 16, color: color),
              ),
            ],
          ),
          // 祖先面包屑
          if (_ancestorPath.isNotEmpty) ...[
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _ancestorPath.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right, size: 14, color: color.withValues(alpha: 0.5)),
                      ),
                    InkWell(
                      onTap: () => _scrollToNode(_ancestorPath[i].id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: i == _ancestorPath.length - 1
                              ? color.withValues(alpha: 0.2)
                              : color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: i == _ancestorPath.length - 1
                              ? Border.all(color: color, width: 1)
                              : null,
                        ),
                        child: Text(
                          _ancestorPath[i].title.length > 6
                              ? '${_ancestorPath[i].title.substring(0, 6)}…'
                              : _ancestorPath[i].title,
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: i == _ancestorPath.length - 1
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // 叶节点列表
          if (_descendantLeaves.isNotEmpty) ...[
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Icon(Icons.eco, size: 12, color: Colors.teal.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  for (int i = 0; i < _descendantLeaves.length && i < 8; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _scrollToNode(_descendantLeaves[i].id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _descendantLeaves[i].title.length > 5
                              ? '${_descendantLeaves[i].title.substring(0, 5)}…'
                              : _descendantLeaves[i].title,
                          style: TextStyle(fontSize: 9, color: Colors.teal.shade700),
                        ),
                      ),
                    ),
                  ],
                  if (_descendantLeaves.length > 8)
                    Text(' +${_descendantLeaves.length - 8}',
                        style: TextStyle(fontSize: 9, color: Colors.teal.shade400)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 图谱画布 ────────────────────────────────────────────────────────────

  Widget _buildGraphView() {
    final canvasW = MediaQuery.of(context).size.width * 2.5;
    final canvasH = MediaQuery.of(context).size.height * 2.5;
    _canvasW = canvasW;
    _canvasH = canvasH;

    return Stack(
      children: [
        Container(
          color: const Color(0xFFF8FAFE),
          child: GestureDetector(
            onTapDown: (d) => _handleTap(d.localPosition),
            onDoubleTapDown: (d) => _handleDoubleTap(d.localPosition),
            onLongPressStart: (d) => _handleLongPressOrDragStart(d.localPosition),
            onLongPressMoveUpdate: (d) => _handleDragUpdate(d.localPosition),
            onLongPressEnd: (_) => _handleDragEnd(),
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(300),
              minScale: 0.05,
              maxScale: 5.0,
              child: CustomPaint(
                painter: GraphPainter(
                  nodes: _nodes,
                  edges: _edges.where((e) {
                    final vis = _visiblePositionedNodes.map((p) => p.node.id).toSet();
                    return vis.contains(e.sourceId) && vis.contains(e.targetId);
                  }).toList(),
                  selectedNode: _selectedNode,
                  positionedNodes: _visiblePositionedNodes,
                  highlightedNodeIds: _highlightedNodeIds,
                  collapsedNodes: _collapsedNodes,
                  adjacentNodeIds: _adjacentNodeIds,
                  hasChildrenFn: _hasChildren,
                  learningPathNodeIds: _showLearningPath ? _learningPathNodeIds : [],
                  drillPathNodeIds: _drillPathNodeIds,
                  ancestorPath: _ancestorPath,
                ),
                size: Size(canvasW, canvasH),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: _buildGraphToolbar(),
        ),
        if (_visiblePositionedNodes.isNotEmpty)
          Positioned(
            right: 8,
            bottom: 8,
            child: _buildMinimap(canvasW, canvasH),
          ),
      ],
    );
  }

  // ── 缩放工具栏 ──────────────────────────────────────────────────────────

  Widget _buildGraphToolbar() {
    return AnimatedBuilder(
      animation: _transformationController,
      builder: (context, _) {
        final scale = _getCurrentScale();
        final percent = (scale * 100).round();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toolBtn(Icons.add, '放大', _zoomIn),
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Text(
                  '$percent%',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
              ),
              _toolBtn(Icons.remove, '缩小', _zoomOut),
              Divider(height: 1, color: Colors.grey.shade200),
              _toolBtn(Icons.crop_free, '复位', _resetView),
              Divider(height: 1, color: Colors.grey.shade200),
              _toolBtn(Icons.fit_screen, '全图', _fitAll),
              if (_selectedNode != null) ...[
                Divider(height: 1, color: Colors.grey.shade200),
                _toolBtn(Icons.my_location, '居中选中', _centerOnSelected),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 36,
          child: Icon(icon, size: 20, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  double _getCurrentScale() {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  Size _getViewportSize() {
    final renderBox = context.findRenderObject() as RenderBox?;
    return renderBox?.size ?? const Size(400, 600);
  }

  /// 计算所有可见节点的包围盒
  Rect _computeNodesBounds() {
    if (_visiblePositionedNodes.isEmpty) {
      return Rect.fromLTWH(0, 0, _canvasW, _canvasH);
    }
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in _visiblePositionedNodes) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    const pad = 100.0;
    return Rect.fromLTWH(minX - pad, minY - pad,
        (maxX - minX) + pad * 2, (maxY - minY) + pad * 2);
  }

  void _zoomIn() {
    final viewport = _getViewportSize();
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    final cur = _transformationController.value;
    final s = (_getCurrentScale() * 1.3).clamp(0.05, 5.0);
    final inv = Matrix4.inverted(cur);
    final focus = MatrixUtils.transformPoint(inv, Offset(cx, cy));
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, -s * focus.dx + cx)
      ..setEntry(1, 3, -s * focus.dy + cy);
  }

  void _zoomOut() {
    final viewport = _getViewportSize();
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    final cur = _transformationController.value;
    final s = (_getCurrentScale() / 1.3).clamp(0.05, 5.0);
    final inv = Matrix4.inverted(cur);
    final focus = MatrixUtils.transformPoint(inv, Offset(cx, cy));
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, -s * focus.dx + cx)
      ..setEntry(1, 3, -s * focus.dy + cy);
  }

  /// 复位：缩放至 0.8 并将图谱包围盒居中到视口
  void _resetView() {
    final bounds = _computeNodesBounds();
    final viewport = _getViewportSize();
    const scale = 0.8;
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    final centerX = bounds.center.dx;
    final centerY = bounds.center.dy;
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -scale * centerX + cx)
      ..setEntry(1, 3, -scale * centerY + cy);
  }

  /// 全图：计算包围盒自动缩放适配视口
  void _fitAll() {
    final bounds = _computeNodesBounds();
    final viewport = _getViewportSize();
    if (bounds.width <= 0 || bounds.height <= 0) {
      _resetView();
      return;
    }
    final padW = viewport.width * 0.1;
    final padH = viewport.height * 0.1;
    final availW = viewport.width - padW * 2;
    final availH = viewport.height - padH * 2;
    final scaleX = availW / bounds.width;
    final scaleY = availH / bounds.height;
    final scale = math.min(scaleX, scaleY).clamp(0.05, 5.0);
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    final centerX = bounds.center.dx;
    final centerY = bounds.center.dy;
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -scale * centerX + cx)
      ..setEntry(1, 3, -scale * centerY + cy);
  }

  void _centerOnSelected() {
    if (_selectedNode == null) return;
    final pNode = _visiblePositionedNodes.cast<PositionedNode?>().firstWhere(
      (p) => p!.node.id == _selectedNode!.id,
      orElse: () => null,
    );
    if (pNode == null) return;
    final viewport = _getViewportSize();
    final s = _getCurrentScale().clamp(0.05, 5.0);
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, -s * pNode.x + cx)
      ..setEntry(1, 3, -s * pNode.y + cy);
  }

  // ── 鹰眼小地图 ──────────────────────────────────────────────────────

  Widget _buildMinimap(double canvasW, double canvasH) {
    const mapW = 140.0;
    const mapH = 120.0;
    final scaleX = mapW / canvasW;
    final scaleY = mapH / canvasH;

    return GestureDetector(
      onTapDown: (details) {
        final tapX = details.localPosition.dx / scaleX;
        final tapY = details.localPosition.dy / scaleY;
        _animateCenter(tapX, tapY, canvasW, canvasH);
      },
      onPanUpdate: (details) {
        final tapX = details.localPosition.dx / scaleX;
        final tapY = details.localPosition.dy / scaleY;
        _animateCenter(tapX, tapY, canvasW, canvasH);
      },
      child: AnimatedBuilder(
        animation: _transformationController,
        builder: (context, _) {
          final matrix = _transformationController.value;
          final inv = Matrix4.inverted(matrix);
          final renderBox = context.findRenderObject() as RenderBox?;
          final parentSize = renderBox?.size ?? const Size(400, 600);

          final topLeft = MatrixUtils.transformPoint(inv, Offset.zero);
          final bottomRight = MatrixUtils.transformPoint(
            inv,
            Offset(parentSize.width, parentSize.height),
          );

          final vpLeft = (topLeft.dx * scaleX).clamp(0.0, mapW);
          final vpTop = (topLeft.dy * scaleY).clamp(0.0, mapH);
          final vpRight = (bottomRight.dx * scaleX).clamp(0.0, mapW);
          final vpBottom = (bottomRight.dy * scaleY).clamp(0.0, mapH);

          return Container(
            width: mapW,
            height: mapH,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _DetailMinimapPainter(
                  nodes: _visiblePositionedNodes,
                  canvasWidth: canvasW,
                  canvasHeight: canvasH,
                  viewportRect: Rect.fromLTRB(vpLeft, vpTop, vpRight, vpBottom),
                ),
                size: const Size(mapW, mapH),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 点击小地图跳转
  void _animateCenter(double x, double y, double canvasW, double canvasH) {
    final viewport = _getViewportSize();
    final s = _getCurrentScale().clamp(0.05, 5.0);
    final cx = viewport.width / 2;
    final cy = viewport.height / 2;
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, -s * x + cx)
      ..setEntry(1, 3, -s * y + cy);
  }

  // ── 节点拖拽处理（长按+拖拽）─────────────────────────────────────────

  void _handleLongPressOrDragStart(Offset position) {
    final matrix = _transformationController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, position);

    for (final pNode in _visiblePositionedNodes) {
      final distance = (Offset(pNode.x, pNode.y) - canvasPos).distance;
      if (distance < 35) {
        _draggingNodeId = pNode.node.id;
        _dragHasMoved = false;
        _longPressedNode = pNode.node;
        return;
      }
    }
    // 如果不在节点上
    _draggingNodeId = null;
    _longPressedNode = null;
  }

  void _handleDragUpdate(Offset position) {
    if (_draggingNodeId == null) return;

    _dragHasMoved = true;
    final matrix = _transformationController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, position);

    // 更新被拖拽节点的位置
    final idx = _visiblePositionedNodes.indexWhere(
        (p) => p.node.id == _draggingNodeId);
    if (idx >= 0) {
      setState(() {
        _visiblePositionedNodes[idx] = PositionedNode(
          _visiblePositionedNodes[idx].node,
          canvasPos.dx,
          canvasPos.dy,
        );
        // 保存自定义偏移
        _nodeOffsets[_draggingNodeId!] = canvasPos;
      });
    }
  }

  void _handleDragEnd() {
    // 如果长按节点但没有移动，显示上下文菜单
    if (!_dragHasMoved && _longPressedNode != null) {
      _showNodeContextMenu(_longPressedNode!);
    }
    _draggingNodeId = null;
    _longPressedNode = null;
    _dragHasMoved = false;
  }

  void _handleTap(Offset position) {
    // 需要将屏幕坐标转为画布坐标
    final matrix = _transformationController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, position);

    for (final pNode in _visiblePositionedNodes) {
      final distance = (Offset(pNode.x, pNode.y) - canvasPos).distance;
      if (distance < 35) {
        setState(() => _selectNode(pNode.node));
        return;
      }
    }
  }

  void _handleDoubleTap(Offset position) {
    final matrix = _transformationController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, position);

    for (final pNode in _visiblePositionedNodes) {
      final distance = (Offset(pNode.x, pNode.y) - canvasPos).distance;
      if (distance < 35 && _hasChildren(pNode.node.id)) {
        setState(() {
          if (_collapsedNodes.contains(pNode.node.id)) {
            _collapsedNodes.remove(pNode.node.id);
          } else {
            _collapsedNodes.add(pNode.node.id);
          }
          _calculatePositions();
        });
        return;
      }
    }
  }

  void _showNodeContextMenu(NodeModel node) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(node.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.route, color: Colors.blue),
              title: const Text('生成学习路径'),
              onTap: () {
                Navigator.pop(context);
                _generateLearningPath(node);
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.green),
              title: const Text('开始学习'),
              onTap: () {
                Navigator.pop(context);
                _startLearning(node);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text('收藏/取消收藏'),
              onTap: () {
                Navigator.pop(context);
                _toggleFavorite(node);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Colors.deepOrange),
              title: const Text('上溯到根节点'),
              subtitle: const Text('追溯从根到当前节点的路径'),
              onTap: () {
                Navigator.pop(context);
                _traceAncestors(node);
              },
            ),
            if (_hasChildren(node.id))
              ListTile(
                leading: const Icon(Icons.arrow_downward, color: Colors.teal),
                title: const Text('下钻到叶节点'),
                subtitle: const Text('展开所有子孙直到叶子'),
                onTap: () {
                  Navigator.pop(context);
                  _drillToLeaves(node);
                },
              ),
            ListTile(
              leading: const Icon(Icons.account_tree, color: Colors.purple),
              title: const Text('全路径（上溯+下钻）'),
              onTap: () {
                Navigator.pop(context);
                _traceFullPath(node);
              },
            ),
            if (_hasChildren(node.id))
              ListTile(
                leading: Icon(
                  _collapsedNodes.contains(node.id)
                      ? Icons.unfold_more
                      : Icons.unfold_less,
                  color: Colors.purple,
                ),
                title: Text(
                    _collapsedNodes.contains(node.id) ? '展开子节点' : '折叠子节点'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    if (_collapsedNodes.contains(node.id)) {
                      _collapsedNodes.remove(node.id);
                    } else {
                      _collapsedNodes.add(node.id);
                    }
                    _calculatePositions();
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.grey),
              title: const Text('查看详情'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectNode(node));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── 节点详情面板 ────────────────────────────────────────────────────────

  Widget _buildNodeDetail() {
    final node = _selectedNode!;
    final primary = Theme.of(context).colorScheme.primary;
    final childCount = _nodes.where((n) => n.parentId == node.id).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getLevelColor(node.level),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text('L${node.level}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(node.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _tagChip(
                              _nodeTypeLabel(node.nodeType ?? ''), primary),
                          if (childCount > 0)
                            _tagChip('$childCount 子节点', Colors.grey),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectNode(null)),
                ),
              ],
            ),
            if (node.content != null && node.content!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(node.content!,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black87, height: 1.5)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _startLearning(node),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('开始学习'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleFavorite(node),
                    icon: const Icon(Icons.star_border, size: 18),
                    label: const Text('收藏'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _generateLearningPath(node),
                    icon: const Icon(Icons.route, size: 18),
                    label: const Text('路径'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 上溯/下钻按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _traceAncestors(node),
                    icon: const Icon(Icons.arrow_upward, size: 16),
                    label: const Text('上溯到根', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hasChildren(node.id)
                        ? () => _drillToLeaves(node)
                        : null,
                    icon: const Icon(Icons.arrow_downward, size: 16),
                    label: const Text('下钻到叶', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _traceFullPath(node),
                    icon: const Icon(Icons.account_tree, size: 16),
                    label: const Text('全路径', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 居中按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final pNode = _visiblePositionedNodes
                      .where((p) => p.node.id == node.id)
                      .firstOrNull;
                  if (pNode != null) {
                    _animateCenterOnNode(pNode.x, pNode.y);
                  }
                },
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text('居中显示'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  Color _getLevelColor(int level) {
    const colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.green,
      Colors.blue,
      Colors.indigo,
    ];
    return level < colors.length ? colors[level] : Colors.grey;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GraphPainter — 对标 Python visualization/graph_2d.py 的渲染质量
// ══════════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════════
// _DetailMinimapPainter — 详细图谱鹰眼小地图
// ══════════════════════════════════════════════════════════════════════════════

class _DetailMinimapPainter extends CustomPainter {
  final List<PositionedNode> nodes;
  final double canvasWidth;
  final double canvasHeight;
  final Rect viewportRect;

  _DetailMinimapPainter({
    required this.nodes,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.viewportRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / canvasWidth;
    final sy = size.height / canvasHeight;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF8FAFE),
    );

    for (final pNode in nodes) {
      final center = Offset(pNode.x * sx, pNode.y * sy);
      final color = _parseNodeColor(pNode.node.color);
      canvas.drawCircle(
        center,
        2.5,
        Paint()..color = color,
      );
    }

    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = const Color(0xFF1677FF).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = const Color(0xFF1677FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  Color _parseNodeColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.grey;
    try {
      final hex = colorStr.replaceFirst('#', '');
      final value = int.parse(hex, radix: 16);
      return Color(value | 0xFF000000);
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  bool shouldRepaint(covariant _DetailMinimapPainter old) =>
      old.viewportRect != viewportRect || old.nodes != nodes;
}

