class QuizResultModel {
  final int? id;
  final String? courseId;
  final String userId;
  final String? quizTimestamp;
  final int score;
  final int numCorrect;
  final int numTotal;
  final String? chapter;
  final String? quizType;
  final String? completedAt;

  QuizResultModel({
    this.id,
    this.courseId,
    required this.userId,
    this.quizTimestamp,
    required this.score,
    required this.numCorrect,
    required this.numTotal,
    this.chapter,
    this.quizType,
    this.completedAt,
  });

  factory QuizResultModel.fromMap(Map<String, dynamic> map) {
    return QuizResultModel(
      id: map['id'],
      courseId: map['course_id'],
      userId: map['user_id'] ?? '',
      quizTimestamp: map['quiz_timestamp'],
      score: map['score'] ?? 0,
      numCorrect: map['num_correct'] ?? 0,
      numTotal: map['num_total'] ?? 0,
      chapter: map['chapter'],
      quizType: map['quiz_type'],
      completedAt: map['completed_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (courseId != null) 'course_id': courseId,
      'user_id': userId,
      'quiz_timestamp': quizTimestamp,
      'score': score,
      'num_correct': numCorrect,
      'num_total': numTotal,
      'chapter': chapter,
      'quiz_type': quizType,
      'completed_at': completedAt,
    };
  }

  double get accuracy => numTotal > 0 ? (numCorrect / numTotal) * 100 : 0;
}
