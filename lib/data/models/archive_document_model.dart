class ArchiveDocument {
  final int? id;
  final String title;
  final String documentType;
  final String period;
  final String courseType;
  final String status;
  final String? content;
  final String? filePath;
  final bool isGenerated;
  final String createdAt;
  final String updatedAt;

  ArchiveDocument({
    this.id,
    required this.title,
    required this.documentType,
    required this.period,
    required this.courseType,
    this.status = 'draft',
    this.content,
    this.filePath,
    this.isGenerated = false,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'document_type': documentType,
        'period': period,
        'course_type': courseType,
        'status': status,
        'content': content,
        'file_path': filePath,
        'is_generated': isGenerated ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ArchiveDocument.fromMap(Map<String, dynamic> map) => ArchiveDocument(
        id: map['id'] as int?,
        title: map['title'] as String? ?? '',
        documentType: map['document_type'] as String? ?? '',
        period: map['period'] as String? ?? '',
        courseType: map['course_type'] as String? ?? '',
        status: map['status'] as String? ?? 'draft',
        content: map['content'] as String?,
        filePath: map['file_path'] as String?,
        isGenerated: (map['is_generated'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
      );

  ArchiveDocument copyWith({
    int? id,
    String? title,
    String? documentType,
    String? period,
    String? courseType,
    String? status,
    String? content,
    String? filePath,
    bool? isGenerated,
    String? createdAt,
    String? updatedAt,
  }) =>
      ArchiveDocument(
        id: id ?? this.id,
        title: title ?? this.title,
        documentType: documentType ?? this.documentType,
        period: period ?? this.period,
        courseType: courseType ?? this.courseType,
        status: status ?? this.status,
        content: content ?? this.content,
        filePath: filePath ?? this.filePath,
        isGenerated: isGenerated ?? this.isGenerated,
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
