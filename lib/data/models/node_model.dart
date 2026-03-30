class NodeModel {
  final String id;
  final String graphId;
  final String title;
  final String? content;
  final String? nodeType;
  final int level;
  final double x;
  final double y;
  final String? color;
  final String? parentId;
  final bool visible;
  final Map<String, dynamic>? metadata;

  NodeModel({
    required this.id,
    required this.graphId,
    required this.title,
    this.content,
    this.nodeType,
    this.level = 0,
    this.x = 0,
    this.y = 0,
    this.color,
    this.parentId,
    this.visible = true,
    this.metadata,
  });

  factory NodeModel.fromMap(Map<String, dynamic> map) {
    return NodeModel(
      id: map['id'] ?? '',
      graphId: map['graph_id'] ?? '',
      title: map['title'] ?? '',
      content: map['content'],
      nodeType: map['node_type'],
      level: map['level'] ?? 0,
      x: (map['x'] ?? 0).toDouble(),
      y: (map['y'] ?? 0).toDouble(),
      color: map['color'],
      parentId: map['parent_id'],
      visible: map['visible'] == 1,
      metadata: map['metadata_json'] != null 
          ? Map<String, dynamic>.from(map['metadata_json']) 
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'graph_id': graphId,
      'title': title,
      'content': content,
      'node_type': nodeType,
      'level': level,
      'x': x,
      'y': y,
      'color': color,
      'parent_id': parentId,
      'visible': visible ? 1 : 0,
      'metadata_json': metadata?.toString(),
    };
  }
}
