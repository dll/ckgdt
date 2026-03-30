class MaterialModel {
  final int? id;
  final String title;
  final String type; // 'pdf', 'slide', 'script', 'uml', 'video_script'
  final String? filePath;
  final String? content;
  final String? chapter;
  final String? createdAt;
  final int size;

  const MaterialModel({
    this.id,
    required this.title,
    required this.type,
    this.filePath,
    this.content,
    this.chapter,
    this.createdAt,
    this.size = 0,
  });

  factory MaterialModel.fromMap(Map<String, dynamic> map) => MaterialModel(
        id: map['id'] as int?,
        title: map['title'] as String? ?? '',
        type: map['type'] as String? ?? 'script',
        filePath: map['file_path'] as String?,
        content: map['content'] as String?,
        chapter: map['chapter'] as String?,
        createdAt: map['created_at'] as String?,
        size: map['size'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'type': type,
        'file_path': filePath,
        'content': content,
        'chapter': chapter,
        'created_at': createdAt ?? DateTime.now().toIso8601String(),
        'size': size,
      };

  String get typeLabel {
    switch (type) {
      case 'pdf':
        return 'PDF课件';
      case 'slide':
        return '幻灯片';
      case 'script':
        return '视频脚本';
      case 'uml':
        return 'UML图';
      case 'video_script':
        return '教学脚本';
      default:
        return '素材';
    }
  }
}
