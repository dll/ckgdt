import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/chapter_helper.dart';
import '../../../core/constants/mask_shapes.dart';
import '../../../data/local/knowledge_graph_dao.dart';
import '../../../data/local/learning_path_dao.dart';
import '../../../data/models/learning_path_model.dart';
import '../../../services/auth_service.dart';
import '../../../services/knowledge_seed_service.dart';
import '../learning/learning_chain_page.dart';
import '../learning/video_page.dart';
import '../materials/resource_viewer_page.dart';
import 'graph_list_page.dart';
import 'graph_properties_page.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 概念类型颜色映射
// ══════════════════════════════════════════════════════════════════════════════

const _conceptTypeColors = {
  'concept': Color(0xFF9C27B0), // purple
  'technology': Color(0xFF2196F3), // blue
  'tool': Color(0xFFFF9800), // orange
  'framework': Color(0xFF4CAF50), // green
  'language': Color(0xFFF44336), // red
  'platform': Color(0xFF00BCD4), // cyan
  'pattern': Color(0xFF795548), // brown
};

const _conceptTypeLabels = {
  'concept': '概念',
  'technology': '技术',
  'tool': '工具',
  'framework': '框架',
  'language': '语言',
  'platform': '平台',
  'pattern': '模式',
};

// ══════════════════════════════════════════════════════════════════════════════
// 关系类型样式映射
// ══════════════════════════════════════════════════════════════════════════════

class _RelationStyle {
  final Color color;
  final String label;
  final bool dashed;
  const _RelationStyle(this.color, this.label, this.dashed);
}

const _relationStyles = <String, _RelationStyle>{
  'prerequisite': _RelationStyle(Color(0xFFE53935), '前置', false),
  'related_to': _RelationStyle(Color(0xFF9E9E9E), '关联', true),
  'part_of': _RelationStyle(Color(0xFF4CAF50), '组成', false),
  'compared_with': _RelationStyle(Color(0xFF2196F3), '对比', true),
  'applied_in': _RelationStyle(Color(0xFFFF9800), '应用', true),
  'builds_upon': _RelationStyle(Color(0xFF9C27B0), '递进', false),
  'alternative_to': _RelationStyle(Color(0xFF607D8B), '替代', true),
  'extends': _RelationStyle(Color(0xFF009688), '扩展', false),
};

// ══════════════════════════════════════════════════════════════════════════════
// 数据模型 — 力导向布局用
// ══════════════════════════════════════════════════════════════════════════════

class _ConceptNode {
  final int id;
  final String name;
  final String type;
  final int? chapter;
  final String importance;
  final String? description;
  final String? keywords;
  double x, y;
  double vx = 0, vy = 0;

  _ConceptNode({
    required this.id,
    required this.name,
    required this.type,
    this.chapter,
    this.importance = 'important',
    this.description,
    this.keywords,
    this.x = 0,
    this.y = 0,
  });

  double get radius {
    switch (importance) {
      case 'core':
        return 28;
      case 'important':
        return 22;
      case 'supplementary':
        return 16;
      default:
        return 22;
    }
  }

  Color get color =>
      _conceptTypeColors[type] ?? const Color(0xFF9E9E9E);

  factory _ConceptNode.fromMap(Map<String, dynamic> map) {
    return _ConceptNode(
      id: map['id'] as int,
      name: (map['concept_name'] ?? map['name'] ?? '') as String,
      type: (map['concept_type'] ?? map['type'] ?? 'concept') as String,
      chapter: map['chapter'] as int?,
      importance: (map['importance'] ?? 'important') as String,
      description: map['description'] as String?,
      keywords: map['keywords'] as String?,
    );
  }
}

class _ConceptEdge {
  final int id;
  final int sourceId;
  final int targetId;
  final String relationType;
  final String? label;
  final double weight;
  final bool bidirectional;
  final String? sourceName;
  final String? targetName;

