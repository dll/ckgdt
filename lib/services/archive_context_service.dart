import 'package:flutter/foundation.dart';
import '../data/local/course_dao.dart';
import '../data/local/class_dao.dart';
import '../data/local/lab_task_dao.dart';
import '../data/local/achievement_dao.dart';
import '../data/local/assessment_dao.dart';
import '../data/local/database_helper.dart';
import 'auth_service.dart';

/// 归档生成上下文收集器。
///
/// **职责**：把 ArchiveAgent 生成材料时需要的"系统事实"统一打包成
/// 一份结构化文本，注入 prompt 的 [SYSTEM_FACTS] 段。AI 据此决定哪些
/// 字段照搬模板、哪些字段必须替换为本课程/本班级的真实值。
///
/// **6 类事实**：
///   1. 课程：当前激活课程的 id / name / description / chapterCount / chapters
///   2. 班级：教师当前管理的活跃班级（专业 / 学期 / 学生数）
///   3. 章节：DB graphs 表里被标为 chapter 的根节点（标题 + 节点数）
///   4. 实验：lab_tasks 表的全部任务（标题 / 章节 / 学时）
///   5. 教师：当前登录教师 id / 姓名
///   6. 学生数：班级成员数（不含敏感的姓名/学号列表）
///
/// **输出格式**：纯文本 markdown，可直接拼进 prompt。每段独立编号，
/// AI 可定位"事实第 3.2 项"做引用。
///
/// **降级策略**：任何一类数据采集失败（DB 表不在 / 无激活课程）都不抛错，
/// 在该段位置写"[暂无数据]"。生成不依赖完整事实——AI 会按继承模板的部分
/// 行文。
class ArchiveContextService {
  ArchiveContextService();

  final _courseDao = CourseDao();
  final _classDao = ClassDao();
  final _labTaskDao = LabTaskDao();
  final _achievementDao = AchievementDao();
  final _assessmentDao = AssessmentDao();
  final _auth = AuthService();

  /// 收集全部 6 类事实并打包为 prompt 段。
  ///
  /// [classId]：可选。给了就只看这个班的事实；不给走"教师当前管理的活跃班"
  Future<String> collectForPrompt({int? classId}) async {
    final buf = StringBuffer();
    buf.writeln('## 系统事实清单（生成时以此为准，模板字段如与此冲突应替换）\n');

    buf.writeln(await _section1Course());
    buf.writeln(await _section2Class(classId: classId));
    buf.writeln(await _section3Chapters());
    buf.writeln(await _section4Labs());
    buf.writeln(_section5Teacher());
    buf.writeln(await _section6StudentCount(classId: classId));
    buf.writeln(await _section7Achievement());
    buf.writeln(await _section8Assessment());

    return buf.toString();
  }

  Future<String> _section1Course() async {
    try {
      final c = await _courseDao.getActiveCourse();
      if (c == null) return '### 1. 课程\n[暂无激活课程]\n';
      final b = StringBuffer('### 1. 课程\n');
      b.writeln('- 课程 id：`${c.id}`');
      b.writeln('- 课程名称：${c.name}');
      if (c.description.isNotEmpty) b.writeln('- 课程简介：${c.description}');
      b.writeln('- 章节数：${c.chapterCount}');
      if (c.chapters.isNotEmpty) {
        b.writeln('- 章节列表：');
        for (var i = 0; i < c.chapters.length; i++) {
          b.writeln('  ${i + 1}. ${c.chapters[i]}');
        }
      }
      return b.toString();
    } catch (e, st) {
      _logErr('section1Course', e, st);
      return '### 1. 课程\n[采集失败：$e]\n';
    }
  }

  Future<String> _section2Class({int? classId}) async {
    try {
      Map<String, dynamic>? cls;
      if (classId != null) {
        cls = await _classDao.getClass(classId);
      } else {
        // 取教师管理的第一个活跃班；没有就退到第一个全班
        final tid = _auth.currentUser?.userId;
        if (tid != null) {
          final teacherClasses = await _classDao.getTeacherClasses(tid);
          if (teacherClasses.isNotEmpty) cls = teacherClasses.first;
        }
        if (cls == null) {
          final actives = await _classDao.getActiveClasses();
          if (actives.isNotEmpty) cls = actives.first;
        }
      }
      if (cls == null) return '### 2. 班级\n[暂无班级数据]\n';

      final b = StringBuffer('### 2. 班级\n');
      b.writeln('- 班级名称：${cls['name'] ?? '未命名'}');
      b.writeln('- 专业：${cls['major'] ?? '[未填]'}');
      b.writeln('- 学期：${cls['semester'] ?? '[未填]'}');
      b.writeln('- 年级：${cls['grade'] ?? '[未填]'}');
      b.writeln('- 学生数：${cls['student_count'] ?? '?'}');
      return b.toString();
    } catch (e, st) {
      _logErr('section2Class', e, st);
      return '### 2. 班级\n[采集失败：$e]\n';
    }
  }

