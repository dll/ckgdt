enum MidtermProgressStatus {
  aligned,
  delayed,
  ahead,
}

class MidtermCheckFormData {
  final MidtermProgressStatus progressStatus;
  final String plannedProgress;
  final String actualProgress;
  final bool hoursMatched;
  final bool labMatched;
  final bool adjustmentRecorded;
  final int homeworkAssignedCount;
  final int homeworkReviewedCount;
  final bool homeworkAligned;
  final bool homeworkFeedbackComplete;
  final bool examConducted;
  final String examMode;
  final bool paperSubmitted;
  final bool answerSubmitted;
  final bool scoreSubmitted;
  final bool analysisSubmitted;
  final String note;

  const MidtermCheckFormData({
    required this.progressStatus,
    required this.plannedProgress,
    required this.actualProgress,
    required this.hoursMatched,
    required this.labMatched,
    required this.adjustmentRecorded,
    required this.homeworkAssignedCount,
    required this.homeworkReviewedCount,
    required this.homeworkAligned,
    required this.homeworkFeedbackComplete,
    required this.examConducted,
    required this.examMode,
    required this.paperSubmitted,
    required this.answerSubmitted,
    required this.scoreSubmitted,
    required this.analysisSubmitted,
    required this.note,
  });

  factory MidtermCheckFormData.defaults() => const MidtermCheckFormData(
        progressStatus: MidtermProgressStatus.aligned,
        plannedProgress: '期中前计划教学内容',
        actualProgress: '期中前实际完成内容',
        hoursMatched: true,
        labMatched: true,
        adjustmentRecorded: true,
        homeworkAssignedCount: 0,
        homeworkReviewedCount: 0,
        homeworkAligned: true,
        homeworkFeedbackComplete: true,
        examConducted: false,
        examMode: '阶段测验',
        paperSubmitted: false,
        answerSubmitted: false,
        scoreSubmitted: false,
        analysisSubmitted: false,
        note: '',
      );
}

class MidtermCheckDraftService {
  MidtermCheckDraftService._();

  static String progressContent(MidtermCheckFormData data, {DateTime? now}) {
    final status = _progressStatusLabel(data.progressStatus);
    final suggestion = switch (data.progressStatus) {
      MidtermProgressStatus.aligned => '当前教学进度与期初教学进度表基本对齐，继续按原计划执行。',
      MidtermProgressStatus.delayed => '当前教学进度滞后（延时），需记录原因并明确补课、调课或内容压缩安排。',
      MidtermProgressStatus.ahead => '当前教学进度超前，需确认未跳过实验、实践或关键知识点。',
    };
    return '''
# 课程进度执行检查

**核查方式**：教师勾选确认
**核查日期**：${_date(now)}

## 一、进度结论

| 项目 | 内容 |
|------|------|
| 期中进度状态 | $status |
| 计划进度 | ${_text(data.plannedProgress)} |
| 实际进度 | ${_text(data.actualProgress)} |
| 理论/实验学时 | ${_yes(data.hoursMatched)} |
| 实验/实践安排 | ${_yes(data.labMatched)} |
| 调课/补课记录 | ${_yes(data.adjustmentRecorded)} |

## 二、教师核查

| 核查项 | 勾选结果 | 说明 |
|--------|----------|------|
| 教学内容与期初进度表一致 | ${_check(data.progressStatus == MidtermProgressStatus.aligned)} | 若为滞后或超前，应写明原因 |
| 理论、实验、实践学时已核对 | ${_check(data.hoursMatched)} | 与教学任务书、课表、实验安排一致 |
| 实验或实践任务按进度实施 | ${_check(data.labMatched)} | 未实施项目需写明补做安排 |
| 调课、停课、补课有记录 | ${_check(data.adjustmentRecorded)} | 作为期中检查依据 |

## 三、检查结论与整改

$suggestion

${_note(data.note)}
''';
  }

