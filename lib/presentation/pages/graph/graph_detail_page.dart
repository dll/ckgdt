import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../data/local/graph_dao.dart';
import '../../../data/models/graph_model.dart';
import '../../../data/models/node_model.dart';
import '../../../data/models/edge_model.dart';

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
  List<NodeModel> _nodes = [];
  List<EdgeModel> _edges = [];
  bool _isLoading = true;
  NodeModel? _selectedNode;

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
      setState(() {
        _nodes = nodes;
        _edges = edges;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.graphTitle),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGraphData,
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

  Widget _buildGraphView() {
    return Container(
      color: Colors.grey[100],
      child: GestureDetector(
        onTapDown: (details) => _handleTap(details.localPosition),
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
    final positionedNodes = _calculateNodePositions();
    for (final node in positionedNodes) {
      final distance = (Offset(node.x, node.y) - position).distance;
      if (distance < 35) {
        setState(() => _selectedNode = node);
        return;
      }
    }
  }

  List<NodeModel> _calculateNodePositions() {
    // Check if nodes have valid positions
    final hasValidPositions = _nodes.any((n) => n.x != 0 || n.y != 0);
    
    if (hasValidPositions) {
      return _nodes;
    }

    // Auto-calculate positions in a tree-like layout
    final positioned = <NodeModel>[];
    final levelGroups = <int, List<NodeModel>>{};
    
    for (final node in _nodes) {
      levelGroups.putIfAbsent(node.level, () => []).add(node);
    }

    final levels = levelGroups.keys.toList()..sort();
    final screenWidth = 800.0;
    final verticalSpacing = 120.0;
    final startY = 100.0;

    for (int i = 0; i < levels.length; i++) {
      final level = levels[i];
      final levelNodes = levelGroups[level]!;
      final horizontalSpacing = screenWidth / (levelNodes.length + 1);
      
      for (int j = 0; j < levelNodes.length; j++) {
        final node = levelNodes[j];
        positioned.add(NodeModel(
          id: node.id,
          graphId: node.graphId,
          title: node.title,
          content: node.content,
          nodeType: node.nodeType,
          level: node.level,
          x: horizontalSpacing * (j + 1),
          y: startY + i * verticalSpacing,
          color: node.color,
          parentId: node.parentId,
          visible: node.visible,
          metadata: node.metadata,
        ));
      }
    }

    return positioned;
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
                      backgroundColor: const Color(0xFF667eea),
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

  GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    // Calculate positions if nodes don't have valid positions
    final positionedNodes = _calculateNodePositions();

    // Draw edges first (behind nodes)
    final edgePaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final sourceNode = positionedNodes.where((n) => n.id == edge.sourceId).firstOrNull;
      final targetNode = positionedNodes.where((n) => n.id == edge.targetId).firstOrNull;
      if (sourceNode != null && targetNode != null) {
        canvas.drawLine(
          Offset(sourceNode.x, sourceNode.y),
          Offset(targetNode.x, targetNode.y),
          edgePaint,
        );
        
        // Draw arrow
        _drawArrow(canvas, Offset(sourceNode.x, sourceNode.y), Offset(targetNode.x, targetNode.y), edgePaint);
      }
    }

    // Draw nodes
    for (final node in positionedNodes) {
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
      canvas.drawCircle(Offset(node.x + 2, node.y + 2), nodeRadius, shadowPaint);

      canvas.drawCircle(Offset(node.x, node.y), nodeRadius, nodePaint);
      canvas.drawCircle(Offset(node.x, node.y), nodeRadius, borderPaint);

      // Draw level indicator
      final levelPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(node.x + nodeRadius - 8, node.y - nodeRadius + 8), 8, levelPaint);

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
        Offset(node.x + nodeRadius - 8 - levelTextPainter.width / 2, 
               node.y - nodeRadius + 8 - levelTextPainter.height / 2),
      );

      // Draw title
      final displayTitle = node.title.length > 6 ? '${node.title.substring(0, 6)}...' : node.title;
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
        Offset(node.x - textPainter.width / 2, node.y - textPainter.height / 2),
      );
    }
  }

  List<NodeModel> _calculateNodePositions() {
    // Check if nodes have valid positions
    final hasValidPositions = nodes.any((n) => n.x != 0 || n.y != 0);
    
    if (hasValidPositions) {
      return nodes;
    }

    // Auto-calculate positions in a tree-like layout
    final positioned = <NodeModel>[];
    final levelGroups = <int, List<NodeModel>>{};
    
    for (final node in nodes) {
      levelGroups.putIfAbsent(node.level, () => []).add(node);
    }

    final levels = levelGroups.keys.toList()..sort();
    final screenWidth = 800.0;
    final verticalSpacing = 120.0;
    final startY = 100.0;

    for (int i = 0; i < levels.length; i++) {
      final level = levels[i];
      final levelNodes = levelGroups[level]!;
      final horizontalSpacing = screenWidth / (levelNodes.length + 1);
      
      for (int j = 0; j < levelNodes.length; j++) {
        final node = levelNodes[j];
        positioned.add(NodeModel(
          id: node.id,
          graphId: node.graphId,
          title: node.title,
          content: node.content,
          nodeType: node.nodeType,
          level: node.level,
          x: horizontalSpacing * (j + 1),
          y: startY + i * verticalSpacing,
          color: node.color,
          parentId: node.parentId,
          visible: node.visible,
          metadata: node.metadata,
        ));
      }
    }

    return positioned;
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
