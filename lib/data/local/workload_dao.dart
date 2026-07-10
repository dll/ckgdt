import 'database_helper.dart';
import 'course_dao.dart';
import '../../core/error_handler.dart';

class TeachingWorkload {
  final int? id;
  final String teacherId;
  final String teacherName;
  final String? department;
  final String? courseSerial;
  final String? courseCode;
  final String courseName;
  final String? courseCategory;
  final String? classNames;
  final String? teachingForm;
  final String? courseNature;
  final double? credits;
  final int? studentCount;
  final int? groupNumber;
  final int? groupSize;
  final int groupCount;
  final double courseCoefficient;
  final int classHours;
  final double? practiceCredits;
  final double scaleCoefficient;
  final double calculatedWorkload;
  final double declaredWorkload;
  final double verifiedWorkload;
  final String workloadType;
  final String? otherCategory;
  final String? extraHoursProject;
  final String status;
  final String? aiReviewJson;
  final bool teacherConfirmed;
  final String? feedback;
  final String? semester;
  final String? courseId;
  final String? remark;
  final String? createdAt;
  final String? updatedAt;

  TeachingWorkload({
    this.id,
    required this.teacherId,
    required this.teacherName,
    this.department,
    this.courseSerial,
    this.courseCode,
    required this.courseName,
    this.courseCategory,
    this.classNames,
    this.teachingForm,
    this.courseNature,
    this.credits,
    this.studentCount,
    this.groupNumber,
    this.groupSize,
    this.groupCount = 1,
    this.courseCoefficient = 1.0,
    this.classHours = 0,
    this.practiceCredits,
    this.scaleCoefficient = 1.0,
    this.calculatedWorkload = 0,
    this.declaredWorkload = 0,
    this.verifiedWorkload = 0,
    this.workloadType = '理论工作量',
    this.otherCategory,
    this.extraHoursProject,
    this.status = 'draft',
    this.aiReviewJson,
    this.teacherConfirmed = false,
    this.feedback,
    this.semester,
    this.courseId,
    this.remark,
    this.createdAt,
    this.updatedAt,
  });

  double get computedWorkload =>
      classHours * courseCoefficient * scaleCoefficient;

