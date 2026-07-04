/// 作业数据模型
class HomeworkModel {
  final int id;
  final String courseId;
  final String title;
  final String description;
  final String chapter;
  final String chapterTitle;
  final String courseObjective;
  final int totalScore;
  final DateTime? deadline;
  final String status; // draft / published / closed
  final DateTime createdAt;

  const HomeworkModel({
    required this.id,
    required this.courseId,
    required this.title,
    required this.description,
    this.chapter = '',
    this.chapterTitle = '',
    this.courseObjective = '',
    this.totalScore = 100,
    this.deadline,
    this.status = 'published',
    required this.createdAt,
  });

  factory HomeworkModel.fromMap(Map<String, dynamic> m) => HomeworkModel(
        id: m['id'] as int? ?? 0,
        courseId: m['course_id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        chapter: m['chapter'] as String? ?? '',
        chapterTitle: m['chapter_title'] as String? ?? '',
        courseObjective: m['course_objective'] as String? ?? '',
        totalScore: m['total_score'] as int? ?? 100,
        deadline: m['deadline'] != null ? DateTime.tryParse(m['deadline'] as String) : null,
        status: m['status'] as String? ?? 'published',
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'course_id': courseId,
        'title': title,
        'description': description,
        'chapter': chapter,
        'chapter_title': chapterTitle,
        'course_objective': courseObjective,
        'total_score': totalScore,
        'deadline': deadline?.toIso8601String(),
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}

/// 作业题目模型
class HomeworkItemModel {
  final int id;
  final int homeworkId;
  final int itemIndex;
  final String type; // basic / practice / thinking
  final String typeLabel;
  final String question;
  final String? referenceAnswer;
  final int maxScore;
  final List<ObjectiveMapping> objectiveMapping;

  const HomeworkItemModel({
    required this.id,
    required this.homeworkId,
    required this.itemIndex,
    required this.type,
    required this.typeLabel,
    required this.question,
    this.referenceAnswer,
    required this.maxScore,
    this.objectiveMapping = const [],
  });

  factory HomeworkItemModel.fromMap(Map<String, dynamic> m) => HomeworkItemModel(
        id: m['id'] as int? ?? 0,
        homeworkId: m['homework_id'] as int? ?? 0,
        itemIndex: m['item_index'] as int? ?? 0,
        type: m['type'] as String? ?? 'basic',
        typeLabel: m['type_label'] as String? ?? '基础题',
        question: m['question'] as String? ?? '',
        referenceAnswer: m['reference_answer'] as String?,
        maxScore: m['max_score'] as int? ?? 100,
        objectiveMapping: (m['objective_mapping'] as List?)
                ?.map((e) => ObjectiveMapping.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'homework_id': homeworkId,
        'item_index': itemIndex,
        'type': type,
        'type_label': typeLabel,
        'question': question,
        'reference_answer': referenceAnswer,
        'max_score': maxScore,
        'objective_mapping': objectiveMapping.map((e) => e.toMap()).toList(),
      };
}

/// 作业提交模型
class HomeworkSubmissionModel {
  final int id;
  final int homeworkId;
  final int itemId;
  final String userId;
  final String? answerText;
  final String? answerFilePath;
  final int? score;
  final String? aiComment;
  final String? teacherComment;
  final String status; // submitted / ai_graded / teacher_reviewed
  final DateTime submittedAt;
  final DateTime? gradedAt;

  const HomeworkSubmissionModel({
    required this.id,
    required this.homeworkId,
    required this.itemId,
    required this.userId,
    this.answerText,
    this.answerFilePath,
    this.score,
    this.aiComment,
    this.teacherComment,
    this.status = 'submitted',
    required this.submittedAt,
    this.gradedAt,
  });

  factory HomeworkSubmissionModel.fromMap(Map<String, dynamic> m) =>
      HomeworkSubmissionModel(
        id: m['id'] as int? ?? 0,
        homeworkId: m['homework_id'] as int? ?? 0,
        itemId: m['item_id'] as int? ?? 0,
        userId: m['user_id'] as String? ?? '',
        answerText: m['answer_text'] as String?,
        answerFilePath: m['answer_file_path'] as String?,
        score: m['score'] as int?,
        aiComment: m['ai_comment'] as String?,
        teacherComment: m['teacher_comment'] as String?,
        status: m['status'] as String? ?? 'submitted',
        submittedAt: DateTime.tryParse(m['submitted_at'] as String? ?? '') ?? DateTime.now(),
        gradedAt: m['graded_at'] != null ? DateTime.tryParse(m['graded_at'] as String) : null,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'homework_id': homeworkId,
        'item_id': itemId,
        'user_id': userId,
        'answer_text': answerText,
        'answer_file_path': answerFilePath,
        'score': score,
        'ai_comment': aiComment,
        'teacher_comment': teacherComment,
        'status': status,
        'submitted_at': submittedAt.toIso8601String(),
        'graded_at': gradedAt?.toIso8601String(),
      };
}

/// 目标映射
class ObjectiveMapping {
  final int objectiveId;
  final double contribution;

  const ObjectiveMapping({
    required this.objectiveId,
    required this.contribution,
  });

  factory ObjectiveMapping.fromMap(Map<String, dynamic> m) => ObjectiveMapping(
        objectiveId: m['objective_id'] as int? ?? 0,
        contribution: (m['contribution'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toMap() => {
        'objective_id': objectiveId,
        'contribution': contribution,
      };
}
