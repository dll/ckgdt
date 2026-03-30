class EdgeModel {
  final String id;
  final String graphId;
  final String sourceId;
  final String targetId;
  final String? edgeType;
  final String? label;
  final double weight;
  final String? color;
  final double width;
  final String? style;
  final bool visible;

  EdgeModel({
    required this.id,
    required this.graphId,
    required this.sourceId,
    required this.targetId,
    this.edgeType,
    this.label,
    this.weight = 1.0,
    this.color,
    this.width = 1.0,
    this.style,
    this.visible = true,
  });

  factory EdgeModel.fromMap(Map<String, dynamic> map) {
    return EdgeModel(
      id: map['id'] ?? '',
      graphId: map['graph_id'] ?? '',
      sourceId: map['source_id'] ?? '',
      targetId: map['target_id'] ?? '',
      edgeType: map['edge_type'],
      label: map['label'],
      weight: (map['weight'] ?? 1.0).toDouble(),
      color: map['color'],
      width: (map['width'] ?? 1.0).toDouble(),
      style: map['style'],
      visible: map['visible'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'graph_id': graphId,
      'source_id': sourceId,
      'target_id': targetId,
      'edge_type': edgeType,
      'label': label,
      'weight': weight,
      'color': color,
      'width': width,
      'style': style,
      'visible': visible ? 1 : 0,
    };
  }
}
