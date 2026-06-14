class PumlFileModel {
  final int? id;
  final String? courseId;
  final String title;
  final String content;
  final String? filePath;
  final String? renderedUrl;
  final String
      diagramType; // 'class','sequence','activity','component','usecase','flowchart'
  final String? chapter;
  final String? createdAt;
  final String? updatedAt;

  const PumlFileModel({
    this.id,
    this.courseId,
    required this.title,
    required this.content,
    this.filePath,
    this.renderedUrl,
    this.diagramType = 'class',
    this.chapter,
    this.createdAt,
    this.updatedAt,
  });

  factory PumlFileModel.fromMap(Map<String, dynamic> map) => PumlFileModel(
        id: map['id'] as int?,
        courseId: map['course_id'] as String?,
        title: map['title'] as String? ?? '',
        content: map['content'] as String? ?? '',
        filePath: map['file_path'] as String?,
        renderedUrl: map['rendered_url'] as String?,
        diagramType: map['diagram_type'] as String? ?? 'class',
        chapter: map['chapter'] as String?,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        if (courseId != null) 'course_id': courseId,
        'title': title,
        'content': content,
        'file_path': filePath,
        'rendered_url': renderedUrl,
        'diagram_type': diagramType,
        'chapter': chapter,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'updated_at': updatedAt ?? DateTime.now().toIso8601String(),
      };

  String get typeLabel {
    const labels = {
      'class': '类图',
      'sequence': '顺序图',
      'activity': '活动图',
      'component': '组件图',
      'usecase': '用例图',
      'flowchart': '流程图',
    };
    return labels[diagramType] ?? diagramType;
  }

  PumlFileModel copyWith({
    String? title,
    String? content,
    String? renderedUrl,
    String? diagramType,
    String? chapter,
  }) =>
      PumlFileModel(
        id: id,
        courseId: courseId,
        title: title ?? this.title,
        content: content ?? this.content,
        filePath: filePath,
        renderedUrl: renderedUrl ?? this.renderedUrl,
        diagramType: diagramType ?? this.diagramType,
        chapter: chapter ?? this.chapter,
        createdAt: createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
}
