class QuestionModel {
  final int? id;
  final String? source;
  final String question;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final int answerIndex;

  QuestionModel({
    this.id,
    this.source,
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.answerIndex,
  });

  factory QuestionModel.fromMap(Map<String, dynamic> map) {
    return QuestionModel(
      id: map['id'],
      source: map['source'],
      question: map['question'] ?? '',
      optionA: map['option_a'] ?? '',
      optionB: map['option_b'] ?? '',
      optionC: map['option_c'] ?? '',
      optionD: map['option_d'] ?? '',
      answerIndex: map['answer_index'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'source': source,
      'question': question,
      'option_a': optionA,
      'option_b': optionB,
      'option_c': optionC,
      'option_d': optionD,
      'answer_index': answerIndex,
    };
  }

  List<String> get options => [optionA, optionB, optionC, optionD];

  String get correctAnswer {
    switch (answerIndex) {
      case 0:
        return optionA;
      case 1:
        return optionB;
      case 2:
        return optionC;
      case 3:
        return optionD;
      default:
        return '';
    }
  }
}
