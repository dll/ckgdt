import '../local/database_helper.dart';

/// 教师申请 DAO
class TeacherApplicationDao {
  Future<int> submitApplication({
    required String applicantId,
    String? applicantName,
    required String workId,
    String? school,
    String? reason,
  }) async {
    final db = await DatabaseHelper.instance.database;
    // 检查是否已有待审核申请
    final existing = await db.query(
      'teacher_applications',
      where: 'applicant_id = ? AND status = ?',
      whereArgs: [applicantId, 'pending'],
    );
    if (existing.isNotEmpty) {
      throw Exception('您已有一个待审核的申请');
    }
    return await db.insert('teacher_applications', {
      'applicant_id': applicantId,
      'applicant_name': applicantName,
      'work_id': workId,
      'school': school,
      'reason': reason,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 获取所有待审核申请
  Future<List<Map<String, dynamic>>> getPendingApplications() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query(
      'teacher_applications',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at DESC',
    );
  }

  /// 获取所有申请（含已审核）
  Future<List<Map<String, dynamic>>> getAllApplications() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query(
      'teacher_applications',
      orderBy: 'created_at DESC',
    );
  }

  /// 获取某用户的申请
  Future<Map<String, dynamic>?> getApplicationByUser(String userId) async {
    final db = await DatabaseHelper.instance.database;
    final list = await db.query(
      'teacher_applications',
      where: 'applicant_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return list.isNotEmpty ? list.first : null;
  }

  /// 审核申请
  Future<void> reviewApplication({
    required int applicationId,
    required String reviewerId,
    required bool approved,
    String? comment,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'teacher_applications',
      {
        'status': approved ? 'approved' : 'rejected',
        'reviewer_id': reviewerId,
        'review_comment': comment,
        'reviewed_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [applicationId],
    );

    // 若通过，升级用户角色为 teacher
    if (approved) {
      final app = await db.query('teacher_applications',
          where: 'id = ?', whereArgs: [applicationId]);
      if (app.isNotEmpty) {
        final applicantId = app.first['applicant_id'] as String;
        await db.update(
          'users',
          {'role': 'teacher'},
          where: 'user_id = ?',
          whereArgs: [applicantId],
        );
      }
    }
  }

  /// 待审核数量
  Future<int> getPendingCount() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM teacher_applications WHERE status = 'pending'");
    return (result.first['cnt'] as int?) ?? 0;
  }
}
