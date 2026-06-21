import 'dart:math' as math;
import 'dart:ui';
import '../data/models/node_model.dart';
import '../data/models/edge_model.dart';

enum GraphLayout {
  tree('tree', '树形布局'),
  spring('spring', '弹簧布局'),
  circular('circular', '圆形布局'),
  layered('layered', '层次布局'),
  shell('shell', '壳层布局'),
  random('random', '随机布局'),
  grid('grid', '网格布局'),
  force('force', '力导向布局'),
  star('star', '星形布局'),
  kamadaKawai('kamada_kawai', 'Kamada-Kawai布局'),
  concentric('concentric', '同心圆布局');

  final String value;
  final String label;
  const GraphLayout(this.value, this.label);

  static GraphLayout fromString(String value) {
    return GraphLayout.values.firstWhere(
      (e) => e.value == value,
      orElse: () => GraphLayout.tree,
    );
  }
}

class PositionedNode {
  final NodeModel node;
  double x;
  double y;

  PositionedNode(this.node, this.x, this.y);
}

class GraphLayoutService {
  static const double defaultNodeSpacing = 120.0;
  static const double defaultRadius = 200.0;

  List<PositionedNode> calculateLayout({
    required List<NodeModel> nodes,
    required List<EdgeModel> edges,
    required GraphLayout layoutType,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    if (nodes.isEmpty) return [];

    switch (layoutType) {
      case GraphLayout.tree:
        return _treeLayout(nodes, edges, canvasWidth);
      case GraphLayout.spring:
        return _springLayout(nodes, edges);
      case GraphLayout.circular:
        return _circularLayout(nodes, canvasWidth);
      case GraphLayout.layered:
        return _layeredLayout(nodes, edges, canvasWidth);
      case GraphLayout.shell:
        return _shellLayout(nodes, edges);
      case GraphLayout.random:
        return _randomLayout(nodes, canvasWidth, canvasHeight);
      case GraphLayout.grid:
        return _gridLayout(nodes, canvasWidth);
      case GraphLayout.force:
        return _forceLayout(nodes, edges);
      case GraphLayout.star:
        return _starLayout(nodes);
      case GraphLayout.kamadaKawai:
        return _kamadaKawaiLayout(nodes, edges);
      case GraphLayout.concentric:
        return _concentricLayout(nodes, edges);
    }
  }

  List<PositionedNode> _treeLayout(
      List<NodeModel> nodes, List<EdgeModel> edges, double canvasWidth) {
    final levelGroups = <int, List<NodeModel>>{};
    for (final node in nodes) {
      levelGroups.putIfAbsent(node.level, () => []).add(node);
    }
    final levels = levelGroups.keys.toList()..sort();

    final positioned = <PositionedNode>[];
    const verticalSpacing = 120.0;
    const startY = 100.0;

    for (int i = 0; i < levels.length; i++) {
      final level = levels[i];
      final levelNodes = levelGroups[level]!;
      final horizontalSpacing = canvasWidth / (levelNodes.length + 1);

      for (int j = 0; j < levelNodes.length; j++) {
        final x = horizontalSpacing * (j + 1);
        final y = startY + i * verticalSpacing;
        positioned.add(PositionedNode(levelNodes[j], x, y));
      }
    }

    return positioned;
  }

  List<PositionedNode> _springLayout(
      List<NodeModel> nodes, List<EdgeModel> edges) {
    if (nodes.isEmpty) return [];

    final positioned = nodes.map((n) {
      final hasPosition = n.x != 0 || n.y != 0;
      return PositionedNode(
        n,
        hasPosition ? n.x : math.Random().nextDouble() * 800,
        hasPosition ? n.y : math.Random().nextDouble() * 600,
      );
    }).toList();

    const iterations = 50;
    const k = 100.0;
    const damping = 0.8;

    for (int iter = 0; iter < iterations; iter++) {
      final forces = List.generate(positioned.length, (_) => const Offset(0, 0));

      for (int i = 0; i < positioned.length; i++) {
        for (int j = i + 1; j < positioned.length; j++) {
          final dx = positioned[j].x - positioned[i].x;
          final dy = positioned[j].y - positioned[i].y;
          final dist = math.sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);
          final force = k / (dist * dist);
          forces[i] = Offset(forces[i].dx - dx / dist * force,
              forces[i].dy - dy / dist * force);
          forces[j] = Offset(forces[j].dx + dx / dist * force,
              forces[j].dy + dy / dist * force);
        }
      }

      for (int i = 0; i < positioned.length; i++) {
        positioned[i].x += forces[i].dx * damping;
        positioned[i].y += forces[i].dy * damping;
        positioned[i].x = positioned[i].x.clamp(50, 750);
        positioned[i].y = positioned[i].y.clamp(50, 550);
      }
    }

    return positioned;
  }

