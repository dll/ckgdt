/// 班级问答模型
///
/// **场景**：学生提问，可选"私聊老师" 或 "全班可见"。老师回复后所有 visibility=class
/// 的问答全班可见、visibility=private 仅提问者 + 老师可见。
class ClassQaModel {
  final int? id;

  /// 提问者
  final String authorId;
  final String authorName;
  final String authorRole; // student / teacher / admin

  /// 班级 ID（可选；空表示全校）
  final String? classId;

  /// 问题标题（≤ 80 字）
  final String title;

  /// 问题正文（Markdown）
  final String body;

  /// 可见性：'class'（全班可见） / 'private'（仅 author + 老师可见）
  final String visibility;

  /// 'open'（未回复） / 'answered'（有教师回复） / 'closed'（已结题）
  final String status;

  /// 教师采纳的最佳回复 id（用于"已采纳答案"展示）
  final int? acceptedReplyId;

  /// 创建时间
  final String createdAt;

  /// 更新时间（最近一次回复 / 编辑）
  final String updatedAt;

  const ClassQaModel({
    this.id,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    this.classId,
    required this.title,
    required this.body,
    this.visibility = 'class',
    this.status = 'open',
    this.acceptedReplyId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'author_id': authorId,
        'author_name': authorName,
        'author_role': authorRole,
        'class_id': classId,
        'title': title,
        'body': body,
        'visibility': visibility,
        'status': status,
        'accepted_reply_id': acceptedReplyId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ClassQaModel.fromMap(Map<String, dynamic> m) => ClassQaModel(
        id: m['id'] as int?,
        authorId: m['author_id'] as String? ?? '',
        authorName: m['author_name'] as String? ?? '',
        authorRole: m['author_role'] as String? ?? 'student',
        classId: m['class_id'] as String?,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        visibility: m['visibility'] as String? ?? 'class',
        status: m['status'] as String? ?? 'open',
        acceptedReplyId: m['accepted_reply_id'] as int?,
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
      );
}

class ClassQaReplyModel {
  final int? id;
  final int qaId;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String body;

  /// 是否教师回复（决定显示样式 + 是否可被采纳）
  final bool isTeacher;

  /// 点赞数（学生互助场景）
  final int likes;

  final String createdAt;

  const ClassQaReplyModel({
    this.id,
    required this.qaId,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.body,
    this.isTeacher = false,
    this.likes = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'qa_id': qaId,
        'author_id': authorId,
        'author_name': authorName,
        'author_role': authorRole,
        'body': body,
        'is_teacher': isTeacher ? 1 : 0,
        'likes': likes,
        'created_at': createdAt,
      };

  factory ClassQaReplyModel.fromMap(Map<String, dynamic> m) => ClassQaReplyModel(
        id: m['id'] as int?,
        qaId: m['qa_id'] as int? ?? 0,
        authorId: m['author_id'] as String? ?? '',
        authorName: m['author_name'] as String? ?? '',
        authorRole: m['author_role'] as String? ?? 'student',
        body: m['body'] as String? ?? '',
        isTeacher: (m['is_teacher'] as int? ?? 0) == 1,
        likes: m['likes'] as int? ?? 0,
        createdAt: m['created_at'] as String? ?? '',
      );
}
