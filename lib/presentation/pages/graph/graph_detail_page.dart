import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/local/learning_record_dao.dart';
import '../../../data/local/favorite_dao.dart';
import '../../../data/local/learning_path_dao.dart';
import '../../../data/models/node_model.dart';
import '../../../data/models/edge_model.dart';
import '../../../data/models/learning_path_model.dart';
import '../../../services/graph_layout_service.dart';
import '../../../services/auth_service.dart';

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
  bool _showSearch = false;
  Set<String> _highlightedNodeIds = {};
  String? _filterNodeType; // null = 全部
  Set<String> _availableNodeTypes = {};

  // ── 展开/折叠 ────────────────────────────────────────────────────────────
  Set<String> _collapsedNodes = {}; // 被折叠的父节点 ID
  List<PositionedNode> _visiblePositionedNodes = [];

  // ── 邻居高亮 ────────────────────────────────────────────────────────────
  Set<String> _adjacentNodeIds = {}; // 选中节点的相邻节点

  // ── 节点拖拽 ────────────────────────────────────────────────────────────
  String? _draggingNodeId; // 正在拖拽的节点 ID
  Map<String, Offset> _nodeOffsets = {}; // 节点自定义偏移（拖拽结果）
  bool _dragHasMoved = false; // 拖拽期间是否移动过
  NodeModel? _longPressedNode; // 长按的节点（用于区分拖拽和上下文菜单）

  // ── 学习路径覆盖 ──────────────────────────────────────────────────────────
  List<String> _learningPathNodeIds = []; // 当前显示的学习路径节点ID列表
  bool _showLearningPath = false;

  // ── 上溯/下钻路径 ────────────────────────────────────────────────────────
  List<NodeModel> _ancestorPath = []; // 从选中节点到根节点的路径
  List<NodeModel> _descendantLeaves = []; // 选中节点的所有叶子节点
  Set<String> _drillPathNodeIds = {}; // 上溯+下钻的全部节点ID（用于高亮）

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
      _nodes = nodes;
      _edges = edges;
      _availableNodeTypes = nodes
          .where((n) => n.nodeType != null && n.nodeType!.isNotEmpty)
          .map((n) => n.nodeType!)
          .toSet();
      _calculatePositions();
      setState(() => _isLoading = false);
    } catch (e) {
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
              Clipboard.setData(ClipboardData(text: reportStr));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('报告已复制到剪贴板')),
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

    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Markdown 已复制到剪贴板')),
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
    } catch (_) {}
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
    } catch (_) {}
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
    return Container(
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
            size: Size(
              MediaQuery.of(context).size.width * 2.5,
              MediaQuery.of(context).size.height * 2.5,
            ),
          ),
        ),
      ),
    );
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

class GraphPainter extends CustomPainter {
  final List<NodeModel> nodes;
  final List<EdgeModel> edges;
  final NodeModel? selectedNode;
  final List<PositionedNode> positionedNodes;
  final Set<String> highlightedNodeIds;
  final Set<String> collapsedNodes;
  final Set<String> adjacentNodeIds;
  final bool Function(String) hasChildrenFn;
  final List<String> learningPathNodeIds;
  final Set<String> drillPathNodeIds;
  final List<NodeModel> ancestorPath;

  GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    required this.positionedNodes,
    this.highlightedNodeIds = const {},
    this.collapsedNodes = const {},
    this.adjacentNodeIds = const {},
    required this.hasChildrenFn,
    this.learningPathNodeIds = const [],
    this.drillPathNodeIds = const {},
    this.ancestorPath = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positionedNodes.isEmpty) return;

    final nodeMap = {for (final p in positionedNodes) p.node.id: p};

    // ── 绘制边 ───────────────────────────────────────────────────────────
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      final isSearchHighlighted = highlightedNodeIds.contains(edge.sourceId) ||
          highlightedNodeIds.contains(edge.targetId);

      // 判断边是否连接选中节点（邻居高亮）
      final isAdjacentEdge = selectedNode != null &&
          (edge.sourceId == selectedNode!.id || edge.targetId == selectedNode!.id);

      // 判断边是否在上溯/下钻路径中
      final isDrillEdge = drillPathNodeIds.isNotEmpty &&
          drillPathNodeIds.contains(edge.sourceId) &&
          drillPathNodeIds.contains(edge.targetId);

      // 交叉引用边（虚线）
      final isDashed = edge.style == 'dashed' || edge.edgeType == 'requires' ||
          edge.edgeType == 'implements' || edge.edgeType == 'supports' ||
          edge.edgeType == 'guides';

      Color edgeColor;
      double edgeWidth;
      if (isDrillEdge) {
        edgeColor = const Color(0xFFFF8F00); // 琥珀色
        edgeWidth = 3.0;
      } else if (isAdjacentEdge) {
        edgeColor = Colors.red.shade400;
        edgeWidth = 2.5;
      } else if (isSearchHighlighted) {
        edgeColor = Colors.blue.shade300;
        edgeWidth = 2.0;
      } else if (isDashed) {
        edgeColor = const Color(0xFFFF5722);
        edgeWidth = 1.5;
      } else {
        edgeColor = Colors.grey.shade300;
        edgeWidth = 1.2;
      }

      final edgePaint = Paint()
        ..color = edgeColor
        ..strokeWidth = edgeWidth
        ..style = PaintingStyle.stroke;

      final srcOff = Offset(src.x, src.y);
      final tgtOff = Offset(tgt.x, tgt.y);

      // 贝塞尔曲线替代直线
      final mid = Offset((src.x + tgt.x) / 2, (src.y + tgt.y) / 2);
      final dx = tgt.x - src.x;
      final dy = tgt.y - src.y;
      final ctrl = Offset(mid.dx - dy * 0.1, mid.dy + dx * 0.1);

      final path = Path()
        ..moveTo(srcOff.dx, srcOff.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, tgtOff.dx, tgtOff.dy);
      canvas.drawPath(path, edgePaint);

      // 箭头（调整到节点边缘而非中心）
      final nodeRadius = 28.0;
      final dist = (tgtOff - srcOff).distance;
      if (dist > nodeRadius * 2) {
        final t = 1 - nodeRadius / dist;
        final arrowEnd = Offset(
          srcOff.dx + (tgtOff.dx - srcOff.dx) * t,
          srcOff.dy + (tgtOff.dy - srcOff.dy) * t,
        );
        _drawArrow(canvas, srcOff, arrowEnd,
            edgePaint..style = PaintingStyle.fill);
      }

      // 边标签
      if (edge.label != null && edge.label!.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: edge.label,
            style: TextStyle(
                fontSize: 9, color: Colors.grey.shade500),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 2));
      }
    }

    // ── 绘制上溯/下钻路径高亮叠加 ─────────────────────────────────────────
    if (drillPathNodeIds.isNotEmpty) {
      // 绘制上溯路径连线（琥珀色粗线，带光晕）
      if (ancestorPath.length >= 2) {
        final ancestorPaint = Paint()
          ..color = const Color(0xFFFF8F00)
          ..strokeWidth = 4.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final ancestorGlow = Paint()
          ..color = const Color(0xFFFF8F00).withValues(alpha: 0.15)
          ..strokeWidth = 16.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        for (int i = 0; i < ancestorPath.length - 1; i++) {
          final fromNode = nodeMap[ancestorPath[i].id];
          final toNode = nodeMap[ancestorPath[i + 1].id];
          if (fromNode == null || toNode == null) continue;

          final start = Offset(fromNode.x, fromNode.y);
          final end = Offset(toNode.x, toNode.y);

          canvas.drawLine(start, end, ancestorGlow);
          canvas.drawLine(start, end, ancestorPaint);

          // 路径序号
          final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
          canvas.drawCircle(mid, 10, Paint()..color = Colors.white);
          canvas.drawCircle(
              mid,
              10,
              Paint()
                ..color = const Color(0xFFFF8F00)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
          final tp = TextPainter(
            text: TextSpan(
              text: '${i + 1}',
              style: const TextStyle(
                  color: Color(0xFFFF8F00),
                  fontSize: 9,
                  fontWeight: FontWeight.bold),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
        }

        // 根节点标记
        final rootNode = nodeMap[ancestorPath.first.id];
        if (rootNode != null) {
          canvas.drawCircle(
              Offset(rootNode.x, rootNode.y),
              45,
              Paint()
                ..color = Colors.deepOrange.shade700
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3);
          final rootTp = TextPainter(
            text: const TextSpan(
                text: '根',
                style: TextStyle(
                    color: Color(0xFFE65100),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            textDirection: TextDirection.ltr,
          )..layout();
          rootTp.paint(canvas,
              Offset(rootNode.x - rootTp.width / 2, rootNode.y - 55));
        }
      }

      // 下钻路径中所有节点的琥珀色外圈
      for (final nodeId in drillPathNodeIds) {
        final pNode = nodeMap[nodeId];
        if (pNode == null) continue;
        // 不重复标记已在祖先路径中的节点
        if (ancestorPath.any((a) => a.id == nodeId)) continue;

        canvas.drawCircle(
          Offset(pNode.x, pNode.y),
          38,
          Paint()
            ..color = const Color(0xFFFF8F00).withValues(alpha: 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    // ── 绘制学习路径叠加 ─────────────────────────────────────────────────
    if (learningPathNodeIds.length >= 2) {
      final pathPaint = Paint()
        ..color = const Color(0xFF4CAF50)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final pathGlowPaint = Paint()
        ..color = const Color(0xFF4CAF50).withValues(alpha: 0.15)
        ..strokeWidth = 14.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < learningPathNodeIds.length - 1; i++) {
        final fromNode = nodeMap[learningPathNodeIds[i]];
        final toNode = nodeMap[learningPathNodeIds[i + 1]];
        if (fromNode == null || toNode == null) continue;

        final start = Offset(fromNode.x, fromNode.y);
        final end = Offset(toNode.x, toNode.y);

        // 绿色光晕线
        canvas.drawLine(start, end, pathGlowPaint);
        // 绿色实线
        canvas.drawLine(start, end, pathPaint);

        // 路径序号标记
        final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
        final numPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(mid, 12, numPaint);
        canvas.drawCircle(
            mid,
            12,
            Paint()
              ..color = const Color(0xFF4CAF50)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);

        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: const TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 10,
                fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
      }

      // 起点/终点标记
      final startNode = nodeMap[learningPathNodeIds.first];
      final endNode = nodeMap[learningPathNodeIds.last];
      if (startNode != null) {
        final sp = Paint()
          ..color = Colors.green.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(Offset(startNode.x, startNode.y), 45, sp);
        // "起" 标签
        final startTp = TextPainter(
          text: const TextSpan(
              text: '起',
              style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        startTp.paint(canvas,
            Offset(startNode.x - startTp.width / 2, startNode.y - 55));
      }
      if (endNode != null) {
        final ep = Paint()
          ..color = Colors.red.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawCircle(Offset(endNode.x, endNode.y), 45, ep);
        final endTp = TextPainter(
          text: const TextSpan(
              text: '终',
              style: TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        endTp.paint(
            canvas, Offset(endNode.x - endTp.width / 2, endNode.y - 55));
      }
    }

    // ── 绘制节点 ─────────────────────────────────────────────────────────
    for (final pNode in positionedNodes) {
      final node = pNode.node;
      final isSelected = selectedNode?.id == node.id;
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final isAdjacent = adjacentNodeIds.contains(node.id);
      final isCollapsed = collapsedNodes.contains(node.id);
      final hasChildren = hasChildrenFn(node.id);
      final isDrillNode = drillPathNodeIds.contains(node.id);

      final baseRadius = _getNodeRadius(node);
      final radius = isSelected ? baseRadius + 8 : baseRadius;
      final center = Offset(pNode.x, pNode.y);
      final nodeColor = _getNodeColor(node);

      // 上溯/下钻路径光晕（琥珀色）
      if (isDrillNode && !isSelected) {
        final drillGlow = Paint()
          ..color = const Color(0xFFFF8F00).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(center, radius + 8, drillGlow);
        // 琥珀色边框
        canvas.drawCircle(
            center,
            radius + 3,
            Paint()
              ..color = const Color(0xFFFF8F00)
              ..strokeWidth = 2.5
              ..style = PaintingStyle.stroke);
      }

      // 搜索高亮光晕（黄色）
      if (isHighlighted) {
        final glowPaint = Paint()
          ..color = Colors.yellow.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawCircle(center, radius + 10, glowPaint);
      }

      // 邻居高亮光晕（红色/橙色）
      if (isAdjacent && !isSelected) {
        final adjGlow = Paint()
          ..color = Colors.red.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(center, radius + 8, adjGlow);
        // 邻居虚线边框
        final adjBorder = Paint()
          ..color = Colors.red.shade300
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius + 3, adjBorder);
      }

      // 阴影
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(center.dx + 2, center.dy + 3), radius, shadowPaint);

      // 节点形状（按 nodeType 区分）
      _drawNodeShape(canvas, center, radius, nodeColor, node.nodeType);

      // 选中边框
      if (isSelected) {
        final selPaint = Paint()
          ..color = Colors.blue
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius + 2, selPaint);
      }

      // 折叠指示器
      if (hasChildren) {
        final indicator = isCollapsed ? '+' : '−';
        final indColor = isCollapsed ? Colors.orange : Colors.green;
        final indRadius = 9.0;
        final indCenter =
            Offset(center.dx + radius - 4, center.dy - radius + 4);
        canvas.drawCircle(
            indCenter, indRadius, Paint()..color = Colors.white);
        canvas.drawCircle(
            indCenter,
            indRadius,
            Paint()
              ..color = indColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
        final tp = TextPainter(
          text: TextSpan(
            text: indicator,
            style: TextStyle(
                color: indColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(indCenter.dx - tp.width / 2, indCenter.dy - tp.height / 2));
      }

      // 节点标题
      final displayTitle =
          node.title.length > 8 ? '${node.title.substring(0, 8)}…' : node.title;
      final textPainter = TextPainter(
        text: TextSpan(
          text: displayTitle,
          style: TextStyle(
            color: _isLightColor(nodeColor) ? Colors.black87 : Colors.white,
            fontSize: node.level == 0 ? 11 : 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 2 - 8);
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2,
            center.dy - textPainter.height / 2),
      );
    }
  }

  double _getNodeRadius(NodeModel node) {
    switch (node.level) {
      case 0: return 38;
      case 1: return 32;
      case 2: return 28;
      default: return 24;
    }
  }

  void _drawNodeShape(
      Canvas canvas, Offset center, double radius, Color color, String? type) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;

    switch (type) {
      case 'root':
        // 双圆（表示根节点）
        canvas.drawCircle(center, radius, paint);
        canvas.drawCircle(
            center,
            radius - 4,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        break;
      case 'category':
        // 圆角矩形
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: center, width: radius * 2, height: radius * 1.6),
          Radius.circular(radius * 0.4),
        );
        canvas.drawRRect(rect, paint);
        break;
      case 'section':
        // 六边形
        _drawPolygon(canvas, center, radius, 6, paint);
        break;
      default:
        // 默认圆形
        canvas.drawCircle(center, radius, paint);
    }
  }

  void _drawPolygon(
      Canvas canvas, Offset center, double radius, int sides, Paint paint) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  Color _getNodeColor(NodeModel node) {
    // 优先使用节点自定义颜色
    if (node.color != null && node.color!.isNotEmpty) {
      try {
        return Color(int.parse(node.color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    // 按层级着色
    const levelColors = [
      Color(0xFFE53935), // L0 红
      Color(0xFFFF9800), // L1 橙
      Color(0xFF4CAF50), // L2 绿
      Color(0xFF2196F3), // L3 蓝
      Color(0xFF9C27B0), // L4 紫
      Color(0xFF607D8B), // L5 灰蓝
    ];
    return node.level < levelColors.length
        ? levelColors[node.level]
        : const Color(0xFF9E9E9E);
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() > 0.5;
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    const arrowSize = 10.0;
    final angle = (end - start).direction;
    final p1 = Offset(
      end.dx - arrowSize * math.cos(angle - 0.4),
      end.dy - arrowSize * math.sin(angle - 0.4),
    );
    final p2 = Offset(
      end.dx - arrowSize * math.cos(angle + 0.4),
      end.dy - arrowSize * math.sin(angle + 0.4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant GraphPainter old) =>
      old.selectedNode != selectedNode ||
      old.positionedNodes != positionedNodes ||
      old.highlightedNodeIds != highlightedNodeIds ||
      old.collapsedNodes != collapsedNodes ||
      old.adjacentNodeIds != adjacentNodeIds ||
      old.learningPathNodeIds != learningPathNodeIds ||
      old.drillPathNodeIds != drillPathNodeIds ||
      old.ancestorPath != ancestorPath;
}
