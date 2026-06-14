class ArchiveDocument {
  final int? id;
  final String title;
  final String documentType;
  final String period;
  final String? courseId;
  final String courseType;
  final String status;
  final String? content;
  final String? filePath;
  final bool isGenerated;
  final String createdAt;
  final String updatedAt;

  /// V25：AI 审核结果 JSON。schema 见 archive_review_agent.dart 注释。
  /// 空字符串表示未审核过；非空且为合法 JSON 表示已审核（status 通常为 reviewing/approved）。
  final String reviewJson;

  /// V25：上一次审核时间戳（ISO8601）。空字符串表示未审核。
  final String reviewedAt;

  /// V25：审核表所属的源文档 ID。
  /// 例：syllabus_review 文档的 originDocId 指向被审的 syllabus 文档 ID。
  /// null 表示该文档不是审核衍生品（自身就是源文档或导入文档）。
  final int? originDocId;

  ArchiveDocument({
    this.id,
    required this.title,
    required this.documentType,
    required this.period,
    this.courseId,
    required this.courseType,
    this.status = 'draft',
    this.content,
    this.filePath,
    this.isGenerated = false,
    this.reviewJson = '',
    this.reviewedAt = '',
    this.originDocId,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'document_type': documentType,
        'period': period,
        'course_id': courseId,
        'course_type': courseType,
        'status': status,
        'content': content,
        'file_path': filePath,
        'is_generated': isGenerated ? 1 : 0,
        'review_json': reviewJson,
        'reviewed_at': reviewedAt,
        'origin_doc_id': originDocId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ArchiveDocument.fromMap(Map<String, dynamic> map) => ArchiveDocument(
        id: map['id'] as int?,
        title: map['title'] as String? ?? '',
        documentType: map['document_type'] as String? ?? '',
        period: map['period'] as String? ?? '',
        courseId: map['course_id'] as String?,
        courseType: map['course_type'] as String? ?? '',
        status: map['status'] as String? ?? 'draft',
        content: map['content'] as String?,
        filePath: map['file_path'] as String?,
        isGenerated: (map['is_generated'] as int? ?? 0) == 1,
        reviewJson: map['review_json'] as String? ?? '',
        reviewedAt: map['reviewed_at'] as String? ?? '',
        originDocId: map['origin_doc_id'] as int?,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
      );

  ArchiveDocument copyWith({
    int? id,
    String? title,
    String? documentType,
    String? period,
    String? courseId,
    String? courseType,
    String? status,
    String? content,
    String? filePath,
    bool? isGenerated,
    String? reviewJson,
    String? reviewedAt,
    int? originDocId,
    String? createdAt,
    String? updatedAt,
  }) =>
      ArchiveDocument(
        id: id ?? this.id,
        title: title ?? this.title,
        documentType: documentType ?? this.documentType,
        period: period ?? this.period,
        courseId: courseId ?? this.courseId,
        courseType: courseType ?? this.courseType,
        status: status ?? this.status,
        content: content ?? this.content,
        filePath: filePath ?? this.filePath,
        isGenerated: isGenerated ?? this.isGenerated,
        reviewJson: reviewJson ?? this.reviewJson,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        originDocId: originDocId ?? this.originDocId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class DocumentTypeDef {
  final String key;
  final String label;
  final String iconCodePoint;
  final bool needsGeneration;
  final bool canCreate;
  final bool canImport;
  final bool canPrint;
  final String? sourceTable;

  const DocumentTypeDef({
    required this.key,
    required this.label,
    required this.iconCodePoint,
    this.needsGeneration = false,
    this.canCreate = false,
    this.canImport = false,
    this.canPrint = true,
    this.sourceTable,
  });
}
