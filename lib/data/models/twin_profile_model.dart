/// 数字孪生画像数据模型 — 高保真教育教学数字镜像
///
/// 贯穿 教(教学进度) 学(学习行为) 练(实验实践) 评(成绩达成) 研(教学反思)
/// 五个维度，支撑精准教学与个性化学习。
library;

// ═══════════════════════════════════════════════════════════════════════════════
// 学生数字孪生画像
// ═══════════════════════════════════════════════════════════════════════════════

class StudentTwinProfile {
  // ── 核心指标（原有） ──
  final double quizAvg;
  final double labCompletionRate;
  final double wrongDigestRate;
  final double conceptCoverage;
  final int studyMinutesTotal;
  final List<double> weeklyMinutes;
  final Map<String, double> radar;
  final String level;

  // ── 章节掌握度映射（骨架层）──
  /// 按章节的测验正确率，key=章节号(1-6)，value=正确率(0-100)
  final Map<int, double> chapterMastery;

  // ── 学习行为画像（脉搏层）──
  final LearningPattern learningPattern;

  // ── 每日活跃热力图 ──
  /// 近30天每天的学习分钟数，index 0=30天前，29=今天
  final List<double> dailyActivity;

  // ── 风险评估（诊断层）──
  final String riskLevel; // 'healthy' | 'warning' | 'critical'
  final List<String> riskReasons;

  // ── 里程碑成就 ──
  final List<Milestone> milestones;

  // ── 趋势对比 ──
  final TrendComparison? trend;

