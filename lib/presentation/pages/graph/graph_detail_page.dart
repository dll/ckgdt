import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../data/local/graph_dao.dart';
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

class _GraphDetailPageState extends State<GraphDetailPage> {
  final _graphDao = GraphDao();
  final _learningPathDao = LearningPathDao();
  final _authService = AuthService();
  final _layoutService = GraphLayoutService();

  List<NodeModel> _nodes = [];
  List<EdgeModel> _edges = [];
  bool _isLoading = true;
  NodeModel? _selectedNode;
  GraphLayout _currentLayout = GraphLayout.tree;
  List<PositionedNode> _positionedNodes = [];
  Offset? _tapPosition;

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  Future<void> _loadGraphData() async {
    setState(() => _isLoading = true);
    try {
      final nodes = await _graphDao.getNodes(widget.graphId);
      final edges = await _graphDao.getEdges(widget.graphId);
      _calculatePositions(nodes, edges);
      setState(() {
        _nodes = nodes;
        _edges = edges;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _calculatePositions(List<NodeModel> nodes, List<EdgeModel> edges) {
    final screenWidth = MediaQuery.of(context).size.width * 2;
    final screenHeight = MediaQuery.of(context).size.height * 2;
    _positionedNodes = _layoutService.calculateLayout(
      nodes: nodes,
      edges: edges,
      layoutType: _currentLayout,
      canvasWidth: screenWidth,
      canvasHeight: screenHeight,
    );
  }

  void _changeLayout(GraphLayout layout) {
    setState(() {
      _currentLayout = layout;
    });
    _calculatePositions(_nodes, _edges);
  }

  void _showLayoutPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择布局',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: GraphLayout.values.map((layout) {
                final isSelected = _currentLayout == layout;
                return ChoiceChip(
                  label: Text(layout.label),
                  selected: isSelected,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.graphTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGraphData,
          ),
          IconButton(
            icon: const Icon(Icons.grid_view),
            tooltip: '切换布局',
            onPressed: _showLayoutPicker,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export_markdown',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('导出Markdown'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'analyze',
                child: ListTile(
                  leading: Icon(Icons.analytics),
                  title: Text('图谱分析'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'center',
                child: ListTile(
                  leading: Icon(Icons.center_focus_strong),
                  title: Text('居中显示'),
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
                  child: Text(
                    '暂无图谱数据',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    // 图谱可视化区域
                    Expanded(
                      flex: 3,
                      child: _buildGraphView(),
                    ),
                    // 节点详情
                    if (_selectedNode != null)
                      Expanded(
                        flex: 2,
                        child: _buildNodeDetail(),
                      ),
                  ],
                ),
    );
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'export_markdown':
        _exportMarkdown();
        break;
      case 'analyze':
        _analyzeGraph();
        break;
      case 'center':
        setState(() => _selectedNode = null);
        break;
    }
  }

  void _exportMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# ${widget.graphTitle}');
    buffer.writeln();
    buffer.writeln('## 节点');
    for (final node in _nodes) {
      buffer.writeln('### ${node.title}');
      if (node.content != null) {
        buffer.writeln(node.content);
      }
      buffer.writeln();
    }
    buffer.writeln('## 关系');
    for (final edge in _edges) {
      buffer.writeln(
          '- ${edge.sourceId} → ${edge.targetId}: ${edge.label ?? ""}');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Markdown已生成，可在控制台查看')),
    );
  }

  void _analyzeGraph() {
    final nodeCount = _nodes.length;
    final edgeCount = _edges.length;
    final avgDegree =
        edgeCount > 0 ? (edgeCount * 2 / nodeCount).toStringAsFixed(2) : '0';

    final levels = <int>{};
    for (final node in _nodes) {
      levels.add(node.level);
    }

    final nodeTypes = <String>{};
    for (final node in _nodes) {
      if (node.nodeType != null) {
        nodeTypes.add(node.nodeType!);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('图谱分析'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAnalysisRow('节点总数', '$nodeCount'),
            _buildAnalysisRow('边总数', '$edgeCount'),
            _buildAnalysisRow('平均度', avgDegree),
            _buildAnalysisRow('层级数', '${levels.length}'),
            _buildAnalysisRow('节点类型数', '${nodeTypes.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGraphView() {
    return Container(
      color: Colors.grey[100],
      child: GestureDetector(
        onTapDown: (details) => _handleTap(details.localPosition),
        onLongPressStart: (details) => _handleLongPress(details.localPosition),
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: 0.1,
          maxScale: 4.0,
          child: CustomPaint(
            painter: GraphPainter(
              nodes: _nodes,
              edges: _edges,
              selectedNode: _selectedNode,
              positionedNodes: _positionedNodes,
            ),
            size: Size(
              MediaQuery.of(context).size.width * 2,
              MediaQuery.of(context).size.height * 2,
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(Offset position) {
    for (final pNode in _positionedNodes) {
      final distance = (Offset(pNode.x, pNode.y) - position).distance;
      if (distance < 35) {
        setState(() => _selectedNode = pNode.node);
        return;
      }
    }
  }

  void _handleLongPress(Offset position) {
    for (final pNode in _positionedNodes) {
      final distance = (Offset(pNode.x, pNode.y) - position).distance;
      if (distance < 35) {
        _showNodeContextMenu(position, pNode.node);
        return;
      }
    }
  }

  void _showNodeContextMenu(Offset position, NodeModel node) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.route),
              title: Text('生成学习路径: ${node.title}'),
              onTap: () {
                Navigator.pop(context);
                _generateLearningPath(node);
              },
            ),
            ListTile(
              leading: const Icon(Icons.quiz),
              title: Text('加入测验'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已选择节点「${node.title}」加入测验')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('查看详情'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedNode = node);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _generateLearningPath(NodeModel node) async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }

    final path = LearningPathModel(
      userId: userId,
      title: '学习路径: ${node.title}',
      description: '从 ${widget.graphTitle} 生成',
      nodeIds: [node.id],
    );

    await _learningPathDao.createPath(path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已生成学习路径')),
      );
    }
  }

  Widget _buildNodeDetail() {
    final node = _selectedNode!;
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
                CircleAvatar(
                  backgroundColor: _getLevelColor(node.level),
                  child: Text(
                    '${node.level}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    node.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedNode = null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              node.nodeType ?? '知识点',
              style: TextStyle(
                color: _getLevelColor(node.level),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (node.content != null && node.content!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                node.content!,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('开始学习: ${node.title}')),
                      );
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始学习'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('添加收藏: ${node.title}')),
                      );
                    },
                    icon: const Icon(Icons.star),
                    label: const Text('收藏'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(int level) {
    switch (level) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.amber;
      case 3:
        return Colors.green;
      case 4:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _selectNode(NodeModel node) {
    setState(() => _selectedNode = node);
  }
}

class GraphPainter extends CustomPainter {
  final List<NodeModel> nodes;
  final List<EdgeModel> edges;
  final NodeModel? selectedNode;
  final List<PositionedNode> positionedNodes;

  GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    required this.positionedNodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty || positionedNodes.isEmpty) return;

    // Draw edges first (behind nodes)
    final edgePaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final sourceNode =
          positionedNodes.where((n) => n.node.id == edge.sourceId).firstOrNull;
      final targetNode =
          positionedNodes.where((n) => n.node.id == edge.targetId).firstOrNull;
      if (sourceNode != null && targetNode != null) {
        canvas.drawLine(
          Offset(sourceNode.x, sourceNode.y),
          Offset(targetNode.x, targetNode.y),
          edgePaint,
        );

        // Draw arrow
        _drawArrow(canvas, Offset(sourceNode.x, sourceNode.y),
            Offset(targetNode.x, targetNode.y), edgePaint);
      }
    }

    // Draw nodes
    for (final pNode in positionedNodes) {
      final node = pNode.node;
      final isSelected = selectedNode?.id == node.id;
      final nodeRadius = isSelected ? 40.0 : 30.0;

      final nodePaint = Paint()
        ..color = _getNodeColor(node.level)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isSelected ? Colors.red : Colors.white
        ..strokeWidth = isSelected ? 3 : 2
        ..style = PaintingStyle.stroke;

      // Draw shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(
          Offset(pNode.x + 2, pNode.y + 2), nodeRadius, shadowPaint);

      canvas.drawCircle(Offset(pNode.x, pNode.y), nodeRadius, nodePaint);
      canvas.drawCircle(Offset(pNode.x, pNode.y), nodeRadius, borderPaint);

      // Draw level indicator
      final levelPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
          Offset(pNode.x + nodeRadius - 8, pNode.y - nodeRadius + 8),
          8,
          levelPaint);

      // Draw level number
      final levelTextPainter = TextPainter(
        text: TextSpan(
          text: '${node.level}',
          style: TextStyle(
            color: _getNodeColor(node.level),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      levelTextPainter.layout();
      levelTextPainter.paint(
        canvas,
        Offset(pNode.x + nodeRadius - 8 - levelTextPainter.width / 2,
            pNode.y - nodeRadius + 8 - levelTextPainter.height / 2),
      );

      // Draw title
      final displayTitle = node.title.length > 6
          ? '${node.title.substring(0, 6)}...'
          : node.title;
      final textPainter = TextPainter(
        text: TextSpan(
          text: displayTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: 50);
      textPainter.paint(
        canvas,
        Offset(
            pNode.x - textPainter.width / 2, pNode.y - textPainter.height / 2),
      );
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    final arrowSize = 8.0;
    final angle = (end - start).direction;
    final arrowPoint1 = Offset(
      end.dx - arrowSize * math.cos(angle - 0.5),
      end.dy - arrowSize * math.sin(angle - 0.5),
    );
    final arrowPoint2 = Offset(
      end.dx - arrowSize * math.cos(angle + 0.5),
      end.dy - arrowSize * math.sin(angle + 0.5),
    );

    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowPoint1.dx, arrowPoint1.dy)
      ..lineTo(arrowPoint2.dx, arrowPoint2.dy)
      ..close();

    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
  }

  Color _getNodeColor(int level) {
    switch (level) {
      case 0:
        return Colors.red[400]!;
      case 1:
        return Colors.orange[400]!;
      case 2:
        return Colors.amber[400]!;
      case 3:
        return Colors.green[400]!;
      case 4:
        return Colors.blue[400]!;
      default:
        return Colors.grey[400]!;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