  List<PositionedNode> _circularLayout(
      List<NodeModel> nodes, double canvasWidth) {
    if (nodes.isEmpty) return [];

    final centerX = canvasWidth / 2;
    const centerY = 300.0;
    final radius = math.min(canvasWidth, 600) / 2 - 50;
    final angleStep = 2 * math.pi / nodes.length;

    return List.generate(nodes.length, (i) {
      final angle = i * angleStep - math.pi / 2;
      return PositionedNode(
        nodes[i],
        centerX + radius * math.cos(angle),
        centerY + radius * math.sin(angle),
      );
    });
  }

  List<PositionedNode> _layeredLayout(
      List<NodeModel> nodes, List<EdgeModel> edges, double canvasWidth) {
    return _treeLayout(nodes, edges, canvasWidth);
  }

  List<PositionedNode> _shellLayout(
      List<NodeModel> nodes, List<EdgeModel> edges) {
    if (nodes.isEmpty) return [];

    const centerX = 400.0;
    const centerY = 300.0;

    final inDegree = <String, int>{};
    final outDegree = <String, int>{};
    for (final edge in edges) {
      inDegree[edge.targetId] = (inDegree[edge.targetId] ?? 0) + 1;
      outDegree[edge.sourceId] = (outDegree[edge.sourceId] ?? 0) + 1;
    }

    final shells = <int, List<NodeModel>>{};
    for (final node in nodes) {
      final d = (inDegree[node.id] ?? 0) - (outDegree[node.id] ?? 0);
      final shell = d > 0 ? 1 : (d < 0 ? 0 : 0);
      shells.putIfAbsent(shell, () => []).add(node);
    }

    final positioned = <PositionedNode>[];
    final shellKeys = shells.keys.toList()..sort();

    for (int si = 0; si < shellKeys.length; si++) {
      final shellNodes = shells[shellKeys[si]]!;
      final radius = 100.0 + si * 120.0;
      final angleStep = 2 * math.pi / shellNodes.length;

      for (int i = 0; i < shellNodes.length; i++) {
        final angle = i * angleStep - math.pi / 2;
        positioned.add(PositionedNode(
          shellNodes[i],
          centerX + radius * math.cos(angle),
          centerY + radius * math.sin(angle),
        ));
      }
    }

    return positioned;
  }

  List<PositionedNode> _randomLayout(
      List<NodeModel> nodes, double canvasWidth, double canvasHeight) {
    final random = math.Random(42);
    return nodes
        .map((n) => PositionedNode(
              n,
              50 + random.nextDouble() * (canvasWidth - 100),
              50 + random.nextDouble() * (canvasHeight - 100),
            ))
        .toList();
  }

  List<PositionedNode> _gridLayout(List<NodeModel> nodes, double canvasWidth) {
    if (nodes.isEmpty) return [];

    final cols = (math.sqrt(nodes.length)).ceil();
    const spacing = 100.0;
    const startX = 50.0;
    const startY = 50.0;

    return List.generate(nodes.length, (i) {
      final col = i % cols;
      final row = i ~/ cols;
      return PositionedNode(
        nodes[i],
        startX + col * spacing,
        startY + row * spacing,
      );
    });
  }

  List<PositionedNode> _forceLayout(
      List<NodeModel> nodes, List<EdgeModel> edges) {
    return _springLayout(nodes, edges);
  }

