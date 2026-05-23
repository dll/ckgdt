part of '../knowledge_graph_page.dart';

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
  double x = 0, y = 0;
  double vx = 0, vy = 0;

  _ConceptNode({
    required this.id,
    required this.name,
    required this.type,
    this.chapter,
    this.importance = 'important',
    this.description,
    this.keywords,
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
  mask('蒙版视图', Icons.auto_awesome),
  achievement('达成度', Icons.emoji_events);

  final String label;
  final IconData icon;
  const _ViewMode(this.label, this.icon);
}

// ══════════════════════════════════════════════════════════════════════════════
// KnowledgeGraphPage
// ══════════════════════════════════════════════════════════════════════════════