  Future<String> _section3Chapters() async {
    try {
      final db = await DatabaseHelper.instance.database;
      // 章节图谱：course 类型 + level=0 的根节点为章节
      final rows = await db.rawQuery('''
        SELECT n.title, n.id, n.graph_id,
          (SELECT COUNT(*) FROM nodes WHERE graph_id = n.graph_id AND parent_id = n.id) AS sub_count
        FROM nodes n
        WHERE n.parent_id IS NULL OR n.parent_id = ''
        ORDER BY n.graph_id, n.level, n.id
        LIMIT 30
      ''');
      if (rows.isEmpty) return '### 3. 章节（来自图谱根节点）\n[暂无图谱数据]\n';

      final b = StringBuffer('### 3. 章节（来自图谱根节点）\n');
      var i = 0;
      for (final r in rows) {
        final title = r['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        i++;
        b.writeln('- 章 ${r['graph_id']}/${r['id']}：$title（子节点 ${r['sub_count']}）');
        if (i >= 12) break; // 防止超长，抓前 12 个根节点足够给 AI 看出结构
      }
      return b.toString();
    } catch (e, st) {
      _logErr('section3Chapters', e, st);
      return '### 3. 章节\n[采集失败：$e]\n';
    }
  }

  Future<String> _section4Labs() async {
    try {
      final tasks = await _labTaskDao.getTasks();
      if (tasks.isEmpty) return '### 4. 实验任务\n[暂无实验任务]\n';
      final b = StringBuffer('### 4. 实验任务\n');
      var i = 0;
      for (final t in tasks) {
        i++;
        if (i > 10) break;
        b.writeln(
            '- 实验 ${t['chapter'] ?? '?'} | ${t['title'] ?? '未命名'} | 学时 ${t['hours'] ?? t['duration'] ?? '?'}');
      }
      if (tasks.length > 10) {
        b.writeln('- …（共 ${tasks.length} 项，仅列出前 10）');
      }
      return b.toString();
    } catch (e, st) {
      _logErr('section4Labs', e, st);
      return '### 4. 实验任务\n[采集失败：$e]\n';
    }
  }

  String _section5Teacher() {
    final u = _auth.currentUser;
    if (u == null) return '### 5. 教师\n[未登录]\n';
    final b = StringBuffer('### 5. 教师\n');
    b.writeln('- 教师 id：${u.userId}');
    b.writeln('- 教师姓名：${u.realName ?? '[未填]'}');
    return b.toString();
  }

  Future<String> _section6StudentCount({int? classId}) async {
    try {
      if (classId == null) return '';
      final members = await _classDao.getClassMembers(classId);
      final students = members.where((m) => (m['role'] ?? 'student') == 'student');
      return '### 6. 学生人数\n- 班级 #$classId 学生数：${students.length}\n';
    } catch (e, st) {
      _logErr('section6StudentCount', e, st);
      return '';
    }
  }

  /// 给生成期"建议章节标题列表"的便捷方法（不进 prompt，给 UI 按钮用）
  Future<List<String>> chapterTitlesFromGraphs() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT DISTINCT title FROM nodes
        WHERE (parent_id IS NULL OR parent_id = '')
          AND graph_id IN (SELECT id FROM graphs WHERE graph_type = 'course' OR graph_type IS NULL)
        ORDER BY level, id LIMIT 8
      ''');
      return rows
          .map((r) => r['title']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      return const [];
    }
  }

  /// 7. 成绩达成：最近批次的班级加权达成度 + 各课程目标达成度。
  Future<String> _section7Achievement() async {
    try {
      final batches = await _achievementDao.getAllBatches();
      if (batches.isEmpty) return '### 7. 成绩达成\n[暂无达成度批次]\n';
      final latest = batches.first;
      final batchId = latest['id'] as int;
      final avg = await _achievementDao.calculateClassAverage(batchId);
      final b = StringBuffer('### 7. 成绩达成\n');
      b.writeln('- 批次：${latest['batch_name'] ?? '未命名'}');
      const w = [0.15, 0.25, 0.30, 0.30];
      double weighted = 0;
      for (int i = 1; i <= 4; i++) {
        final a = avg['课程目标$i'] ?? 0;
        weighted += a * w[i - 1];
        b.writeln('- 课程目标$i 班级平均达成度：${a.toStringAsFixed(4)}（权重 ${w[i - 1]}）');
      }
      b.writeln('- 加权总达成度：${weighted.toStringAsFixed(4)}');
      return b.toString();
    } catch (e, st) {
      _logErr('section7Achievement', e, st);
      return '### 7. 成绩达成\n[采集失败：$e]\n';
    }
  }

  /// 8. 项目考核与答辩：分组数 + 答辩记录概况。
  Future<String> _section8Assessment() async {
    try {
      final groups = await _assessmentDao.getGroups();
      final defenses = await _assessmentDao.getDefenseRecords();
      final b = StringBuffer('### 8. 项目考核与答辩\n');
      b.writeln('- 考核分组数：${groups.length}');
      b.writeln('- 答辩记录数：${defenses.length}');
      if (defenses.isNotEmpty) {
        final done = defenses.where((d) => (d['status'] ?? '') == 'completed').length;
        b.writeln('- 已完成答辩：$done / ${defenses.length}');
      }
      return b.toString();
    } catch (e, st) {
      _logErr('section8Assessment', e, st);
      return '### 8. 项目考核与答辩\n[采集失败：$e]\n';
    }
  }

  void _logErr(String tag, Object e, StackTrace st) {
    if (kDebugMode) debugPrint('[ArchiveContextService.$tag] $e\n$st');
  }
}
