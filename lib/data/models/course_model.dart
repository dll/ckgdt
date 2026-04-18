/// 课程数据模型
class CourseModel {
  final String id;
  final String name;
  final String description;
  final int chapterCount;
  final List<String> chapters;
  final bool isActive;
  final String createdAt;

  CourseModel({
    required this.id,
    required this.name,
    this.description = '',
    this.chapterCount = 6,
    this.chapters = const [],
    this.isActive = false,
    required this.createdAt,
  });

  factory CourseModel.fromMap(Map<String, dynamic> map) {
    List<String> parseChapters(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return raw.cast<String>();
      if (raw is String && raw.isNotEmpty) {
        // JSON 数组字符串解析
        final trimmed = raw.trim();
        if (trimmed.startsWith('[')) {
          try {
            // 简易解析：去掉 [] 后按 "," 分割
            final inner = trimmed.substring(1, trimmed.length - 1);
            return inner
                .split(RegExp(r'"\s*,\s*"'))
                .map((s) => s.replaceAll('"', '').trim())
                .where((s) => s.isNotEmpty)
                .toList();
          } catch (_) {
            return [raw];
          }
        }
        return raw.split(',').map((s) => s.trim()).toList();
      }
      return [];
    }

    return CourseModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      chapterCount: map['chapter_count'] as int? ?? 6,
      chapters: parseChapters(map['chapters']),
      isActive: (map['is_active'] as int? ?? 0) == 1,
      createdAt: map['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'chapter_count': chapterCount,
      'chapters': '["${chapters.join('","')}"]',
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
  }

  CourseModel copyWith({
    String? id,
    String? name,
    String? description,
    int? chapterCount,
    List<String>? chapters,
    bool? isActive,
    String? createdAt,
  }) {
    return CourseModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      chapterCount: chapterCount ?? this.chapterCount,
      chapters: chapters ?? this.chapters,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
