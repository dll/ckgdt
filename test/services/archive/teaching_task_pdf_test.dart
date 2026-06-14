import 'package:flutter_test/flutter_test.dart';
import 'package:knowledge_graph_app/services/archive/teaching_task_pdf.dart';

void main() {
  const validMarkdown = '''
# 教 学 任 务 书

经学校批准聘请刘东良老师担任2026-2027学年第1学期以下教学任务：

| 课程名称 | 课程类别 | 总学时 | 讲授 | 实验 | 实践 | 课外自主学时 | 教学班级 | 计划人数 | 备注 |
|------|------|------|------|------|------|------|------|------|------|
| 移动应用开发 | 专业必修课 | 48 | 32 | 16 | 0 | 0 | 软件231 | 66 |  |

---
> 教师：刘东良 ｜ 学期：2026-2027学年第1学期
> 签发日期：2026年06月13日
> 课程行数：1
''';

  test('parse keeps teacher semester issue date and rows', () {
    final data = TeachingTaskPdf.parse(validMarkdown);
    expect(data.teacher, '刘东良');
    expect(data.semester, '2026-2027学年第1学期');
    expect(data.issueDate, '2026年06月13日');
    expect(data.rows, hasLength(1));
  });

  test('review approves valid teaching task', () {
    final result = TeachingTaskPdf.review(validMarkdown);
    expect(result.isApproved, isTrue);
    expect(result.errors, isEmpty);
    expect(result.passed.map((e) => e.key), contains('teaching_task.rows'));
  });

  test('review catches hour total mismatch', () {
    final invalid = validMarkdown.replaceFirst(
      '| 移动应用开发 | 专业必修课 | 48 | 32 | 16 | 0 | 0 | 软件231 | 66 |  |',
      '| 移动应用开发 | 专业必修课 | 40 | 32 | 16 | 0 | 0 | 软件231 | 66 |  |',
    );
    final result = TeachingTaskPdf.review(invalid);
    expect(result.isApproved, isFalse);
    expect(
        result.errors.map((e) => e.key), contains('teaching_task.row_1_hours'));
  });
}
