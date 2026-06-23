import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/midterm_check_draft_service.dart';

void main() {
  group('MidtermCheckDraftService', () {
    test('progress content shows aligned delayed or ahead status', () {
      const data = MidtermCheckFormData(
        progressStatus: MidtermProgressStatus.delayed,
        plannedProgress: '计划完成第1-8周内容',
        actualProgress: '实际完成第1-7周内容',
        hoursMatched: false,
        labMatched: true,
        adjustmentRecorded: false,
        homeworkAssignedCount: 3,
        homeworkReviewedCount: 2,
        homeworkAligned: false,
        homeworkFeedbackComplete: true,
        examConducted: true,
        examMode: '期中考试',
        paperSubmitted: true,
        answerSubmitted: true,
        scoreSubmitted: false,
        analysisSubmitted: false,
        note: '第8周因调课顺延',
      );

      final md = MidtermCheckDraftService.progressContent(
        data,
        now: DateTime(2026, 6, 23),
      );

      expect(md, contains('滞后（延时）'));
      expect(md, contains('计划完成第1-8周内容'));
      expect(md, contains('实际完成第1-7周内容'));
      expect(md, contains('调课、停课、补课有记录'));
      expect(md, contains('第8周因调课顺延'));
    });

    test('homework content records assigned reviewed and alignment', () {
      final data = MidtermCheckFormData.defaults().copyWithForTest(
        homeworkAssignedCount: 4,
        homeworkReviewedCount: 3,
        homeworkAligned: false,
      );

      final md = MidtermCheckDraftService.homeworkContent(data);

      expect(md, contains('布置作业次数 | 4 次'));
      expect(md, contains('已批阅次数 | 3 次'));
      expect(md, contains('待批阅次数 | 1 次'));
      expect(md, contains('作业布置或批阅与当前教学进度存在偏差'));
    });

    test('exam content records paper answer scores and analysis evidence', () {
      final data = MidtermCheckFormData.defaults().copyWithForTest(
        examConducted: true,
        examMode: '期中考试',
        paperSubmitted: true,
        answerSubmitted: true,
        scoreSubmitted: true,
        analysisSubmitted: true,
      );

      final md = MidtermCheckDraftService.examContent(data);

      expect(md, contains('是否组织期中考试 | 是'));
      expect(md, contains('试卷/阶段任务 | 是'));
      expect(md, contains('参考答案/评分标准 | 是'));
      expect(md, contains('学生成绩 | 是'));
      expect(md, contains('期中阶段考核材料基本齐全'));
    });
  });
}

extension _MidtermCheckFormDataTestCopy on MidtermCheckFormData {
  MidtermCheckFormData copyWithForTest({
    MidtermProgressStatus? progressStatus,
    String? plannedProgress,
    String? actualProgress,
    bool? hoursMatched,
    bool? labMatched,
    bool? adjustmentRecorded,
    int? homeworkAssignedCount,
    int? homeworkReviewedCount,
    bool? homeworkAligned,
    bool? homeworkFeedbackComplete,
    bool? examConducted,
    String? examMode,
    bool? paperSubmitted,
    bool? answerSubmitted,
    bool? scoreSubmitted,
    bool? analysisSubmitted,
    String? note,
  }) =>
      MidtermCheckFormData(
        progressStatus: progressStatus ?? this.progressStatus,
        plannedProgress: plannedProgress ?? this.plannedProgress,
        actualProgress: actualProgress ?? this.actualProgress,
        hoursMatched: hoursMatched ?? this.hoursMatched,
        labMatched: labMatched ?? this.labMatched,
        adjustmentRecorded: adjustmentRecorded ?? this.adjustmentRecorded,
        homeworkAssignedCount:
            homeworkAssignedCount ?? this.homeworkAssignedCount,
        homeworkReviewedCount:
            homeworkReviewedCount ?? this.homeworkReviewedCount,
        homeworkAligned: homeworkAligned ?? this.homeworkAligned,
        homeworkFeedbackComplete:
            homeworkFeedbackComplete ?? this.homeworkFeedbackComplete,
        examConducted: examConducted ?? this.examConducted,
        examMode: examMode ?? this.examMode,
        paperSubmitted: paperSubmitted ?? this.paperSubmitted,
        answerSubmitted: answerSubmitted ?? this.answerSubmitted,
        scoreSubmitted: scoreSubmitted ?? this.scoreSubmitted,
        analysisSubmitted: analysisSubmitted ?? this.analysisSubmitted,
        note: note ?? this.note,
      );
}
