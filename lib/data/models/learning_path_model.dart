class LearningPathModel {
  final int? id;
  final String? courseId;
  final String userId;
  final String title;
  final String? description;
  final List<String> nodeIds;
  final double progress;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LearningPathModel({
    this.id,
    this.courseId,
    required this.userId,
    required this.title,
    this.description,
    this.nodeIds = const [],
    this.progress = 0,
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  factory LearningPathModel.fromMap(Map<String, dynamic> map) {
    return LearningPathModel(
      id: map['id'],
      courseId: map['course_id'] as String?,
      userId: map['user_id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'],
      nodeIds:
          map['node_ids'] != null ? List<String>.from(map['node_ids']) : [],
      progress: (map['progress'] ?? 0).toDouble(),
      status: map['status'] ?? 'active',
      createdAt:
          map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt:
          map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (courseId != null) 'course_id': courseId,
      'user_id': userId,
      'title': title,
      'description': description,
      'node_ids': nodeIds.join(','),
      'progress': progress,
      'status': status,
      'created_at':
          createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'updated_at':
          updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  LearningPathModel copyWith({
    int? id,
    String? courseId,
    String? userId,
    String? title,
    String? description,
    List<String>? nodeIds,
    double? progress,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LearningPathModel(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      nodeIds: nodeIds ?? this.nodeIds,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PathNodeModel {
  final int? id;
  final int pathId;
  final String nodeId;
  final String? nodeTitle;
  final int sequence;
  final bool isCompleted;
  final DateTime? completedAt;

  PathNodeModel({
    this.id,
    required this.pathId,
    required this.nodeId,
    this.nodeTitle,
    required this.sequence,
    this.isCompleted = false,
    this.completedAt,
  });

  factory PathNodeModel.fromMap(Map<String, dynamic> map) {
    return PathNodeModel(
      id: map['id'],
      pathId: map['path_id'],
      nodeId: map['node_id'] ?? '',
      nodeTitle: map['node_title'],
      sequence: map['sequence'] ?? 0,
      isCompleted: map['is_completed'] == 1,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'path_id': pathId,
      'node_id': nodeId,
      'node_title': nodeTitle,
      'sequence': sequence,
      'is_completed': isCompleted ? 1 : 0,
      'completed_at': completedAt?.toIso8601String(),
    };
  }
}
