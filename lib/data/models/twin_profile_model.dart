/// 数字孪生画像数据模型

class StudentTwinProfile {
  final double quizAvg;
  final double labCompletionRate;
  final double wrongDigestRate;
  final double conceptCoverage;
  final int studyMinutesTotal;
  final List<double> weeklyMinutes;
  final Map<String, double> radar;
  final String level;

  const StudentTwinProfile({
    required this.quizAvg,
    required this.labCompletionRate,
    required this.wrongDigestRate,
    required this.conceptCoverage,
    required this.studyMinutesTotal,
    required this.weeklyMinutes,
    required this.radar,
    required this.level,
  });

  Map<String, dynamic> toJson() => {
        'quizAvg': quizAvg,
        'labCompletionRate': labCompletionRate,
        'wrongDigestRate': wrongDigestRate,
        'conceptCoverage': conceptCoverage,
        'studyMinutesTotal': studyMinutesTotal,
        'weeklyMinutes': weeklyMinutes,
        'radar': radar,
        'level': level,
      };

  factory StudentTwinProfile.fromJson(Map<String, dynamic> j) =>
      StudentTwinProfile(
        quizAvg: (j['quizAvg'] as num?)?.toDouble() ?? 0,
        labCompletionRate: (j['labCompletionRate'] as num?)?.toDouble() ?? 0,
        wrongDigestRate: (j['wrongDigestRate'] as num?)?.toDouble() ?? 0,
        conceptCoverage: (j['conceptCoverage'] as num?)?.toDouble() ?? 0,
        studyMinutesTotal: (j['studyMinutesTotal'] as num?)?.toInt() ?? 0,
        weeklyMinutes: ((j['weeklyMinutes'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        radar: ((j['radar'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
        level: j['level'] as String? ?? '入门',
      );

  static StudentTwinProfile empty() => const StudentTwinProfile(
        quizAvg: 0,
        labCompletionRate: 0,
        wrongDigestRate: 0,
        conceptCoverage: 0,
        studyMinutesTotal: 0,
        weeklyMinutes: [],
        radar: {},
        level: '入门',
      );
}

class WeakSpot {
  final int nodeId;
  final String nodeTitle;
  final double avgScore;

  const WeakSpot({
    required this.nodeId,
    required this.nodeTitle,
    required this.avgScore,
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'nodeTitle': nodeTitle,
        'avgScore': avgScore,
      };
}

class TeacherTwinProfile {
  final int classSize;
  final double classAvg;
  final Map<int, double> nodeCoverage;
  final List<WeakSpot> weakSpots;
  final int pendingGrading;

  const TeacherTwinProfile({
    required this.classSize,
    required this.classAvg,
    required this.nodeCoverage,
    required this.weakSpots,
    required this.pendingGrading,
  });

  Map<String, dynamic> toJson() => {
        'classSize': classSize,
        'classAvg': classAvg,
        'nodeCoverage':
            nodeCoverage.map((k, v) => MapEntry(k.toString(), v)),
        'weakSpots': weakSpots.map((w) => w.toJson()).toList(),
        'pendingGrading': pendingGrading,
      };

  factory TeacherTwinProfile.fromJson(Map<String, dynamic> j) =>
      TeacherTwinProfile(
        classSize: (j['classSize'] as num?)?.toInt() ?? 0,
        classAvg: (j['classAvg'] as num?)?.toDouble() ?? 0,
        nodeCoverage: ((j['nodeCoverage'] as Map?) ?? {})
            .map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble())),
        weakSpots: ((j['weakSpots'] as List?) ?? [])
            .map((e) => WeakSpot(
                  nodeId: e['nodeId'] as int,
                  nodeTitle: e['nodeTitle'] as String,
                  avgScore: (e['avgScore'] as num).toDouble(),
                ))
            .toList(),
        pendingGrading: (j['pendingGrading'] as num?)?.toInt() ?? 0,
      );

  static TeacherTwinProfile empty() => const TeacherTwinProfile(
        classSize: 0,
        classAvg: 0,
        nodeCoverage: {},
        weakSpots: [],
        pendingGrading: 0,
      );
}
