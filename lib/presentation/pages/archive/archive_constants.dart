import 'package:flutter/material.dart';
import '../../../data/models/archive_document_model.dart';

export '../../../core/constants/archive_periods.dart'
    show archivePeriodKeys, archivePeriodLabels, periodLabel;

const List<IconData> archivePeriodIcons = [
  Icons.wb_sunny_outlined,
  Icons.cloud_outlined,
  Icons.nights_stay_outlined,
  Icons.archive_outlined,
];

const examCourseDocs = {
  'beginning': [
    DocumentTypeDef(
        key: 'teaching_task',
        label: '教学任务单',
        iconCodePoint: '0xe3e4',
        needsGeneration: true,
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'syllabus',
        label: '教学大纲',
        iconCodePoint: '0xe3e4',
        sourceTable: 'syllabus_items',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'syllabus_evaluation',
        label: '大纲合理性评价表',
        iconCodePoint: '0xe869',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'syllabus_review',
        label: '大纲合理性审核表',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'calendar',
        label: '教学日历',
        iconCodePoint: '0xe8b1',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'course_schedule',
        label: '课程课表',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'teaching_schedule',
        label: '教学进度表',
        iconCodePoint: '0xe8b1',
        canCreate: true,
        needsGeneration: true,
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'lesson_plan',
        label: '教学教案',
        iconCodePoint: '0xe882',
        sourceTable: 'lesson_plans',
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'courseware',
        label: '教学课件',
        iconCodePoint: '0xe2c7',
        canImport: true,
        needsGeneration: true,
        canPrint: false),
    DocumentTypeDef(
        key: 'roll_call',
        label: '学生点名册',
        iconCodePoint: '0xe7fb',
        canImport: true,
        canPrint: false),
    DocumentTypeDef(
        key: 'teacher_guide',
        label: '教师教学指导手册',
        iconCodePoint: '0xe869',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'student_guide',
        label: '学生学习指导手册',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'assessment_plan',
        label: '综合考核方案',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'survey',
        label: '问卷',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
  ],
  'midterm': [
    DocumentTypeDef(
        key: 'midterm_progress_check',
        label: '课程进度执行检查',
        iconCodePoint: '0xe872',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'midterm_homework_review',
        label: '作业与批阅次数统计',
        iconCodePoint: '0xe8b1',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'midterm_exam',
        label: '期中考试',
        iconCodePoint: '0xe869',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
  ],
  'final': [
    DocumentTypeDef(
        key: 'final_exam',
        label: '期末试卷',
        iconCodePoint: '0xe869',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'final_analysis',
        label: '期末成绩分析',
        iconCodePoint: '0xe872',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'course_summary',
        label: '课程总结',
        iconCodePoint: '0xe3e4',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'exam_review_form',
        label: '试卷审核表',
        iconCodePoint: '0xe8b1',
        needsGeneration: true),
  ],
  'archive': [
    DocumentTypeDef(
        key: 'all_materials', label: '全部教学材料', iconCodePoint: '0xe2c7'),
    DocumentTypeDef(
        key: 'print_report',
        label: '印刷审批表',
        iconCodePoint: '0xe858',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'archive_form',
        label: '归档确认表',
        iconCodePoint: '0xe884',
        needsGeneration: true),
  ],
};

const assessCourseDocs = {
  'beginning': [
    DocumentTypeDef(
        key: 'teaching_task',
        label: '教学任务单',
        iconCodePoint: '0xe3e4',
        needsGeneration: true,
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'syllabus',
        label: '教学大纲',
        iconCodePoint: '0xe3e4',
        sourceTable: 'syllabus_items',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'syllabus_evaluation',
        label: '大纲合理性评价表',
        iconCodePoint: '0xe869',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'syllabus_review',
        label: '大纲合理性审核表',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'calendar',
        label: '教学日历',
        iconCodePoint: '0xe8b1',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'course_schedule',
        label: '课程课表',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'teaching_schedule',
        label: '教学进度表',
        iconCodePoint: '0xe8b1',
        canCreate: true,
        needsGeneration: true,
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'lesson_plan',
        label: '教学教案',
        iconCodePoint: '0xe882',
        sourceTable: 'lesson_plans',
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'courseware',
        label: '教学课件',
        iconCodePoint: '0xe2c7',
        canImport: true,
        needsGeneration: true,
        canPrint: false),
    DocumentTypeDef(
        key: 'roll_call',
        label: '学生点名册',
        iconCodePoint: '0xe7fb',
        canImport: true,
        canPrint: false),
    DocumentTypeDef(
        key: 'teacher_guide',
        label: '教师教学指导手册',
        iconCodePoint: '0xe869',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'student_guide',
        label: '学生学习指导手册',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'assessment_plan',
        label: '综合考核方案',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'survey',
        label: '问卷',
        iconCodePoint: '0xe8b1',
        canImport: true,
        canPrint: true),
  ],
  'midterm': [
    DocumentTypeDef(
        key: 'midterm_progress_check',
        label: '课程进度执行检查',
        iconCodePoint: '0xe872',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'midterm_homework_review',
        label: '作业与批阅次数统计',
        iconCodePoint: '0xe8b1',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
    DocumentTypeDef(
        key: 'midterm_exam',
        label: '期中考试',
        iconCodePoint: '0xe869',
        canImport: true,
        needsGeneration: true,
        canPrint: true),
  ],
  'final': [
    DocumentTypeDef(
        key: 'final_assessment',
        label: '期末考核材料',
        iconCodePoint: '0xe869',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'final_analysis',
        label: '期末成绩分析',
        iconCodePoint: '0xe872',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'course_summary',
        label: '课程总结',
        iconCodePoint: '0xe3e4',
        needsGeneration: true),
    DocumentTypeDef(
        key: 'assessment_review_form',
        label: '考核审核表',
        iconCodePoint: '0xe8b1',
        needsGeneration: true),
  ],
  'archive': [
    DocumentTypeDef(
        key: 'all_materials', label: '全部教学材料', iconCodePoint: '0xe2c7'),
    DocumentTypeDef(
        key: 'archive_form',
        label: '归档确认表',
        iconCodePoint: '0xe884',
        needsGeneration: true),
  ],
};

bool isExamCourse(String courseType) => courseType == 'exam';

Map<String, List<DocumentTypeDef>> docsForCourseType(String courseType) =>
    isExamCourse(courseType) ? examCourseDocs : assessCourseDocs;

List<DocumentTypeDef> docsForPeriod(String courseType, String period) {
  final all = docsForCourseType(courseType);
  return all[period] ?? [];
}

String documentLabelForCourseType(String courseType, String docType) {
  final defs = docsForCourseType(courseType);
  for (final list in defs.values) {
    for (final d in list) {
      if (d.key == docType) return d.label;
    }
  }
  return docType;
}

/// Detect course type from syllabus content.
/// Returns 'assess' (考查) by default; 'exam' (考试) if syllabus explicitly contains 考试 and no 考查.
String detectCourseTypeFromSyllabus(String? content) {
  if (content == null || content.isEmpty) return 'assess';
  final hasExam = content.contains('考试');
  final hasAssess = content.contains('考查');
  if (hasExam && !hasAssess) return 'exam';
  return 'assess';
}