  static String homeworkContent(MidtermCheckFormData data, {DateTime? now}) {
    final pending = (data.homeworkAssignedCount - data.homeworkReviewedCount)
        .clamp(0, data.homeworkAssignedCount);
    final conclusion = data.homeworkAligned && pending == 0
        ? '作业布置、批阅与当前教学进度基本对齐。'
        : '作业布置或批阅与当前教学进度存在偏差，需补充批阅、反馈或说明原因。';
    return '''
# 作业与批阅次数统计

**核查方式**：教师勾选确认
**核查日期**：${_date(now)}

## 一、统计结论

| 项目 | 内容 |
|------|------|
| 布置作业次数 | ${data.homeworkAssignedCount} 次 |
| 已批阅次数 | ${data.homeworkReviewedCount} 次 |
| 待批阅次数 | $pending 次 |
| 是否按教学进度布置 | ${_yes(data.homeworkAligned)} |
| 是否完成反馈 | ${_yes(data.homeworkFeedbackComplete)} |

## 二、与进度对齐核查

| 核查项 | 勾选结果 | 说明 |
|--------|----------|------|
| 作业覆盖期中前已授内容 | ${_check(data.homeworkAligned)} | 作业内容应对应已完成章节、实验或阶段项目 |
| 作业次数与教学进度匹配 | ${_check(data.homeworkAssignedCount > 0 && data.homeworkAligned)} | 未布置时需说明替代考核方式 |
| 已按时完成批阅 | ${_check(pending == 0)} | 待批阅 $pending 次 |
| 已向学生反馈共性问题 | ${_check(data.homeworkFeedbackComplete)} | 可为评分、评语、课堂讲评或平台反馈 |

## 三、检查结论与处理

$conclusion

${_note(data.note)}
''';
  }

  static String examContent(MidtermCheckFormData data, {DateTime? now}) {
    final evidenceReady = data.examConducted
        ? data.paperSubmitted &&
            data.answerSubmitted &&
            data.scoreSubmitted &&
            data.analysisSubmitted
        : data.scoreSubmitted || data.analysisSubmitted;
    final conclusion = evidenceReady
        ? '期中阶段考核材料基本齐全，可进入审核、打印和归档。'
        : '期中阶段考核材料不完整，需补齐试题/任务、参考答案、成绩或质量分析。';
    return '''
# 期中考试

**核查方式**：教师勾选确认
**核查日期**：${_date(now)}

## 一、考核方式

| 项目 | 内容 |
|------|------|
| 是否组织期中考试 | ${_yes(data.examConducted)} |
| 考核方式 | ${_text(data.examMode)} |
| 试卷/阶段任务 | ${_yes(data.paperSubmitted)} |
| 参考答案/评分标准 | ${_yes(data.answerSubmitted)} |
| 学生成绩 | ${_yes(data.scoreSubmitted)} |
| 成绩质量分析 | ${_yes(data.analysisSubmitted)} |

## 二、材料提交核查

| 材料项 | 勾选结果 | 归档要求 |
|--------|----------|----------|
| 试卷或阶段任务书 | ${_check(data.paperSubmitted)} | 有正式期中考试时必须提交试卷；无考试时提交阶段任务或替代考核说明 |
| 参考答案或评分标准 | ${_check(data.answerSubmitted)} | 分值、评分点或评分量规清晰 |
| 学生成绩记录 | ${_check(data.scoreSubmitted)} | 能反映学生阶段学习情况 |
| 质量分析与改进措施 | ${_check(data.analysisSubmitted)} | 说明共性问题、薄弱环节和后续教学改进 |

## 三、检查结论

$conclusion

${_note(data.note)}
''';
  }

  static String _progressStatusLabel(MidtermProgressStatus status) =>
      switch (status) {
        MidtermProgressStatus.aligned => '对齐',
        MidtermProgressStatus.delayed => '滞后（延时）',
        MidtermProgressStatus.ahead => '超前',
      };

  static String _date(DateTime? now) {
    final d = now ?? DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _check(bool value) => value ? '已勾选' : '未勾选';

  static String _yes(bool value) => value ? '是' : '否';

  static String _text(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '待填写' : trimmed;
  }

  static String _note(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '补充说明：无。' : '补充说明：$trimmed';
  }
}
