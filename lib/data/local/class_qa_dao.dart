import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import '../models/class_qa_model.dart';

/// 班级问答广场 DAO（class_qa + class_qa_replies 两张表）
class ClassQaDao {
  ClassQaDao._();
  static final ClassQaDao instance = ClassQaDao._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ── 问题 ─────────────────────────────────────────────────────────────

  /// 创建问题；返回 id。
  Future<int> create(ClassQaModel qa) async {
    try {
      final db = await _dbHelper.database;
      return await db.insert('class_qa', qa.toMap());
    } catch (e) {
      debugPrint('ClassQaDao.create failed: $e');
      return -1;
    }
  }

  /// 列出问题（按可见性过滤）。
  ///
  /// [viewerId] 当前用户；私有问题只对 authorId == viewerId 或 viewerIsTeacher 可见。
  Future<List<ClassQaModel>> list({
    required String viewerId,
    required bool viewerIsTeacher,
    String? classId,
    String? status, // 'open' / 'answered' / 'closed' / null=全部
    int limit = 50,
  }) async {
    try {
      final db = await _dbHelper.database;
      final whereParts = <String>[];
      final args = <dynamic>[];

      if (classId != null && classId.isNotEmpty) {
        whereParts.add('class_id = ?');
        args.add(classId);
      }
      if (status != null) {
        whereParts.add('status = ?');
        args.add(status);
      }
      // 可见性：教师可见全部；学生可见 'class' 或自己提的 'private'
      if (!viewerIsTeacher) {
        whereParts.add("(visibility = 'class' OR author_id = ?)");
        args.add(viewerId);
      }

      final rows = await db.query(
        'class_qa',
        where: whereParts.isEmpty ? null : whereParts.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'updated_at DESC',
        limit: limit,
      );
      return rows.map(ClassQaModel.fromMap).toList();
    } catch (e) {
      debugPrint('ClassQaDao.list failed: $e');
      return [];
    }
  }

  /// 取一个问题详情。
  Future<ClassQaModel?> get(int id) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db
          .query('class_qa', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      return ClassQaModel.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// 更新状态 / 采纳的最佳回复。
  Future<bool> updateStatus(int qaId,
      {String? status, int? acceptedReplyId}) async {
    try {
      final db = await _dbHelper.database;
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status != null) updates['status'] = status;
      if (acceptedReplyId != null) {
        updates['accepted_reply_id'] = acceptedReplyId;
      }
      final n = await db.update('class_qa', updates,
          where: 'id = ?', whereArgs: [qaId]);
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(int qaId) async {
    try {
      final db = await _dbHelper.database;
      await db.delete('class_qa_replies', where: 'qa_id = ?', whereArgs: [qaId]);
      final n = await db.delete('class_qa', where: 'id = ?', whereArgs: [qaId]);
      return n > 0;
    } catch (_) {
      return false;
    }
  }

  // ── 回复 ─────────────────────────────────────────────────────────────

  Future<int> addReply(ClassQaReplyModel reply) async {
    try {
      final db = await _dbHelper.database;
      final id = await db.insert('class_qa_replies', reply.toMap());
      // 更新问题状态：教师首次回复 → answered
      if (reply.isTeacher) {
        await db.update(
          'class_qa',
          {
            'status': 'answered',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ? AND status = ?',
          whereArgs: [reply.qaId, 'open'],
        );
      } else {
        // 学生回复也更新 updated_at
        await db.update(
          'class_qa',
          {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [reply.qaId],
        );
      }
      return id;
    } catch (e) {
      debugPrint('ClassQaDao.addReply failed: $e');
      return -1;
    }
  }

  Future<List<ClassQaReplyModel>> listReplies(int qaId) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query('class_qa_replies',
          where: 'qa_id = ?', whereArgs: [qaId], orderBy: 'created_at ASC');
      return rows.map(ClassQaReplyModel.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> incrementLike(int replyId) async {
    try {
      final db = await _dbHelper.database;
      await db.rawUpdate(
          'UPDATE class_qa_replies SET likes = likes + 1 WHERE id = ?',
          [replyId]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