  const StudentTwinProfile({
    required this.quizAvg,
    required this.labCompletionRate,
    required this.wrongDigestRate,
    required this.conceptCoverage,
    required this.studyMinutesTotal,
    required this.weeklyMinutes,
    required this.radar,
    required this.level,
    this.chapterMastery = const {},
    this.learningPattern = const LearningPattern(),
    this.dailyActivity = const [],
    this.riskLevel = 'healthy',
    this.riskReasons = const [],
    this.milestones = const [],
    this.trend,
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
        'chapterMastery':
            chapterMastery.map((k, v) => MapEntry(k.toString(), v)),
        'learningPattern': learningPattern.toJson(),
        'dailyActivity': dailyActivity,
        'riskLevel': riskLevel,
        'riskReasons': riskReasons,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'trend': trend?.toJson(),
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
        chapterMastery: ((j['chapterMastery'] as Map?) ?? {})
            .map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble())),
        learningPattern: j['learningPattern'] != null
            ? LearningPattern.fromJson(j['learningPattern'] as Map<String, dynamic>)
            : const LearningPattern(),
        dailyActivity: ((j['dailyActivity'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        riskLevel: j['riskLevel'] as String? ?? 'healthy',
        riskReasons: ((j['riskReasons'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        milestones: ((j['milestones'] as List?) ?? [])
            .map((e) => Milestone.fromJson(e as Map<String, dynamic>))
            .toList(),
        trend: j['trend'] != null
            ? TrendComparison.fromJson(j['trend'] as Map<String, dynamic>)
            : null,
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

// ═══════════════════════════════════════════════════════════════════════════════
// 学习行为模式
// ═══════════════════════════════════════════════════════════════════════════════

class LearningPattern {
  /// 高峰学习时段（0-23），按活跃度排序，取 top 3
  final List<int> peakHours;

  /// 学习稳定度(0-100)：weeklyMinutes 方差归一化后取反
  /// 100=非常稳定(每周均匀)  0=极度不稳定(突击型)
  final double consistency;

  /// 学习风格标签
  final String style; // '稳健型' | '冲刺型' | '晨型' | '夜型' | '均衡型'

  /// 最近7天活跃天数
  final int activeDaysLast7;

  /// 连续学习天数
  final int streakDays;

  /// 上次学习距今天数
  final int daysSinceLastStudy;

  const LearningPattern({
    this.peakHours = const [],
    this.consistency = 0,
    this.style = '均衡型',
    this.activeDaysLast7 = 0,
    this.streakDays = 0,
    this.daysSinceLastStudy = 0,
  });

  Map<String, dynamic> toJson() => {
        'peakHours': peakHours,
        'consistency': consistency,
        'style': style,
        'activeDaysLast7': activeDaysLast7,
        'streakDays': streakDays,
        'daysSinceLastStudy': daysSinceLastStudy,
      };

  factory LearningPattern.fromJson(Map<String, dynamic> j) => LearningPattern(
        peakHours: ((j['peakHours'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        consistency: (j['consistency'] as num?)?.toDouble() ?? 0,
        style: j['style'] as String? ?? '均衡型',
        activeDaysLast7: (j['activeDaysLast7'] as num?)?.toInt() ?? 0,
        streakDays: (j['streakDays'] as num?)?.toInt() ?? 0,
        daysSinceLastStudy: (j['daysSinceLastStudy'] as num?)?.toInt() ?? 0,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 里程碑成就
// ═══════════════════════════════════════════════════════════════════════════════

class Milestone {
  final String id;
  final String title;
  final String icon; // emoji
  final String achievedAt; // ISO8601 or empty if not achieved
  final bool achieved;

  const Milestone({
    required this.id,
    required this.title,
    required this.icon,
    this.achievedAt = '',
    this.achieved = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'icon': icon,
        'achievedAt': achievedAt,
        'achieved': achieved,
      };

  factory Milestone.fromJson(Map<String, dynamic> j) => Milestone(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        icon: j['icon'] as String? ?? '',
        achievedAt: j['achievedAt'] as String? ?? '',
        achieved: j['achieved'] as bool? ?? false,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 趋势对比（本周 vs 上周）
// ═══════════════════════════════════════════════════════════════════════════════

class TrendComparison {
  final double quizAvgDelta; // 正=提升，负=下降
  final double labRateDelta;
  final double conceptCovDelta;
  final double studyTimeDelta; // 本周 vs 上周 学习时长变化(分钟)
  final String summary; // 一句话趋势总结

  const TrendComparison({
    this.quizAvgDelta = 0,
    this.labRateDelta = 0,
    this.conceptCovDelta = 0,
    this.studyTimeDelta = 0,
    this.summary = '',
  });

  Map<String, dynamic> toJson() => {
        'quizAvgDelta': quizAvgDelta,
        'labRateDelta': labRateDelta,
        'conceptCovDelta': conceptCovDelta,
        'studyTimeDelta': studyTimeDelta,
        'summary': summary,
      };

  factory TrendComparison.fromJson(Map<String, dynamic> j) => TrendComparison(
        quizAvgDelta: (j['quizAvgDelta'] as num?)?.toDouble() ?? 0,
        labRateDelta: (j['labRateDelta'] as num?)?.toDouble() ?? 0,
        conceptCovDelta: (j['conceptCovDelta'] as num?)?.toDouble() ?? 0,
        studyTimeDelta: (j['studyTimeDelta'] as num?)?.toDouble() ?? 0,
        summary: j['summary'] as String? ?? '',
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 薄弱知识点
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════════
// 学生风险预警条目（教师视角）
// ═══════════════════════════════════════════════════════════════════════════════

class StudentAlert {
  final String userId;
  final String realName;
  final String alertType; // 'inactive' | 'low_score' | 'no_submission'
  final String message;

  const StudentAlert({
    required this.userId,
    required this.realName,
    required this.alertType,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'realName': realName,
        'alertType': alertType,
        'message': message,
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// 教师数字孪生画像
// ═══════════════════════════════════════════════════════════════════════════════

class TeacherTwinProfile {
  // ── 核心指标（原有）──
  final int classSize;
  final double classAvg;
  final Map<int, double> nodeCoverage;
  final List<WeakSpot> weakSpots;
  final int pendingGrading;

  // ── 班级分布（心脏层）──
  /// 成绩段分布: {excellent(>=85), good(>=70), average(>=60), atRisk(<60)}
  final Map<String, int> classDistribution;

  // ── 教学进度映射（骨架层）──
  /// 教学大纲执行率(0-100)：已完成教学任务/总任务
  final double teachingProgress;

  // ── 实时预警（诊断层）──
  final List<StudentAlert> alerts;

  // ── 教学效能指标 ──
  /// 班级参与度(0-100)：近7天有学习记录的学生占比
  final double classEngagement;

  /// 批阅及时性(0-100)：3天内批完的比率
  final double gradingTimeliness;

  /// 待提交截止预警：距离截止日期不足3天但仍有未提交的实验数
  final int deadlineWarnings;

  // ── 趋势对比 ──
  final TrendComparison? trend;

  const TeacherTwinProfile({
    required this.classSize,
    required this.classAvg,
    required this.nodeCoverage,
    required this.weakSpots,
    required this.pendingGrading,
    this.classDistribution = const {},
    this.teachingProgress = 0,
    this.alerts = const [],
    this.classEngagement = 0,
    this.gradingTimeliness = 0,
    this.deadlineWarnings = 0,
    this.trend,
  });

  Map<String, dynamic> toJson() => {
        'classSize': classSize,
        'classAvg': classAvg,
        'nodeCoverage':
            nodeCoverage.map((k, v) => MapEntry(k.toString(), v)),
        'weakSpots': weakSpots.map((w) => w.toJson()).toList(),
        'pendingGrading': pendingGrading,
        'classDistribution': classDistribution,
        'teachingProgress': teachingProgress,
        'alerts': alerts.map((a) => a.toJson()).toList(),
        'classEngagement': classEngagement,
        'gradingTimeliness': gradingTimeliness,
        'deadlineWarnings': deadlineWarnings,
        'trend': trend?.toJson(),
      };

  factory TeacherTwinProfile.fromJson(Map<String, dynamic> j) =>
      TeacherTwinProfile(
        classSize: (j['classSize'] as num?)?.toInt() ?? 0,
        classAvg: (j['classAvg'] as num?)?.toDouble() ?? 0,
        nodeCoverage: ((j['nodeCoverage'] as Map?) ?? {}).map(
            (k, v) => MapEntry(int.parse(k.toString()), (v as num).toDouble())),
        weakSpots: ((j['weakSpots'] as List?) ?? [])
            .map((e) => WeakSpot(
                  nodeId: e['nodeId'] as int,
                  nodeTitle: e['nodeTitle'] as String,
                  avgScore: (e['avgScore'] as num).toDouble(),
                ))
            .toList(),
        pendingGrading: (j['pendingGrading'] as num?)?.toInt() ?? 0,
        classDistribution: ((j['classDistribution'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        teachingProgress: (j['teachingProgress'] as num?)?.toDouble() ?? 0,
        alerts: ((j['alerts'] as List?) ?? [])
            .map((e) => StudentAlert(
                  userId: e['userId'] as String? ?? '',
                  realName: e['realName'] as String? ?? '',
                  alertType: e['alertType'] as String? ?? '',
                  message: e['message'] as String? ?? '',
                ))
            .toList(),
        classEngagement: (j['classEngagement'] as num?)?.toDouble() ?? 0,
        gradingTimeliness: (j['gradingTimeliness'] as num?)?.toDouble() ?? 0,
        deadlineWarnings: (j['deadlineWarnings'] as num?)?.toInt() ?? 0,
        trend: j['trend'] != null
            ? TrendComparison.fromJson(j['trend'] as Map<String, dynamic>)
            : null,
      );

  static TeacherTwinProfile empty() => const TeacherTwinProfile(
        classSize: 0,
        classAvg: 0,
        nodeCoverage: {},
        weakSpots: [],
        pendingGrading: 0,
      );
}