  _ConceptEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.relationType,
    this.label,
    this.weight = 1.0,
    this.bidirectional = false,
    this.sourceName,
    this.targetName,
  });

  _RelationStyle get style =>
      _relationStyles[relationType] ??
      const _RelationStyle(Color(0xFF9E9E9E), '关联', true);

  factory _ConceptEdge.fromMap(Map<String, dynamic> map) {
    return _ConceptEdge(
      id: map['id'] as int,
      sourceId: (map['source_concept_id'] ?? map['source_id'] ?? 0) as int,
      targetId: (map['target_concept_id'] ?? map['target_id'] ?? 0) as int,
      relationType: (map['relation_type'] ?? 'related_to') as String,
      label: map['relation_label'] as String?,
      weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
      bidirectional: (map['bidirectional'] as int?) == 1,
      sourceName: map['source_name'] as String?,
      targetName: map['target_name'] as String?,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 视图模式枚举
// ══════════════════════════════════════════════════════════════════════════════

enum _ViewMode {
  global('全局视图', Icons.public),
  chapter('章节视图', Icons.view_module),
  relation('关系视图', Icons.device_hub),
  mask('蒙版视图', Icons.auto_awesome);

  final String label;
  final IconData icon;
  const _ViewMode(this.label, this.icon);
}

// ══════════════════════════════════════════════════════════════════════════════
// KnowledgeGraphPage
// ══════════════════════════════════════════════════════════════════════════════

class KnowledgeGraphPage extends StatefulWidget {
  const KnowledgeGraphPage({super.key});

  @override
  State<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends State<KnowledgeGraphPage>
    with TickerProviderStateMixin {
  final _dao = KnowledgeGraphDao();
  final _transformationController = TransformationController();

  // ── 数据 ────────────────────────────────────────────────────────────────
  List<_ConceptNode> _nodes = [];
  List<_ConceptEdge> _edges = [];
  bool _isLoading = true;
  bool _hasData = false;
  String? _errorMessage;

  // ── 视图状态 ─────────────────────────────────────────────────────────────
  _ViewMode _viewMode = _ViewMode.global;
  int? _chapterFilter; // null = 全部
  _ConceptNode? _selectedNode;
  Set<int> _highlightedNodeIds = {};
  Set<int> _adjacentNodeIds = {};
  Set<int> _adjacentEdgeIds = {};

  // ── 搜索 ────────────────────────────────────────────────────────────────
  bool _showSearch = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // ── 关系视图 ─────────────────────────────────────────────────────────────
  _ConceptNode? _focusedNode; // 关系视图中聚焦的节点
  int _focusDepth = 2;

  // ── 蒙版视图 ─────────────────────────────────────────────────────────────
  MaskShape _selectedMask = MaskShape.android;
  Path? _currentMaskPath; // 缓存当前蒙版路径

  // ── 统计 ────────────────────────────────────────────────────────────────
  Map<String, dynamic> _stats = {};

  // ── 学习路径 ────────────────────────────────────────────────────────────
  final _learningPathDao = LearningPathDao();
  final _authService = AuthService();

  // ── 画布参数 ─────────────────────────────────────────────────────────────
  static const double _canvasWidth = 2400;
  static const double _canvasHeight = 2000;

  // ── 动画 ────────────────────────────────────────────────────────────────
  late AnimationController _layoutAnimController;

  @override
  void initState() {
    super.initState();
    _layoutAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _initData();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _searchController.dispose();
    _layoutAnimController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 数据初始化与加载
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _initData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await KnowledgeSeedService().seedIfEmpty();
      await _loadData();
      await _loadStats();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载失败: $e';
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> conceptMaps;
      if (_chapterFilter != null) {
        conceptMaps = await _dao.getConceptsByChapter(_chapterFilter!);
      } else {
        conceptMaps = await _dao.getAllConcepts();
      }

      final allRelationMaps = <Map<String, dynamic>>[];
      final conceptIds = conceptMaps.map((c) => c['id'] as int).toSet();

      // 加载所有概念的关系
      for (final concept in conceptMaps) {
        final rels = await _dao.getRelationsForConcept(concept['id'] as int);
        for (final rel in rels) {
          final srcId = (rel['source_concept_id'] ?? 0) as int;
          final tgtId = (rel['target_concept_id'] ?? 0) as int;
          // 只保留两端都在当前概念集合中的关系
          if (conceptIds.contains(srcId) && conceptIds.contains(tgtId)) {
            // 去重
            if (!allRelationMaps.any((r) => r['id'] == rel['id'])) {
              allRelationMaps.add(rel);
            }
          }
        }
      }

      _nodes = conceptMaps.map((m) => _ConceptNode.fromMap(m)).toList();
      _edges = allRelationMaps.map((m) => _ConceptEdge.fromMap(m)).toList();
      _hasData = _nodes.isNotEmpty;

      if (_hasData) {
        _calculateLayout();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '加载数据失败: $e';
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      _stats = await _dao.getStats();
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 力导向布局算法
  // ══════════════════════════════════════════════════════════════════════════

  void _calculateLayout() {
    switch (_viewMode) {
      case _ViewMode.global:
        _calculateForceLayout(_nodes, _edges);
        break;
      case _ViewMode.chapter:
        _calculateChapterLayout(_nodes, _edges);
        break;
      case _ViewMode.relation:
        if (_focusedNode != null) {
          _calculateRelationLayout();
        } else {
          _calculateForceLayout(_nodes, _edges);
        }
        break;
      case _ViewMode.mask:
        _calculateMaskLayout();
        break;
    }
  }

  void _calculateForceLayout(
      List<_ConceptNode> nodes, List<_ConceptEdge> edges) {
    if (nodes.isEmpty) return;

    final rng = math.Random(42);
    final cx = _canvasWidth / 2;
    final cy = _canvasHeight / 2;
    final spreadRadius = math.min(_canvasWidth, _canvasHeight) * 0.35;

    // 初始化随机位置
    for (final node in nodes) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final r = rng.nextDouble() * spreadRadius;
      node.x = cx + r * math.cos(angle);
      node.y = cy + r * math.sin(angle);
      node.vx = 0;
      node.vy = 0;
    }

    // 构建邻接映射
    final nodeById = {for (final n in nodes) n.id: n};
    const iterations = 100;
    const kRepel = 120000.0;
    const kAttract = 0.004;
    const damping = 0.85;
    const maxVelocity = 15.0;

    for (int iter = 0; iter < iterations; iter++) {
      // 温度衰减
      final temperature = 1.0 - (iter / iterations) * 0.6;

      // 斥力：每对节点之间
      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          final ni = nodes[i];
          final nj = nodes[j];
          var dx = ni.x - nj.x;
          var dy = ni.y - nj.y;
          var dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 1) dist = 1;

          final force = kRepel / (dist * dist) * temperature;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;

          ni.vx += fx;
          ni.vy += fy;
          nj.vx -= fx;
          nj.vy -= fy;
        }
      }

      // 引力：沿边
      for (final edge in edges) {
        final src = nodeById[edge.sourceId];
        final tgt = nodeById[edge.targetId];
        if (src == null || tgt == null) continue;

        var dx = tgt.x - src.x;
        var dy = tgt.y - src.y;
        var dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1) dist = 1;

        final idealDist = 180.0 * (1.0 / edge.weight.clamp(0.1, 3.0));
        final force = kAttract * (dist - idealDist) * temperature;
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;

        src.vx += fx;
        src.vy += fy;
        tgt.vx -= fx;
        tgt.vy -= fy;
      }

      // 更新位置
      for (final node in nodes) {
        node.vx *= damping;
        node.vy *= damping;

        // 限速
        final speed = math.sqrt(node.vx * node.vx + node.vy * node.vy);
        if (speed > maxVelocity) {
          node.vx = (node.vx / speed) * maxVelocity;
          node.vy = (node.vy / speed) * maxVelocity;
        }

        node.x += node.vx;
        node.y += node.vy;

        // 边界约束
        final margin = node.radius + 40;
        node.x = node.x.clamp(margin, _canvasWidth - margin);
        node.y = node.y.clamp(margin, _canvasHeight - margin);
      }
    }
  }

  void _calculateChapterLayout(
      List<_ConceptNode> nodes, List<_ConceptEdge> edges) {
    if (nodes.isEmpty) return;

    // 按章节分组
    final byChapter = <int, List<_ConceptNode>>{};
    for (final node in nodes) {
      final ch = node.chapter ?? 0;
      byChapter.putIfAbsent(ch, () => []).add(node);
    }

    final chapters = byChapter.keys.toList()..sort();
    final numClusters = chapters.length;
    if (numClusters == 0) return;

    // 各章节集群中心位置 — 使用网格布局
    final cols = (math.sqrt(numClusters)).ceil();
    final rows = (numClusters / cols).ceil();
    final cellW = _canvasWidth / (cols + 1);
    final cellH = _canvasHeight / (rows + 1);

    final clusterCenters = <int, Offset>{};
    for (int i = 0; i < chapters.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      clusterCenters[chapters[i]] = Offset(
        cellW * (col + 1),
        cellH * (row + 1),
      );
    }

    // 每个集群内做小范围力导向布局
    final rng = math.Random(42);
    for (final entry in byChapter.entries) {
      final center = clusterCenters[entry.key]!;
      final clusterNodes = entry.value;
      final clusterRadius =
          math.min(cellW, cellH) * 0.35;

      // 初始化
      for (final node in clusterNodes) {
        final angle = rng.nextDouble() * 2 * math.pi;
        final r = rng.nextDouble() * clusterRadius * 0.6;
        node.x = center.dx + r * math.cos(angle);
        node.y = center.dy + r * math.sin(angle);
        node.vx = 0;
        node.vy = 0;
      }

      // 集群内的边
      final clusterIds = clusterNodes.map((n) => n.id).toSet();
      final clusterEdges = edges
          .where((e) =>
              clusterIds.contains(e.sourceId) &&
              clusterIds.contains(e.targetId))
          .toList();

      // 小规模力导向
      _runMiniForceLayout(
          clusterNodes, clusterEdges, center, clusterRadius, 60);
    }
  }

  void _runMiniForceLayout(
    List<_ConceptNode> nodes,
    List<_ConceptEdge> edges,
    Offset center,
    double maxRadius,
    int iterations,
  ) {
    final nodeById = {for (final n in nodes) n.id: n};
    const kRepel = 30000.0;
    const kAttract = 0.008;
    const damping = 0.8;

    for (int iter = 0; iter < iterations; iter++) {
      final temp = 1.0 - (iter / iterations) * 0.5;

      for (int i = 0; i < nodes.length; i++) {
        for (int j = i + 1; j < nodes.length; j++) {
          var dx = nodes[i].x - nodes[j].x;
          var dy = nodes[i].y - nodes[j].y;
          var dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 1) dist = 1;
          final force = kRepel / (dist * dist) * temp;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          nodes[i].vx += fx;
          nodes[i].vy += fy;
          nodes[j].vx -= fx;
          nodes[j].vy -= fy;
        }
      }

      for (final edge in edges) {
        final src = nodeById[edge.sourceId];
        final tgt = nodeById[edge.targetId];
        if (src == null || tgt == null) continue;
        var dx = tgt.x - src.x;
        var dy = tgt.y - src.y;
        var dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1) dist = 1;
        final force = kAttract * (dist - 100) * temp;
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;
        src.vx += fx;
        src.vy += fy;
        tgt.vx -= fx;
        tgt.vy -= fy;
      }

      // 向中心的引力
      for (final node in nodes) {
        final dx = center.dx - node.x;
        final dy = center.dy - node.y;
        node.vx += dx * 0.001 * temp;
        node.vy += dy * 0.001 * temp;

        node.vx *= damping;
        node.vy *= damping;
        node.x += node.vx;
        node.y += node.vy;

        // 约束在集群范围内
        final distFromCenter = math.sqrt(
            math.pow(node.x - center.dx, 2) +
                math.pow(node.y - center.dy, 2));
        if (distFromCenter > maxRadius) {
          final angle =
              math.atan2(node.y - center.dy, node.x - center.dx);
          node.x = center.dx + maxRadius * math.cos(angle);
          node.y = center.dy + maxRadius * math.sin(angle);
        }
      }
    }
  }

  void _calculateRelationLayout() {
    if (_focusedNode == null || _nodes.isEmpty) return;

    final focus = _focusedNode!;
    final center = Offset(_canvasWidth / 2, _canvasHeight / 2);
    focus.x = center.dx;
    focus.y = center.dy;

    // 收集 N 跳内的节点
    final visited = <int>{focus.id};
    var frontier = <int>{focus.id};
    final layerNodes = <int, Set<int>>{0: {focus.id}};

    for (int depth = 1; depth <= _focusDepth; depth++) {
      final nextFrontier = <int>{};
      for (final nid in frontier) {
        for (final edge in _edges) {
          int? neighbor;
          if (edge.sourceId == nid && !visited.contains(edge.targetId)) {
            neighbor = edge.targetId;
          } else if (edge.targetId == nid &&
              !visited.contains(edge.sourceId)) {
            neighbor = edge.sourceId;
          }
          if (neighbor != null) {
            visited.add(neighbor);
            nextFrontier.add(neighbor);
            layerNodes.putIfAbsent(depth, () => {}).add(neighbor);
          }
        }
      }
      frontier = nextFrontier;
    }

    // 同心圆布局
    final nodeById = {for (final n in _nodes) n.id: n};
    for (final entry in layerNodes.entries) {
      if (entry.key == 0) continue;
      final ring = entry.value.toList();
      final ringRadius = entry.key * 250.0;
      for (int i = 0; i < ring.length; i++) {
        final angle = (i / ring.length) * 2 * math.pi - math.pi / 2;
        final node = nodeById[ring[i]];
        if (node != null) {
          node.x = center.dx + ringRadius * math.cos(angle);
          node.y = center.dy + ringRadius * math.sin(angle);
        }
      }
    }

    // 隐藏不在范围内的节点（不修改 _nodes，通过过滤显示）
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 蒙版布局 — 节点按Logo轮廓分布
  // ══════════════════════════════════════════════════════════════════════════

  void _calculateMaskLayout() {
    if (_nodes.isEmpty || _selectedMask == MaskShape.none) {
      _calculateForceLayout(_nodes, _edges);
      return;
    }

    final maskPath = MaskShapeBuilder.getPath(
      _selectedMask, _canvasWidth, _canvasHeight,
    );
    _currentMaskPath = maskPath;

    // 初始化：在蒙版内采样节点位置
    final initPositions = MaskShapeBuilder.samplePoints(
      _selectedMask, _canvasWidth, _canvasHeight, _nodes.length,
    );

    for (int i = 0; i < _nodes.length; i++) {
      if (i < initPositions.length) {
        _nodes[i].x = initPositions[i].dx;
        _nodes[i].y = initPositions[i].dy;
      } else {
        _nodes[i].x = _canvasWidth / 2;
        _nodes[i].y = _canvasHeight / 2;
      }
      _nodes[i].vx = 0;
      _nodes[i].vy = 0;
    }

    // 力导向布局（带蒙版约束）
    final bounds = maskPath.getBounds();
    const iterations = 80;
    const kRepel = 80000.0;
    const kAttract = 0.005;
    const damping = 0.82;
    const maxVelocity = 12.0;

    for (int iter = 0; iter < iterations; iter++) {
      final temperature = 1.0 - (iter / iterations) * 0.6;

      // Coulomb 斥力
      for (int i = 0; i < _nodes.length; i++) {
        for (int j = i + 1; j < _nodes.length; j++) {
          final dx = _nodes[i].x - _nodes[j].x;
          final dy = _nodes[i].y - _nodes[j].y;
          final dist = math.sqrt(dx * dx + dy * dy).clamp(10.0, 1000.0);
          final force = kRepel / (dist * dist) * temperature;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          _nodes[i].vx += fx;
          _nodes[i].vy += fy;
          _nodes[j].vx -= fx;
          _nodes[j].vy -= fy;
        }
      }

      // 弹簧引力（边）
      for (final edge in _edges) {
        final src = _nodes.where((n) => n.id == edge.sourceId).firstOrNull;
        final tgt = _nodes.where((n) => n.id == edge.targetId).firstOrNull;
        if (src == null || tgt == null) continue;

        final dx = tgt.x - src.x;
        final dy = tgt.y - src.y;
        final dist = math.sqrt(dx * dx + dy * dy).clamp(1.0, 1000.0);
        final idealDist = 120.0 / edge.weight.clamp(0.1, 3.0);
        final force = kAttract * (dist - idealDist) * temperature;
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;
        src.vx += fx;
        src.vy += fy;
        tgt.vx -= fx;
        tgt.vy -= fy;
      }

      // 向蒙版中心的微弱引力（防止节点飞出）
      final center = bounds.center;
      for (final node in _nodes) {
        final dx = center.dx - node.x;
        final dy = center.dy - node.y;
        node.vx += dx * 0.0005 * temperature;
        node.vy += dy * 0.0005 * temperature;
      }

      // 更新位置 + 蒙版约束
      for (final node in _nodes) {
        node.vx *= damping;
        node.vy *= damping;
        final speed = math.sqrt(node.vx * node.vx + node.vy * node.vy);
        if (speed > maxVelocity) {
          node.vx = node.vx / speed * maxVelocity;
          node.vy = node.vy / speed * maxVelocity;
        }
        node.x += node.vx;
        node.y += node.vy;

        // 蒙版约束：将节点拉回蒙版内
        final pos = Offset(node.x, node.y);
        if (!maskPath.contains(pos)) {
          final constrained = MaskShapeBuilder.constrainToMask(
            pos, maskPath, bounds,
          );
          node.x = constrained.dx;
          node.y = constrained.dy;
          node.vx *= 0.3;
          node.vy *= 0.3;
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 交互操作
  // ══════════════════════════════════════════════════════════════════════════

  void _handleTap(Offset localPosition) {
    final matrix = _transformationController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, localPosition);

    for (final node in _nodes) {
      final dist = (Offset(node.x, node.y) - canvasPos).distance;
      if (dist < node.radius + 8) {
        _selectNode(node);
        return;
      }
    }

    // 点击空白取消选择
    setState(() {
      _selectedNode = null;
      _adjacentNodeIds = {};
      _adjacentEdgeIds = {};
    });
  }

  void _handleDoubleTap(Offset localPosition) {
    final matrix = _transformationController.value.clone()..invert();
    final canvasPos = MatrixUtils.transformPoint(matrix, localPosition);

    for (final node in _nodes) {
      final dist = (Offset(node.x, node.y) - canvasPos).distance;
      if (dist < node.radius + 8) {
        // 双击：聚焦到该节点的关系网络
        _focusOnNode(node);
        return;
      }
    }
  }

  void _selectNode(_ConceptNode node) {
    setState(() {
      _selectedNode = node;
      _adjacentNodeIds = {};
      _adjacentEdgeIds = {};

      for (final edge in _edges) {
        if (edge.sourceId == node.id) {
          _adjacentNodeIds.add(edge.targetId);
          _adjacentEdgeIds.add(edge.id);
        }
        if (edge.targetId == node.id) {
          _adjacentNodeIds.add(edge.sourceId);
          _adjacentEdgeIds.add(edge.id);
        }
      }
    });

    _showNodeDetailSheet(node);
  }

  void _focusOnNode(_ConceptNode node) {
    setState(() {
      _viewMode = _ViewMode.relation;
      _focusedNode = node;
      _selectedNode = node;
    });
    _calculateLayout();
    setState(() {});

    // 居中视图
    _animateCenterOnNode(node.x, node.y, scale: 0.8);
  }

  void _animateCenterOnNode(double targetX, double targetY,
      {double scale = 1.2}) {
    final screenSize = MediaQuery.of(context).size;

    final endMatrix = Matrix4.identity()
      ..scale(scale)
      ..translate(
        -targetX + screenSize.width / (2 * scale),
        -targetY + screenSize.height / (2 * scale),
      );

    final startMatrix = _transformationController.value.clone();
    final controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    final animation =
        CurvedAnimation(parent: controller, curve: Curves.easeInOut);

    animation.addListener(() {
      final t = animation.value;
      final m = Matrix4.zero();
      for (int i = 0; i < 16; i++) {
        m.storage[i] = startMatrix.storage[i] +
            (endMatrix.storage[i] - startMatrix.storage[i]) * t;
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

  // ── 搜索 ────────────────────────────────────────────────────────────────

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _highlightedNodeIds = {};
      } else {
        _highlightedNodeIds = _nodes
            .where((n) =>
                n.name.toLowerCase().contains(query.toLowerCase()) ||
                (n.description ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()) ||
                (n.keywords ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()))
            .map((n) => n.id)
            .toSet();
      }
    });
  }

  void _scrollToFirstMatch() {
    if (_highlightedNodeIds.isEmpty) return;
    final firstId = _highlightedNodeIds.first;
    final node = _nodes.firstWhere((n) => n.id == firstId);
    _animateCenterOnNode(node.x, node.y, scale: 1.5);
    _selectNode(node);
  }

  // ── 章节过滤 ─────────────────────────────────────────────────────────────

  void _setChapterFilter(int? chapter) {
    setState(() {
      _chapterFilter = chapter;
      _selectedNode = null;
      _adjacentNodeIds = {};
      _adjacentEdgeIds = {};
    });
    _loadData();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 对话框与底部弹出
  // ══════════════════════════════════════════════════════════════════════════

  void _showStatsDialog() {
    final conceptCount = _stats['concept_count'] ?? _nodes.length;
    final relationCount = _stats['relation_count'] ?? _edges.length;
    final typeDistribution =
        _stats['type_distribution'] as Map<String, int>? ?? {};
    final chapterDistribution =
        _stats['chapter_distribution'] as Map<int, int>? ?? {};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Color(0xFF667eea)),
            SizedBox(width: 8),
            Text('知识图谱统计'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 概要统计卡
                Row(
                  children: [
                    _buildStatCard('概念', '$conceptCount', const Color(0xFF667eea)),
                    const SizedBox(width: 8),
                    _buildStatCard(
                        '关系', '$relationCount', const Color(0xFF4CAF50)),
                    const SizedBox(width: 8),
                    _buildStatCard(
                      '类型',
                      '${typeDistribution.length}',
                      const Color(0xFFFF9800),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('概念类型分布',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...typeDistribution.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _conceptTypeColors[e.key] ??
                                  Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                _conceptTypeLabels[e.key] ?? e.key),
                          ),
                          Text('${e.value}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )),
                if (chapterDistribution.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('章节分布',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...chapterDistribution.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.book,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(child: Text('第 ${e.key} 章')),
                            Text('${e.value} 个概念',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  void _showChapterFilterMenu() {
    final chapters = [null, 1, 2, 3, 4, 5, 6];
    final labels = ['全部', '第1章', '第2章', '第3章', '第4章', '第5章', '第6章'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('章节筛选',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(chapters.length, (i) {
                final isSelected = _chapterFilter == chapters[i];
                return ChoiceChip(
                  label: Text(labels[i]),
                  selected: isSelected,
                  selectedColor:
                      const Color(0xFF667eea).withValues(alpha: 0.2),
                  onSelected: (_) {
                    Navigator.pop(ctx);
                    _setChapterFilter(chapters[i]);
                  },
                );
              }),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── 节点详情底部弹出 ─────────────────────────────────────────────────────

  void _showNodeDetailSheet(_ConceptNode node) {
    // 收集关系
    final outgoing = <_ConceptEdge>[];
    final incoming = <_ConceptEdge>[];
    for (final edge in _edges) {
      if (edge.sourceId == node.id) outgoing.add(edge);
      if (edge.targetId == node.id) incoming.add(edge);
    }

    // 按关系类型分组
    final groupedRelations = <String, List<Map<String, dynamic>>>{};
    for (final edge in outgoing) {
      final typeLabel = edge.style.label;
      groupedRelations.putIfAbsent(typeLabel, () => []).add({
        'name': edge.targetName ?? edge.label ?? '概念 ${edge.targetId}',
        'id': edge.targetId,
        'direction': '→',
      });
    }
    for (final edge in incoming) {
      final typeLabel = edge.style.label;
      groupedRelations.putIfAbsent(typeLabel, () => []).add({
        'name': edge.sourceName ?? edge.label ?? '概念 ${edge.sourceId}',
        'id': edge.sourceId,
        'direction': '←',
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 拖拽指示条
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // 标题行
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: node.color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: node.color.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          node.name.isNotEmpty
                              ? node.name.substring(0, 1)
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildBadge(
                                _conceptTypeLabels[node.type] ??
                                    node.type,
                                node.color,
                              ),
                              const SizedBox(width: 6),
                              if (node.chapter != null)
                                _buildBadge(
                                  '第${node.chapter}章',
                                  const Color(0xFF667eea),
                                ),
                              const SizedBox(width: 6),
                              _buildBadge(
                                node.importance == 'core'
                                    ? '核心'
                                    : node.importance == 'important'
                                        ? '重要'
                                        : '补充',
                                node.importance == 'core'
                                    ? const Color(0xFFF44336)
                                    : node.importance == 'important'
                                        ? const Color(0xFFFF9800)
                                        : Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 描述
                if (node.description != null &&
                    node.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      node.description!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],

                // 关键词
                if (node.keywords != null &&
                    node.keywords!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: node.keywords!.split(',').map((kw) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF667eea)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF667eea)
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          kw.trim(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667eea),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // 关系列表
                if (groupedRelations.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    '关联概念',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...groupedRelations.entries.map((entry) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        ...entry.value.map((rel) {
                          return InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              final targetNode = _nodes
                                  .where((n) => n.id == rel['id'])
                                  .firstOrNull;
                              if (targetNode != null) {
                                _animateCenterOnNode(
                                    targetNode.x, targetNode.y);
                                _selectNode(targetNode);
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  Text(
                                    rel['direction'] as String,
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      rel['name'] as String,
                                      style: const TextStyle(
                                          fontSize: 14),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],

                // ── 资源链接 ─────────────────────────────────────────
                if (node.chapter != null) ...[
                  const SizedBox(height: 16),
                  const Text('相关资源',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
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
                                  filterChapter: _chapterName(node.chapter!),
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
                                  filterChapter: _chapterName(node.chapter!),
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
                                  filterChapter: _chapterName(node.chapter!),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],

                // ── 学习链路入口 ─────────────────────────────────────
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LearningChainPage(
                            conceptId: node.id,
                            conceptName: node.name,
                            chapter: node.chapter,
                            description: node.description,
                            keywords: node.keywords,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('打开学习链路'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _generatePathFromNode(node);
                    },
                    icon: const Icon(Icons.route, size: 18),
                    label: const Text('生成学习路径'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                // 查看前置链
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showPrerequisiteChain(node);
                    },
                    icon: const Icon(Icons.account_tree, size: 18),
                    label: const Text('查看前置链'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF667eea),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _focusOnNode(node);
                    },
                    icon: const Icon(Icons.device_hub, size: 18),
                    label: const Text('聚焦关系网络'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF667eea),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ── 前置链追踪 ──────────────────────────────────────────────────────────

  void _showPrerequisiteChain(_ConceptNode startNode) {
    // BFS 反向追溯前置关系
    final chain = <_ConceptNode>[startNode];
    final visited = <int>{startNode.id};
    var current = startNode;
    final nodeById = {for (final n in _nodes) n.id: n};

    // 递归寻找前置
    bool findNext = true;
    while (findNext) {
      findNext = false;
      for (final edge in _edges) {
        if (edge.relationType == 'prerequisite' &&
            edge.targetId == current.id &&
            !visited.contains(edge.sourceId)) {
          final prereq = nodeById[edge.sourceId];
          if (prereq != null) {
            chain.add(prereq);
            visited.add(prereq.id);
            current = prereq;
            findNext = true;
            break;
          }
        }
      }
    }

    // 反转：从前置到当前
    final reversedChain = chain.reversed.toList();

    // 高亮前置链的节点
    setState(() {
      _highlightedNodeIds = reversedChain.map((n) => n.id).toSet();
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.account_tree, color: Color(0xFFE53935)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${startNode.name} 的前置链',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: reversedChain.length <= 1
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('该概念没有前置依赖',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: reversedChain.length,
                  itemBuilder: (context, index) {
                    final node = reversedChain[index];
                    final isLast = index == reversedChain.length - 1;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isLast
                                    ? const Color(0xFFE53935)
                                    : node.color,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            if (!isLast)
                              Container(
                                width: 2,
                                height: 24,
                                color: Colors.grey.shade300,
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  node.name,
                                  style: TextStyle(
                                    fontWeight: isLast
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  _conceptTypeLabels[node.type] ??
                                      node.type,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _highlightedNodeIds = {});
            },
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 学习路径生成
  // ══════════════════════════════════════════════════════════════════════════

  String _chapterName(int chapter) {
    const names = {
      1: '第一章',
      2: '第二章',
      3: '第三章',
      4: '第四章',
      5: '第五章',
      6: '第六章',
    };
    return names[chapter] ?? '第$chapter章';
  }

  /// 从选中概念开始，沿 prerequisite 链向前追溯生成学习路径
  Future<void> _generatePathFromNode(_ConceptNode node) async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录')),
        );
      }
      return;
    }

    // BFS 反向追溯所有前置概念
    final chain = <_ConceptNode>[node];
    final visited = <int>{node.id};
    final nodeById = {for (final n in _nodes) n.id: n};
    var current = node;

    bool findNext = true;
    while (findNext) {
      findNext = false;
      for (final edge in _edges) {
        if (edge.relationType == 'prerequisite' &&
            edge.targetId == current.id &&
            !visited.contains(edge.sourceId)) {
          final prereq = nodeById[edge.sourceId];
          if (prereq != null) {
            chain.add(prereq);
            visited.add(prereq.id);
            current = prereq;
            findNext = true;
            break;
          }
        }
      }
    }

    final reversedChain = chain.reversed.toList();

    // 也收集该概念的相关概念（related_to, builds_upon）
    final related = <_ConceptNode>[];
    for (final edge in _edges) {
      if (edge.sourceId == node.id &&
          (edge.relationType == 'related_to' ||
              edge.relationType == 'builds_upon') &&
          !visited.contains(edge.targetId)) {
        final r = nodeById[edge.targetId];
        if (r != null) {
          related.add(r);
          visited.add(r.id);
        }
      }
    }

    // 构建路径节点列表：前置链 + 目标 + 相关拓展
    final pathNodes = [...reversedChain, ...related];
    final nodeIds = pathNodes.map((n) => 'c_${n.id}').toList();

    final path = LearningPathModel(
      userId: userId,
      title: '${node.name} 学习路径',
      description:
          '基于前置关系自动生成 · ${reversedChain.length}个前置概念 · ${related.length}个拓展概念',
      nodeIds: nodeIds,
      progress: 0,
      status: 'active',
    );

    try {
      await _learningPathDao.createPath(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已生成「${node.name}」学习路径（${pathNodes.length}个概念）'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () {
                // 切换到路径tab（index=2 in HomePage）
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成路径失败: $e')),
        );
      }
    }
  }

  /// 智能推荐：为所有"核心"概念自动生成学习路径
  Future<void> _generateRecommendedPaths() async {
    final userId = _authService.getCurrentUserId();
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录')),
        );
      }
      return;
    }

    // 找到所有核心概念
    final coreNodes =
        _nodes.where((n) => n.importance == 'core').toList();
    if (coreNodes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无核心概念')),
        );
      }
      return;
    }

    // 检查是否已有推荐路径
    final existing = await _learningPathDao.getPathsByUser(userId);
    final existingTitles = existing.map((p) => p.title).toSet();

    int created = 0;
    for (final core in coreNodes) {
      final pathTitle = '${core.name} 学习路径';
      if (existingTitles.contains(pathTitle)) continue;

      // BFS 前置链
      final chain = <_ConceptNode>[core];
      final visited = <int>{core.id};
      final nodeById = {for (final n in _nodes) n.id: n};
      var current = core;

      bool findNext = true;
      while (findNext) {
        findNext = false;
        for (final edge in _edges) {
          if (edge.relationType == 'prerequisite' &&
              edge.targetId == current.id &&
              !visited.contains(edge.sourceId)) {
            final prereq = nodeById[edge.sourceId];
            if (prereq != null) {
              chain.add(prereq);
              visited.add(prereq.id);
              current = prereq;
              findNext = true;
              break;
            }
          }
        }
      }

      final pathNodes = chain.reversed.toList();
      if (pathNodes.length < 2) continue; // 无前置依赖，跳过

      final nodeIds = pathNodes.map((n) => 'c_${n.id}').toList();
      final path = LearningPathModel(
        userId: userId,
        title: pathTitle,
        description: '自动推荐 · ${pathNodes.length}个概念 · 基于前置关系链',
        nodeIds: nodeIds,
        progress: 0,
        status: 'active',
      );

      try {
        await _learningPathDao.createPath(path);
        created++;
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(created > 0
              ? '已生成 $created 条推荐学习路径'
              : '所有推荐路径已存在'),
        ),
      );
    }
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
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build — 主界面
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoadingView()
          : _errorMessage != null
              ? _buildErrorView()
              : !_hasData
                  ? _buildEmptyView()
                  : _buildMainContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _showSearch
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索概念...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.white70),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: _performSearch,
            )
          : const Text('知识图谱'),
      actions: [
        // 搜索
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          tooltip: '搜索概念',
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                _performSearch('');
              }
            });
          },
        ),
        // 章节筛选
        IconButton(
          icon: Badge(
            isLabelVisible: _chapterFilter != null,
            label: _chapterFilter != null
                ? Text('${_chapterFilter}')
                : null,
            child: const Icon(Icons.filter_list),
          ),
          tooltip: '章节筛选',
          onPressed: _showChapterFilterMenu,
        ),
        // 统计
        IconButton(
          icon: const Icon(Icons.analytics_outlined),
          tooltip: '统计信息',
          onPressed: () async {
            await _loadStats();
            _showStatsDialog();
          },
        ),
        // 更多
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多',
          onSelected: (value) {
            if (value == 'structure') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GraphListPage()),
              );
            } else if (value == 'recommend') {
              _generateRecommendedPaths();
            } else if (value == 'properties') {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const GraphPropertiesPage()),
              ).then((_) => _loadData());
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'structure',
              child: ListTile(
                leading: Icon(Icons.account_tree, color: Colors.teal),
                title: Text('结构视图'),
                subtitle: Text('查看章节层级结构', style: TextStyle(fontSize: 11)),
              ),
            ),
            const PopupMenuItem(
              value: 'recommend',
              child: ListTile(
                leading: Icon(Icons.route, color: Colors.orange),
                title: Text('生成推荐路径'),
                subtitle: Text('基于前置关系自动生成', style: TextStyle(fontSize: 11)),
              ),
            ),
            const PopupMenuItem(
              value: 'properties',
              child: ListTile(
                leading: Icon(Icons.table_chart, color: Color(0xFF667eea)),
                title: Text('属性管理'),
                subtitle: Text('查看和编辑节点/关系', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF667eea)),
          SizedBox(height: 16),
          Text(
            '正在加载知识图谱...',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _initData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无知识图谱数据',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮初始化知识图谱',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _initData,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('初始化知识图谱'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF667eea),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // 视图切换
        _buildViewModeSelector(),

        // 蒙版选择器（蒙版视图时显示）
        if (_viewMode == _ViewMode.mask) _buildMaskSelector(),

        // 搜索结果提示
        if (_highlightedNodeIds.isNotEmpty) _buildSearchResultBar(),

        // 章节筛选提示条
        if (_chapterFilter != null) _buildFilterBar(),

        // 关系视图信息条
        if (_viewMode == _ViewMode.relation && _focusedNode != null)
          _buildRelationInfoBar(),

        // 图谱画布
        Expanded(child: _buildGraphCanvas()),

        // 底部图例
        _buildLegendBar(),
      ],
    );
  }

  // ── 视图模式选择器 ─────────────────────────────────────────────────────

  Widget _buildViewModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_ViewMode>(
              segments: _ViewMode.values.map((mode) {
                return ButtonSegment(
                  value: mode,
                  label: Text(mode.label, style: const TextStyle(fontSize: 13)),
                  icon: Icon(mode.icon, size: 16),
                );
              }).toList(),
              selected: {_viewMode},
              onSelectionChanged: (modes) {
                setState(() {
                  _viewMode = modes.first;
                  if (_viewMode != _ViewMode.relation) {
                    _focusedNode = null;
                  }
                });
                _calculateLayout();
                setState(() {});
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 蒙版形状选择器 ───────────────────────────────────────────────────────

  Widget _buildMaskSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.deepPurple.withValues(alpha: 0.05),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: Colors.deepPurple),
          const SizedBox(width: 8),
          const Text(
            '蒙版:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MaskShape.values
                    .where((s) => s != MaskShape.none)
                    .map((shape) {
                  final isSelected = _selectedMask == shape;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        shape.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: Colors.deepPurple,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: isSelected
                            ? Colors.deepPurple
                            : Colors.grey.shade300,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        setState(() => _selectedMask = shape);
                        _calculateLayout();
                        setState(() {});
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 搜索结果提示条 ─────────────────────────────────────────────────────

  Widget _buildSearchResultBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF667eea).withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Color(0xFF667eea)),
          const SizedBox(width: 6),
          Text(
            '找到 ${_highlightedNodeIds.length} 个匹配概念',
            style: const TextStyle(fontSize: 13, color: Color(0xFF667eea)),
          ),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.my_location, size: 14),
            label: const Text('定位', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF667eea),
            ),
            onPressed: _scrollToFirstMatch,
          ),
        ],
      ),
    );
  }

  // ── 筛选提示条 ──────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFFF9800).withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 16, color: Color(0xFFFF9800)),
          const SizedBox(width: 6),
          Text(
            '当前筛选: 第 $_chapterFilter 章 · ${_nodes.length} 个概念',
            style: const TextStyle(fontSize: 13, color: Color(0xFFFF9800)),
          ),
          const Spacer(),
          InkWell(
            onTap: () => _setChapterFilter(null),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: Color(0xFFFF9800)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 关系视图信息条 ─────────────────────────────────────────────────────

  Widget _buildRelationInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF9C27B0).withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.device_hub, size: 16, color: Color(0xFF9C27B0)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '聚焦: ${_focusedNode!.name} · 深度 $_focusDepth',
              style: const TextStyle(fontSize: 13, color: Color(0xFF9C27B0)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 深度调整
          InkWell(
            onTap: () {
              if (_focusDepth > 1) {
                setState(() => _focusDepth--);
                _calculateLayout();
                setState(() {});
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.remove_circle_outline,
                  size: 18,
                  color: _focusDepth > 1
                      ? const Color(0xFF9C27B0)
                      : Colors.grey),
            ),
          ),
          Text('$_focusDepth',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF9C27B0))),
          InkWell(
            onTap: () {
              if (_focusDepth < 4) {
                setState(() => _focusDepth++);
                _calculateLayout();
                setState(() {});
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.add_circle_outline,
                  size: 18,
                  color: _focusDepth < 4
                      ? const Color(0xFF9C27B0)
                      : Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() {
                _viewMode = _ViewMode.global;
                _focusedNode = null;
              });
              _calculateLayout();
              setState(() {});
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(Icons.close, size: 16, color: Color(0xFF9C27B0)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 图谱画布 ──────────────────────────────────────────────────────────

  Widget _buildGraphCanvas() {
    // 在关系视图下过滤显示的节点和边
    List<_ConceptNode> visibleNodes;
    List<_ConceptEdge> visibleEdges;

    if (_viewMode == _ViewMode.relation && _focusedNode != null) {
      // 收集焦点节点 N 跳范围内的节点
      final reachable = <int>{_focusedNode!.id};
      var frontier = <int>{_focusedNode!.id};
      for (int d = 0; d < _focusDepth; d++) {
        final next = <int>{};
        for (final nid in frontier) {
          for (final e in _edges) {
            if (e.sourceId == nid && !reachable.contains(e.targetId)) {
              reachable.add(e.targetId);
              next.add(e.targetId);
            }
            if (e.targetId == nid && !reachable.contains(e.sourceId)) {
              reachable.add(e.sourceId);
              next.add(e.sourceId);
            }
          }
        }
        frontier = next;
      }
      visibleNodes = _nodes.where((n) => reachable.contains(n.id)).toList();
      visibleEdges = _edges
          .where((e) =>
              reachable.contains(e.sourceId) &&
              reachable.contains(e.targetId))
          .toList();
    } else {
      visibleNodes = _nodes;
      visibleEdges = _edges;
    }

    return Stack(
      children: [
        Container(
          color: const Color(0xFFF8FAFE),
          child: GestureDetector(
            onTapDown: (d) => _handleTap(d.localPosition),
            onDoubleTapDown: (d) => _handleDoubleTap(d.localPosition),
            child: InteractiveViewer(
              transformationController: _transformationController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(200),
              minScale: 0.08,
              maxScale: 4.0,
              child: CustomPaint(
                painter: _KnowledgeGraphPainter(
                  nodes: visibleNodes,
                  edges: visibleEdges,
                  selectedNode: _selectedNode,
                  highlightedNodeIds: _highlightedNodeIds,
                  adjacentNodeIds: _adjacentNodeIds,
                  adjacentEdgeIds: _adjacentEdgeIds,
                  focusedNode: _focusedNode,
                  viewMode: _viewMode,
                  maskShape: _selectedMask,
                  maskPath: _currentMaskPath,
                ),
                size: const Size(_canvasWidth, _canvasHeight),
              ),
            ),
          ),
        ),
        // ── 鹰眼小地图 ──
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildMinimap(visibleNodes, visibleEdges),
        ),
      ],
    );
  }

  // ── 鹰眼小地图 ──────────────────────────────────────────────────────────

  Widget _buildMinimap(
      List<_ConceptNode> visibleNodes, List<_ConceptEdge> visibleEdges) {
    const mapW = 140.0;
    const mapH = 120.0;
    final scaleX = mapW / _canvasWidth;
    final scaleY = mapH / _canvasHeight;

    return GestureDetector(
      onTapDown: (details) {
        // 点击小地图定位
        final tapX = details.localPosition.dx / scaleX;
        final tapY = details.localPosition.dy / scaleY;
        _animateCenterOnNode(tapX, tapY);
      },
      onPanUpdate: (details) {
        // 拖拽小地图定位
        final tapX = details.localPosition.dx / scaleX;
        final tapY = details.localPosition.dy / scaleY;
        _animateCenterOnNode(tapX, tapY);
      },
      child: AnimatedBuilder(
        animation: _transformationController,
        builder: (context, child) {
          // 计算当前视口在画布上的位置
          final matrix = _transformationController.value;
          final inv = Matrix4.inverted(matrix);
          // 获取当前组件尺寸（使用 LayoutBuilder 的 context）
          final renderBox = context.findRenderObject() as RenderBox?;
          final parentSize = renderBox?.size ?? const Size(400, 600);

          // 视口在画布坐标中的矩形
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
                painter: _MinimapPainter(
                  nodes: visibleNodes,
                  edges: visibleEdges,
                  canvasWidth: _canvasWidth,
                  canvasHeight: _canvasHeight,
                  viewportRect: Rect.fromLTRB(vpLeft, vpTop, vpRight, vpBottom),
                  maskPath: _viewMode == _ViewMode.mask ? _currentMaskPath : null,
                ),
                size: const Size(mapW, mapH),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 底部图例 ──────────────────────────────────────────────────────────

  Widget _buildLegendBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 概念类型
          SizedBox(
            height: 24,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('概念:',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600)),
                ),
                ..._conceptTypeColors.entries.map((e) => _legendItem(
                      e.value,
                      _conceptTypeLabels[e.key] ?? e.key,
                      isCircle: true,
                    )),
                const SizedBox(width: 12),
                const Text('关系:',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                ..._relationStyles.entries.take(5).map((e) => _legendItem(
                      e.value.color,
                      e.value.label,
                      isCircle: false,
                      dashed: e.value.dashed,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label,
      {bool isCircle = true, bool dashed = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCircle)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            )
          else
            CustomPaint(
              painter: _LegendLinePainter(color: color, dashed: dashed),
              size: const Size(16, 8),
            ),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 9, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 图例线条绘制器
// ══════════════════════════════════════════════════════════════════════════════

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;

  _LegendLinePainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (dashed) {
      const dashWidth = 3.0;
      const dashSpace = 2.0;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset((x + dashWidth).clamp(0, size.width), size.height / 2),
          paint,
        );
        x += dashWidth + dashSpace;
      }
    } else {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter old) =>
      old.color != color || old.dashed != dashed;
}

// ══════════════════════════════════════════════════════════════════════════════
// KnowledgeGraphPainter — 自定义绘制知识图谱
// ══════════════════════════════════════════════════════════════════════════════

class _KnowledgeGraphPainter extends CustomPainter {
  final List<_ConceptNode> nodes;
  final List<_ConceptEdge> edges;
  final _ConceptNode? selectedNode;
  final Set<int> highlightedNodeIds;
  final Set<int> adjacentNodeIds;
  final Set<int> adjacentEdgeIds;
  final _ConceptNode? focusedNode;
  final _ViewMode viewMode;
  final MaskShape maskShape;
  final Path? maskPath;

  _KnowledgeGraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNode,
    this.highlightedNodeIds = const {},
    this.adjacentNodeIds = const {},
    this.adjacentEdgeIds = const {},
    this.focusedNode,
    this.viewMode = _ViewMode.global,
    this.maskShape = MaskShape.none,
    this.maskPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final nodeMap = {for (final n in nodes) n.id: n};

    // ── 章节视图：绘制章节分组背景 ────────────────────────────────────────
    if (viewMode == _ViewMode.chapter) {
      _drawChapterBackgrounds(canvas, nodeMap);
    } else if (viewMode == _ViewMode.mask && maskPath != null) {
      // 蒙版视图：绘制蒙版轮廓
      _drawMaskOutline(canvas, size);
    } else {
      // 全局视图：绘制分散的技术Logo水印
      _drawGlobalWatermarks(canvas, size);
    }

    // ── 绘制边 ─────────────────────────────────────────────────────────────
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;

      final isAdjacentEdge = adjacentEdgeIds.contains(edge.id);
      final isHighlightedEdge = highlightedNodeIds.contains(edge.sourceId) &&
          highlightedNodeIds.contains(edge.targetId);

      final rStyle = edge.style;
      Color edgeColor;
      double edgeWidth;

      if (isAdjacentEdge) {
        edgeColor = rStyle.color;
        edgeWidth = 2.5;
      } else if (isHighlightedEdge) {
        edgeColor = rStyle.color;
        edgeWidth = 2.0;
      } else if (selectedNode != null || highlightedNodeIds.isNotEmpty) {
        // 有选中或高亮时，非相关边减淡
        edgeColor = rStyle.color.withValues(alpha: 0.15);
        edgeWidth = 1.0;
      } else {
        edgeColor = rStyle.color.withValues(alpha: 0.5);
        edgeWidth = 1.5;
      }

      final edgePaint = Paint()
        ..color = edgeColor
        ..strokeWidth = edgeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final srcOff = Offset(src.x, src.y);
      final tgtOff = Offset(tgt.x, tgt.y);

      // 贝塞尔曲线（微弧）
      final mid = Offset((src.x + tgt.x) / 2, (src.y + tgt.y) / 2);
      final dx = tgt.x - src.x;
      final dy = tgt.y - src.y;
      final perpX = -dy * 0.12;
      final perpY = dx * 0.12;
      final ctrl = Offset(mid.dx + perpX, mid.dy + perpY);

      if (rStyle.dashed) {
        _drawDashedQuadBezier(canvas, srcOff, ctrl, tgtOff, edgePaint);
      } else {
        final path = Path()
          ..moveTo(srcOff.dx, srcOff.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, tgtOff.dx, tgtOff.dy);
        canvas.drawPath(path, edgePaint);
      }

      // 箭头
      final dist = (tgtOff - srcOff).distance;
      if (dist > (src.radius + tgt.radius + 10)) {
        final tgtRadius = tgt.radius;
        final t = 1 - (tgtRadius + 4) / dist;
        final arrowEnd = Offset(
          srcOff.dx + (tgtOff.dx - srcOff.dx) * t,
          srcOff.dy + (tgtOff.dy - srcOff.dy) * t,
        );
        _drawArrowHead(canvas, ctrl, arrowEnd, edgePaint);

        // 双向箭头
        if (edge.bidirectional) {
          final srcRadius = src.radius;
          final t2 = (srcRadius + 4) / dist;
          final arrowStart = Offset(
            srcOff.dx + (tgtOff.dx - srcOff.dx) * t2,
            srcOff.dy + (tgtOff.dy - srcOff.dy) * t2,
          );
          _drawArrowHead(canvas, ctrl, arrowStart, edgePaint);
        }
      }

      // 边标签
      if (isAdjacentEdge || (!_hasSelection() && !_hasHighlight())) {
        final labelText = edge.label ?? rStyle.label;
        if (labelText.isNotEmpty) {
          final labelBg = Paint()
            ..color = Colors.white.withValues(alpha: 0.85);
          final tp = TextPainter(
            text: TextSpan(
              text: labelText,
              style: TextStyle(
                fontSize: 9,
                color: edgeColor.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();

          final labelPos =
              Offset(ctrl.dx - tp.width / 2, ctrl.dy - tp.height / 2);
          final labelRect = Rect.fromLTWH(
            labelPos.dx - 3,
            labelPos.dy - 1,
            tp.width + 6,
            tp.height + 2,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
            labelBg,
          );
          tp.paint(canvas, labelPos);
        }
      }
    }

    // ── 绘制节点 ──────────────────────────────────────────────────────────
    for (final node in nodes) {
      final isSelected = selectedNode?.id == node.id;
      final isHighlighted = highlightedNodeIds.contains(node.id);
      final isAdjacent = adjacentNodeIds.contains(node.id);
      final isFocusCenter = focusedNode?.id == node.id;

      final radius = node.radius;
      final center = Offset(node.x, node.y);
      final nodeColor = node.color;

      // 判断是否应该减淡（有选中/高亮时，非相关节点减淡）
      final dimmed = (_hasSelection() || _hasHighlight()) &&
          !isSelected &&
          !isHighlighted &&
          !isAdjacent &&
          !isFocusCenter;

      // 搜索高亮光晕（黄色）
      if (isHighlighted && !isSelected) {
        final glowPaint = Paint()
          ..color = const Color(0xFFFFF176).withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
        canvas.drawCircle(center, radius + 12, glowPaint);
      }

      // 邻居高亮光晕
      if (isAdjacent && !isSelected) {
        final adjGlow = Paint()
          ..color = nodeColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(center, radius + 8, adjGlow);
      }

      // 选中光晕
      if (isSelected) {
        final selGlow = Paint()
          ..color = const Color(0xFF667eea).withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
        canvas.drawCircle(center, radius + 14, selGlow);
      }

      // 焦点中心标记
      if (isFocusCenter) {
        final focusGlow = Paint()
          ..color = const Color(0xFF667eea).withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
        canvas.drawCircle(center, radius + 20, focusGlow);

        // 双圈指示
        canvas.drawCircle(
          center,
          radius + 6,
          Paint()
            ..color = const Color(0xFF667eea)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }

      // 阴影
      if (!dimmed) {
        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(
            Offset(center.dx + 1.5, center.dy + 2.5), radius, shadowPaint);
      }

      // 节点圆
      final fillColor =
          dimmed ? nodeColor.withValues(alpha: 0.2) : nodeColor;
      final nodePaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      // 根据概念类型绘制不同形状
      switch (node.type) {
        case 'framework':
          // 圆角矩形
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center, width: radius * 2, height: radius * 1.7),
            Radius.circular(radius * 0.35),
          );
          canvas.drawRRect(rect, nodePaint);
          break;
        case 'platform':
          // 六边形
          _drawPolygon(canvas, center, radius, 6, nodePaint);
          break;
        case 'pattern':
          // 菱形
          _drawPolygon(canvas, center, radius, 4, nodePaint);
          break;
        default:
          // 默认圆形
          canvas.drawCircle(center, radius, nodePaint);
      }

      // 选中边框环
      if (isSelected) {
        final selRing = Paint()
          ..color = const Color(0xFF667eea)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

        switch (node.type) {
          case 'framework':
            final rect = RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: center,
                  width: radius * 2 + 6,
                  height: radius * 1.7 + 6),
              Radius.circular(radius * 0.35 + 3),
            );
            canvas.drawRRect(rect, selRing);
            break;
          case 'platform':
            _drawPolygon(canvas, center, radius + 3, 6, selRing);
            break;
          case 'pattern':
            _drawPolygon(canvas, center, radius + 3, 4, selRing);
            break;
          default:
            canvas.drawCircle(center, radius + 3, selRing);
        }
      }

      // 节点文本
      final displayName =
          node.name.length > 6 ? '${node.name.substring(0, 6)}...' : node.name;
      final textColor = dimmed
          ? Colors.grey.shade400
          : _isLightColor(nodeColor)
              ? Colors.black87
              : Colors.white;

      final textPainter = TextPainter(
        text: TextSpan(
          text: displayName,
          style: TextStyle(
            color: textColor,
            fontSize: node.importance == 'core'
                ? 11
                : node.importance == 'important'
                    ? 10
                    : 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 2 - 6);

      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2,
            center.dy - textPainter.height / 2),
      );

      // 章节标注（章节视图下不显示，因为有背景标注）
      if (viewMode != _ViewMode.chapter && node.chapter != null && !dimmed) {
        final chTp = TextPainter(
          text: TextSpan(
            text: 'Ch${node.chapter}',
            style: TextStyle(
              fontSize: 8,
              color: dimmed ? Colors.transparent : Colors.grey.shade500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        chTp.paint(
          canvas,
          Offset(center.dx - chTp.width / 2, center.dy + radius + 4),
        );
      }
    }
  }

  // ── 章节背景绘制 ────────────────────────────────────────────────────────

  void _drawChapterBackgrounds(
      Canvas canvas, Map<int, _ConceptNode> nodeMap) {
    // 按章节分组
    final byChapter = <int, List<_ConceptNode>>{};
    for (final node in nodes) {
      final ch = node.chapter ?? 0;
      byChapter.putIfAbsent(ch, () => []).add(node);
    }

    for (final entry in byChapter.entries) {
      if (entry.value.isEmpty) continue;
      final ch = entry.key;
      final color = ChapterHelper.chapterColors[ch] ??
          const Color(0xFF667eea);

      // 找边界
      double minX = double.infinity,
          minY = double.infinity;
      double maxX = double.negativeInfinity,
          maxY = double.negativeInfinity;
      for (final n in entry.value) {
        if (n.x - n.radius < minX) minX = n.x - n.radius;
        if (n.y - n.radius < minY) minY = n.y - n.radius;
        if (n.x + n.radius > maxX) maxX = n.x + n.radius;
        if (n.y + n.radius > maxY) maxY = n.y + n.radius;
      }

      final margin = 40.0;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
            minX - margin, minY - margin - 25, maxX + margin, maxY + margin),
        const Radius.circular(20),
      );

      // 背景
      canvas.drawRRect(
        bgRect,
        Paint()..color = color.withValues(alpha: 0.05),
      );
      // 边框
      canvas.drawRRect(
        bgRect,
        Paint()
          ..color = color.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // ── 技术 Logo 水印 ────────────────────────────────────────────────
      _drawChapterLogoWatermarks(canvas, ch, bgRect.outerRect, color);

      // 章节标题（含简称）
      final shortName = ChapterHelper.chapterShortNames[ch] ?? '';
      final titleText = ch == 0
          ? '未分类'
          : '第 $ch 章 $shortName';
      final tp = TextPainter(
        text: TextSpan(
          text: titleText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(minX - margin + 12, minY - margin - 18));
    }
  }

  /// 在章节背景中绘制技术 Logo 水印（半透明文字 + 图标）
  void _drawChapterLogoWatermarks(
      Canvas canvas, int chapter, Rect rect, Color color) {
    final logos = ChapterHelper.chapterLogos[chapter];
    if (logos == null || logos.isEmpty) return;

    // 裁剪区域防溢出
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)));

    // 计算布局：Logo 分散在背景区域中
    final rng = math.Random(chapter * 1337);
    final areaW = rect.width;
    final areaH = rect.height;

    // 大号文字水印 — 每个logo绘制一次
    for (int i = 0; i < logos.length; i++) {
      final logo = logos[i];
      // 使用确定性随机位置，分散在区域内
      final col = i % 2;
      final row = i ~/ 2;
      final cellW = areaW / 2;
      final cellH = areaH / math.max(((logos.length + 1) ~/ 2), 1);

      final cx = rect.left + cellW * col + cellW * 0.5 +
          (rng.nextDouble() - 0.5) * cellW * 0.4;
      final cy = rect.top + cellH * row + cellH * 0.5 +
          (rng.nextDouble() - 0.5) * cellH * 0.3;

      // 旋转角度（轻微倾斜）
      final angle = (rng.nextDouble() - 0.5) * 0.3; // -0.15 ~ +0.15 rad

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);

      // 绘制文字水印
      final fontSize = logo.length <= 3 ? 42.0 : (logo.length <= 5 ? 34.0 : 26.0);
      final textPainter = TextPainter(
        text: TextSpan(
          text: logo,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: color.withValues(alpha: 0.06),
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }

    // 绘制章节主图标水印（居中大图标）
    final iconData = ChapterHelper.chapterIcons[chapter];
    if (iconData != null) {
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(iconData.codePoint),
          style: TextStyle(
            fontSize: 120,
            fontFamily: iconData.fontFamily,
            package: iconData.fontPackage,
            color: color.withValues(alpha: 0.04),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        Offset(
          rect.center.dx - iconPainter.width / 2,
          rect.center.dy - iconPainter.height / 2,
        ),
      );
    }

    canvas.restore();
  }

  /// 全局视图：在画布上绘制分散的技术Logo水印
  void _drawGlobalWatermarks(Canvas canvas, Size size) {
    // 按章节收集节点中心，计算每个章节的质心
    final chapterCenters = <int, Offset>{};
    final chapterCounts = <int, int>{};
    for (final node in nodes) {
      final ch = node.chapter ?? 0;
      if (ch == 0) continue;
      final prev = chapterCenters[ch] ?? Offset.zero;
      chapterCenters[ch] = Offset(prev.dx + node.x, prev.dy + node.y);
      chapterCounts[ch] = (chapterCounts[ch] ?? 0) + 1;
    }
    // 计算质心
    for (final ch in chapterCenters.keys.toList()) {
      final count = chapterCounts[ch]!;
      chapterCenters[ch] = Offset(
        chapterCenters[ch]!.dx / count,
        chapterCenters[ch]!.dy / count,
      );
    }

    // 在每个章节质心附近绘制1-2个主Logo
    for (final ch in chapterCenters.keys) {
      final center = chapterCenters[ch]!;
      final color = ChapterHelper.chapterColors[ch] ??
          const Color(0xFF667eea);
      final logos = ChapterHelper.chapterLogos[ch];
      if (logos == null || logos.isEmpty) continue;

      // 只绘制前2个最关键的Logo
      final rng = math.Random(ch * 2023);
      for (int i = 0; i < math.min(2, logos.length); i++) {
        final logo = logos[i];
        final offsetX = (rng.nextDouble() - 0.5) * 160;
        final offsetY = (rng.nextDouble() - 0.5) * 120;
        final angle = (rng.nextDouble() - 0.5) * 0.25;

        canvas.save();
        canvas.translate(center.dx + offsetX, center.dy + offsetY);
        canvas.rotate(angle);

        final fontSize = logo.length <= 3 ? 36.0 : 28.0;
        final tp = TextPainter(
          text: TextSpan(
            text: logo,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: color.withValues(alpha: 0.05),
              letterSpacing: 2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

        canvas.restore();
      }
    }
  }

  // ── 辅助方法 ──────────────────────────────────────────────────────────

  bool _hasSelection() => selectedNode != null;
  bool _hasHighlight() => highlightedNodeIds.isNotEmpty;

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

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    const arrowSize = 8.0;
    final angle = (to - from).direction;
    final p1 = Offset(
      to.dx - arrowSize * math.cos(angle - 0.4),
      to.dy - arrowSize * math.sin(angle - 0.4),
    );
    final p2 = Offset(
      to.dx - arrowSize * math.cos(angle + 0.4),
      to.dy - arrowSize * math.sin(angle + 0.4),
    );

    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fillPaint,
    );
  }

  void _drawDashedQuadBezier(
      Canvas canvas, Offset start, Offset control, Offset end, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    const steps = 80;

    var prevPoint = start;
    var accum = 0.0;
    var drawing = true;

    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final x = (1 - t) * (1 - t) * start.dx +
          2 * (1 - t) * t * control.dx +
          t * t * end.dx;
      final y = (1 - t) * (1 - t) * start.dy +
          2 * (1 - t) * t * control.dy +
          t * t * end.dy;
      final curPoint = Offset(x, y);
      final segLen = (curPoint - prevPoint).distance;
      accum += segLen;

      if (drawing) {
        canvas.drawLine(prevPoint, curPoint, paint);
        if (accum >= dashLen) {
          drawing = false;
          accum = 0;
        }
      } else {
        if (accum >= gapLen) {
          drawing = true;
          accum = 0;
        }
      }
      prevPoint = curPoint;
    }
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() > 0.5;
  }

  // ── 蒙版轮廓绘制 ──────────────────────────────────────────────────────

  void _drawMaskOutline(Canvas canvas, Size size) {
    if (maskPath == null) return;

    // 蒙版填充（极淡）
    canvas.drawPath(
      maskPath!,
      Paint()
        ..color = Colors.deepPurple.withValues(alpha: 0.04)
        ..style = PaintingStyle.fill,
    );

    // 蒙版轮廓虚线
    canvas.drawPath(
      maskPath!,
      Paint()
        ..color = Colors.deepPurple.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // 蒙版名称标签
    final labelText = maskShape.label;
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          fontSize: 80,
          fontWeight: FontWeight.w900,
          color: Colors.deepPurple.withValues(alpha: 0.05),
          letterSpacing: 8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter old) =>
      old.selectedNode != selectedNode ||
      old.nodes != nodes ||
      old.edges != edges ||
      old.highlightedNodeIds != highlightedNodeIds ||
      old.adjacentNodeIds != adjacentNodeIds ||
      old.adjacentEdgeIds != adjacentEdgeIds ||
      old.focusedNode != focusedNode ||
      old.viewMode != viewMode ||
      old.maskShape != maskShape;
}

// ══════════════════════════════════════════════════════════════════════════════
// MinimapPainter — 鹰眼小地图绘制
// ══════════════════════════════════════════════════════════════════════════════

class _MinimapPainter extends CustomPainter {
  final List<_ConceptNode> nodes;
  final List<_ConceptEdge> edges;
  final double canvasWidth;
  final double canvasHeight;
  final Rect viewportRect;
  final Path? maskPath;

  _MinimapPainter({
    required this.nodes,
    required this.edges,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.viewportRect,
    this.maskPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / canvasWidth;
    final sy = size.height / canvasHeight;

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF8FAFE),
    );

    // 蒙版轮廓（如果有）
    if (maskPath != null) {
      final scaledMask = maskPath!.transform(
        Matrix4.diagonal3Values(sx, sy, 1).storage,
      );
      canvas.drawPath(
        scaledMask,
        Paint()
          ..color = Colors.deepPurple.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill,
      );
    }

    // 绘制边（细线）
    final nodeMap = {for (final n in nodes) n.id: n};
    for (final edge in edges) {
      final src = nodeMap[edge.sourceId];
      final tgt = nodeMap[edge.targetId];
      if (src == null || tgt == null) continue;
      canvas.drawLine(
        Offset(src.x * sx, src.y * sy),
        Offset(tgt.x * sx, tgt.y * sy),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.25)
          ..strokeWidth = 0.5,
      );
    }

    // 绘制节点（小点）
    for (final node in nodes) {
      final center = Offset(node.x * sx, node.y * sy);
      final r = (node.radius * sx).clamp(1.5, 4.0);
      canvas.drawCircle(
        center,
        r,
        Paint()..color = node.color.withValues(alpha: 0.8),
      );
    }

    // 绘制视口矩形
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = const Color(0xFF667eea).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = const Color(0xFF667eea)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 标签
    final tp = TextPainter(
      text: TextSpan(
        text: '鹰眼',
        style: TextStyle(
          fontSize: 8,
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(3, 2));
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) =>
      old.viewportRect != viewportRect ||
      old.nodes != nodes ||
      old.edges != edges;
}
