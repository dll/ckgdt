class SyllabusData {
  final String courseName;
  final String? englishName;
  final String? courseCode;
  final String? courseType;
  final String? nature;
  final String? semester;
  final int lectureHours;
  final int labHours;
  final double credits;
  final String? examMethod;
  final String? prerequisites;
  final String? targetMajor;
  final String? department;
  final String description;
  final List<CourseObjective> objectives;
  final List<SyllabusChapter> chapters;
  final List<SyllabusLab> labs;
  final AssessmentStructure assessment;
  final List<String> textbooks;

  SyllabusData({
    required this.courseName,
    this.englishName,
    this.courseCode,
    this.courseType,
    this.nature,
    this.semester,
    this.lectureHours = 0,
    this.labHours = 0,
    this.credits = 0,
    this.examMethod,
    this.prerequisites,
    this.targetMajor,
    this.department,
    this.description = '',
    this.objectives = const [],
    required this.chapters,
    this.labs = const [],
    AssessmentStructure? assessment,
    this.textbooks = const [],
  }) : assessment = assessment ?? const AssessmentStructure();

  String get courseId {
    if (courseCode != null && courseCode!.isNotEmpty) {
      return courseCode!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    }
    return courseName.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
  }
}

class CourseObjective {
  final String id;
  final String description;

  CourseObjective({required this.id, required this.description});
}

class SyllabusChapter {
  final int index;
  final String title;
  final String content;
  final String teachingObjectives;
  final String keyPoints;
  final String difficultPoints;
  final String ideoElement;

  SyllabusChapter({
    required this.index,
    required this.title,
    this.content = '',
    this.teachingObjectives = '',
    this.keyPoints = '',
    this.difficultPoints = '',
    this.ideoElement = '',
  });
}

class SyllabusLab {
  final int index;
  final String title;
  final String content;
  final String objectives;
  final String equipment;
  final String notes;

  SyllabusLab({
    required this.index,
    required this.title,
    this.content = '',
    this.objectives = '',
    this.equipment = '',
    this.notes = '',
  });
}

class AssessmentStructure {
  final double dailyWeight;
  final double labWeight;
  final double examWeight;

  const AssessmentStructure({
    this.dailyWeight = 0.2,
    this.labWeight = 0.3,
    this.examWeight = 0.5,
  });
}