  List<PositionedNode> _starLayout(List<NodeModel> nodes) {
    if (nodes.isEmpty) return [];

    const centerX = 400.0;
    const centerY = 300.0;
    final positioned = <PositionedNode>[];

    final centerNode = nodes.first;
    positioned.add(PositionedNode(centerNode, centerX, centerY));

    final remainingNodes = nodes.sublist(1);
    final angleStep = 2 * math.pi / remainingNodes.length;
    const radius = 200.0;

    for (int i = 0; i < remainingNodes.length; i++) {
      final angle = i * angleStep - math.pi / 2;
      positioned.add(PositionedNode(
        remainingNodes[i],
        centerX + radius * math.cos(angle),
        centerY + radius * math.sin(angle),
      ));
    }

    return positioned;
  }

  List<PositionedNode> _kamadaKawaiLayout(
      List<NodeModel> nodes, List<EdgeModel> edges) {
    if (nodes.isEmpty) return [];

    final positioned = nodes.map((n) {
      final hasPosition = n.x != 0 || n.y != 0;
      return PositionedNode(
        n,
        hasPosition ? n.x : math.Random().nextDouble() * 800,
        hasPosition ? n.y : math.Random().nextDouble() * 600,
      );
    }).toList();

    const restLength = 100.0;
    const iterations = 30;
    const epsilon = 0.01;

    for (int iter = 0; iter < iterations; iter++) {
      for (int i = 0; i < positioned.length; i++) {
        Offset force = Offset.zero;

        for (int j = 0; j < positioned.length; j++) {
          if (i == j) continue;

          final dx = positioned[j].x - positioned[i].x;
          final dy = positioned[j].y - positioned[i].y;
          final dist = math.sqrt(dx * dx + dy * dy).clamp(1.0, double.infinity);

          const l = restLength;
          force = Offset(
            force.dx + (dx / dist) * (dist - l),
            force.dy + (dy / dist) * (dist - l),
          );
        }

        const maxMove = 50.0;
        final move = math.sqrt(force.dx * force.dx + force.dy * force.dy);
        if (move > epsilon) {
          positioned[i].x += (force.dx / move) * math.min(move, maxMove);
          positioned[i].y += (force.dy / move) * math.min(move, maxMove);
        }
      }
    }

    return positioned;
  }

  List<PositionedNode> _concentricLayout(
      List<NodeModel> nodes, List<EdgeModel> edges) {
    if (nodes.isEmpty) return [];

    const centerX = 400.0;
    const centerY = 300.0;

    final degree = <String, int>{};
    for (final edge in edges) {
      degree[edge.sourceId] = (degree[edge.sourceId] ?? 0) + 1;
      degree[edge.targetId] = (degree[edge.targetId] ?? 0) + 1;
    }

    final sortedNodes = List<NodeModel>.from(nodes)
      ..sort((a, b) => (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0));

    final positioned = <PositionedNode>[];
    positioned.add(PositionedNode(sortedNodes[0], centerX, centerY));

    if (sortedNodes.length > 1) {
      const shell1Radius = 150.0;
      final shell1Count = math.min(sortedNodes.length - 1, 6);
      final angleStep = 2 * math.pi / shell1Count;

      for (int i = 0; i < shell1Count; i++) {
        final angle = i * angleStep - math.pi / 2;
        positioned.add(PositionedNode(
          sortedNodes[i + 1],
          centerX + shell1Radius * math.cos(angle),
          centerY + shell1Radius * math.sin(angle),
        ));
      }
    }

    if (sortedNodes.length > 7) {
      const shell2Radius = 300.0;
      final shell2Count = sortedNodes.length - 7;
      final angleStep = 2 * math.pi / shell2Count;

      for (int i = 0; i < shell2Count; i++) {
        final angle = i * angleStep;
        positioned.add(PositionedNode(
          sortedNodes[i + 7],
          centerX + shell2Radius * math.cos(angle),
          centerY + shell2Radius * math.sin(angle),
        ));
      }
    }

    return positioned;
  }
}