  /// 规模系数计算（学生人数阈值）
  static double computeScaleCoefficient(int students) {
    if (students <= 40) return 1.0;
    if (students <= 60) return 1.15;
    if (students <= 80) return 1.21;
    if (students <= 100) return 1.3;
    return 1.4;
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'teacher_id': teacherId,
        'teacher_name': teacherName,
        'department': department,
        'course_serial': courseSerial,
        'course_code': courseCode,
        'course_name': courseName,
        'course_category': courseCategory,
        'class_names': classNames,
        'teaching_form': teachingForm,
        'course_nature': courseNature,
        'credits': credits,
        'student_count': studentCount,
        'group_number': groupNumber,
        'group_size': groupSize,
        'group_count': groupCount,
        'course_coefficient': courseCoefficient,
        'class_hours': classHours,
        'practice_credits': practiceCredits,
        'scale_coefficient': scaleCoefficient,
        'calculated_workload': computedWorkload,
        'declared_workload': declaredWorkload,
        'verified_workload': verifiedWorkload,
        'workload_type': workloadType,
        'other_category': otherCategory,
        'extra_hours_project': extraHoursProject,
        'status': status,
        'ai_review_json': aiReviewJson,
        'teacher_confirmed': teacherConfirmed ? 1 : 0,
        'feedback': feedback,
        'semester': semester,
        'course_id': courseId,
        'remark': remark,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory TeachingWorkload.fromMap(Map<String, dynamic> m) =>
      TeachingWorkload(
        id: m['id'] as int?,
        teacherId: (m['teacher_id'] ?? '').toString(),
        teacherName: (m['teacher_name'] ?? '').toString(),
        department: m['department']?.toString(),
        courseSerial: m['course_serial']?.toString(),
        courseCode: m['course_code']?.toString(),
        courseName: (m['course_name'] ?? '').toString(),
        courseCategory: m['course_category']?.toString(),
        classNames: m['class_names']?.toString(),
        teachingForm: m['teaching_form']?.toString(),
        courseNature: m['course_nature']?.toString(),
        credits: (m['credits'] as num?)?.toDouble(),
        studentCount: (m['student_count'] as num?)?.toInt(),
        groupNumber: (m['group_number'] as num?)?.toInt(),
        groupSize: (m['group_size'] as num?)?.toInt(),
        groupCount: (m['group_count'] as num?)?.toInt() ?? 1,
        courseCoefficient:
            (m['course_coefficient'] as num?)?.toDouble() ?? 1.0,
        classHours: (m['class_hours'] as num?)?.toInt() ?? 0,
        practiceCredits: (m['practice_credits'] as num?)?.toDouble(),
        scaleCoefficient:
            (m['scale_coefficient'] as num?)?.toDouble() ?? 1.0,
        calculatedWorkload:
            (m['calculated_workload'] as num?)?.toDouble() ?? 0,
        declaredWorkload:
            (m['declared_workload'] as num?)?.toDouble() ?? 0,
        verifiedWorkload:
            (m['verified_workload'] as num?)?.toDouble() ?? 0,
        workloadType: (m['workload_type'] ?? '理论工作量').toString(),
        otherCategory: m['other_category']?.toString(),
        extraHoursProject: m['extra_hours_project']?.toString(),
        status: (m['status'] ?? 'draft').toString(),
        aiReviewJson: m['ai_review_json']?.toString(),
        teacherConfirmed: (m['teacher_confirmed'] as int?) == 1,
        feedback: m['feedback']?.toString(),
        semester: m['semester']?.toString(),
        courseId: m['course_id']?.toString(),
        remark: m['remark']?.toString(),
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );

  TeachingWorkload copyWith({
    int? id,
    String? teacherId,
    String? teacherName,
    String? department,
    String? courseSerial,
    String? courseCode,
    String? courseName,
    String? courseCategory,
    String? classNames,
    String? teachingForm,
    String? courseNature,
    double? credits,
    int? studentCount,
    int? groupNumber,
    int? groupSize,
    int? groupCount,
    double? courseCoefficient,
    int? classHours,
    double? practiceCredits,
    double? scaleCoefficient,
    double? declaredWorkload,
    double? verifiedWorkload,
    String? workloadType,
    String? otherCategory,
    String? extraHoursProject,
    String? status,
    String? aiReviewJson,
    bool? teacherConfirmed,
    String? feedback,
    String? semester,
    String? courseId,
    String? remark,
    String? createdAt,
    String? updatedAt,
  }) =>
      TeachingWorkload(
        id: id ?? this.id,
        teacherId: teacherId ?? this.teacherId,
        teacherName: teacherName ?? this.teacherName,
        department: department ?? this.department,
        courseSerial: courseSerial ?? this.courseSerial,
        courseCode: courseCode ?? this.courseCode,
        courseName: courseName ?? this.courseName,
        courseCategory: courseCategory ?? this.courseCategory,
        classNames: classNames ?? this.classNames,
        teachingForm: teachingForm ?? this.teachingForm,
        courseNature: courseNature ?? this.courseNature,
        credits: credits ?? this.credits,
        studentCount: studentCount ?? this.studentCount,
        groupNumber: groupNumber ?? this.groupNumber,
        groupSize: groupSize ?? this.groupSize,
        groupCount: groupCount ?? this.groupCount,
        courseCoefficient: courseCoefficient ?? this.courseCoefficient,
        classHours: classHours ?? this.classHours,
        practiceCredits: practiceCredits ?? this.practiceCredits,
        scaleCoefficient: scaleCoefficient ?? this.scaleCoefficient,
        declaredWorkload: declaredWorkload ?? this.declaredWorkload,
        verifiedWorkload: verifiedWorkload ?? this.verifiedWorkload,
        workloadType: workloadType ?? this.workloadType,
        otherCategory: otherCategory ?? this.otherCategory,
        extraHoursProject: extraHoursProject ?? this.extraHoursProject,
        status: status ?? this.status,
        aiReviewJson: aiReviewJson ?? this.aiReviewJson,
        teacherConfirmed: teacherConfirmed ?? this.teacherConfirmed,
        feedback: feedback ?? this.feedback,
        semester: semester ?? this.semester,
        courseId: courseId ?? this.courseId,
        remark: remark ?? this.remark,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class WorkloadDao {
  final _courseDao = CourseDao();

  Future<List<TeachingWorkload>> getWorkloads({
    String? teacherId,
    String? semester,
    String? status,
    String? courseId,
    bool filterByCourse = true,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final where = <String>[];
    final args = <dynamic>[];
    if (teacherId != null) {
      where.add('teacher_id = ?');
      args.add(teacherId);
    }
    if (semester != null) {
      where.add('semester = ?');
      args.add(semester);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (filterByCourse) {
      final resolvedCourseId = courseId ?? await _resolveCourseId();
      if (resolvedCourseId != null && resolvedCourseId.isNotEmpty) {
        where.add('course_id = ?');
        args.add(resolvedCourseId);
      }
    }
    final rows = await db.query(
      'teaching_workload',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => TeachingWorkload.fromMap(r)).toList();
  }

  Future<TeachingWorkload?> getById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('teaching_workload',
        where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? TeachingWorkload.fromMap(rows.first) : null;
  }

  Future<int> insert(TeachingWorkload w) async {
    final db = await DatabaseHelper.instance.database;
    final map = w.toMap();
    map.remove('id');
    if ((map['course_id']?.toString().trim() ?? '').isEmpty) {
      map['course_id'] = await _resolveCourseId();
    }
    final now = DateTime.now().toIso8601String();
    map['created_at'] = now;
    map['updated_at'] = now;
    return db.insert('teaching_workload', map);
  }

  Future<void> update(TeachingWorkload w) async {
    final db = await DatabaseHelper.instance.database;
    final map = w.toMap();
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update('teaching_workload', map,
        where: 'id = ?', whereArgs: [w.id]);
  }

  Future<void> delete(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('teaching_workload', where: 'id = ?', whereArgs: [id]);
  }

  /// 统计概览
  Future<Map<String, double>> getStats({String? teacherId}) async {
    final db = await DatabaseHelper.instance.database;
    final resolvedCourseId = await _resolveCourseId();
    final where = <String>[];
    final args = <dynamic>[];
    if (resolvedCourseId != null && resolvedCourseId.isNotEmpty) {
      where.add('course_id = ?');
      args.add(resolvedCourseId);
    }
    if (teacherId != null) {
      where.add('teacher_id = ?');
      args.add(teacherId);
    }
    final whereClause =
        where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';
    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(calculated_workload), 0) AS total,
        COALESCE(SUM(CASE WHEN status = 'approved' THEN verified_workload ELSE 0 END), 0) AS approved,
        COALESCE(SUM(CASE WHEN status = 'submitted' THEN calculated_workload ELSE 0 END), 0) AS pending
      FROM teaching_workload $whereClause
    ''', args.isNotEmpty ? args : null);
    final row = result.isNotEmpty ? result.first : {};
    return {
      'total': (row['total'] as num?)?.toDouble() ?? 0,
      'approved': (row['approved'] as num?)?.toDouble() ?? 0,
      'pending': (row['pending'] as num?)?.toDouble() ?? 0,
    };
  }

  /// 批量导入工作量数据
  Future<int> batchImport(List<TeachingWorkload> workloads) async {
    final db = await DatabaseHelper.instance.database;
    int count = 0;
    for (final w in workloads) {
      try {
        final map = w.toMap();
        map.remove('id');
        final now = DateTime.now().toIso8601String();
        map['created_at'] = now;
        map['updated_at'] = now;
        await db.insert('teaching_workload', map);
        count++;
      } catch (e, st) {
        swallowDebug(e, tag: 'WorkloadDao.batchImport', stack: st);
      }
    }
    return count;
  }

  Future<String?> _resolveCourseId() async {
    try {
      return (await _courseDao.getActiveCourse())?.id;
    } catch (e, st) {
      swallowDebug(e, tag: 'WorkloadDao._resolveCourseId', stack: st);
      return null;
    }
  }
}
