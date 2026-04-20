import 'package:flutter/foundation.dart';
import 'database_helper.dart';

/// 通知管理 DAO — 通知创建、查询、已读标记、阅读统计
class NotificationDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 创建通知（事务：插入通知 → 解析收件人 → 批量插入收件人）
  // ─────────────────────────────────────────────────────────────────────────

  /// 创建通知并自动分发给目标用户
  ///
  /// [targetType] 可选值：
  ///   - 'all'        → 所有活跃学生
  ///   - 'class'      → 指定班级的成员（通过 class_members 表）
  ///   - 'individual' → 单个用户
  ///   - 'teachers'   → 所有教师和管理员
  Future<int> createNotification({
    required String title,
    required String content,
    String? creatorId,
    String targetType = 'all',
    String? targetId,
    String type = 'manual',
    String? relatedEntityType,
    String? relatedEntityId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    return await db.transaction((txn) async {
      // 1) 插入通知主表
      final notificationId = await txn.insert('notifications', {
        'title': title,
        'content': content,
        'type': type,
        'creator_id': creatorId,
        'target_type': targetType,
        'target_id': targetId,
        'related_entity_type': relatedEntityType,
        'related_entity_id': relatedEntityId,
        'created_at': now,
      });

      // 2) 根据 targetType 解析收件人列表
      List<Map<String, dynamic>> recipients = [];

      switch (targetType) {
        case 'all':
          // 查询所有活跃学生
          recipients = await txn.query(
            'users',
            columns: ['user_id'],
            where: "role = 'student' AND is_active = 1",
          );
          break;

        case 'class':
          // 查询指定班级的成员
          if (targetId != null) {
            recipients = await txn.rawQuery(
              'SELECT user_id FROM class_members WHERE class_id = ?',
              [int.tryParse(targetId) ?? 0],
            );
          }
          break;

        case 'individual':
          // 单个用户
          if (targetId != null) {
            recipients = [
              {'user_id': targetId}
            ];
          }
          break;

        case 'teachers':
          // 查询所有教师和管理员
          recipients = await txn.query(
            'users',
            columns: ['user_id'],
            where: "role IN ('teacher', 'admin') AND is_active = 1",
          );
          break;
      }

      // 3) 批量插入 notification_recipients
      final batch = txn.batch();
      for (final r in recipients) {
        final userId = r['user_id'] as String?;
        if (userId == null) continue;
        batch.insert('notification_recipients', {
          'notification_id': notificationId,
          'user_id': userId,
          'is_read': 0,
        });
      }
      await batch.commit(noResult: true);

      debugPrint('NotificationDao: 创建通知 #$notificationId，'
          '分发给 ${recipients.length} 位用户');

      return notificationId;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 查询通知列表
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取指定用户的通知列表（LEFT JOIN 读取状态）
  ///
  /// 返回 Map 包含：id, title, content, type, creator_id, creator_name,
  ///   target_type, created_at, is_read, read_at
  Future<List<Map<String, dynamic>>> getNotificationsForUser(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT
        n.id,
        n.title,
        n.content,
        n.type,
        n.creator_id,
        u.real_name AS creator_name,
        n.target_type,
        n.target_id,
        n.related_entity_type,
        n.related_entity_id,
        n.created_at,
        nr.is_read,
        nr.read_at
      FROM notifications n
      LEFT JOIN notification_recipients nr
        ON n.id = nr.notification_id AND nr.user_id = ?
      LEFT JOIN users u ON n.creator_id = u.user_id
      WHERE nr.user_id = ?
      ORDER BY n.created_at DESC
      LIMIT ? OFFSET ?
    ''', [userId, userId, limit, offset]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 未读计数
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取用户未读通知数量
  Future<int> getUnreadCount(String userId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM notification_recipients '
      'WHERE user_id = ? AND is_read = 0',
      [userId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 已读标记
  // ─────────────────────────────────────────────────────────────────────────

  /// 标记单条通知为已读
  Future<void> markAsRead(int notificationId, String userId) async {
    final db = await _dbHelper.database;
    await db.update(
      'notification_recipients',
      {
        'is_read': 1,
        'read_at': DateTime.now().toIso8601String(),
      },
      where: 'notification_id = ? AND user_id = ? AND is_read = 0',
      whereArgs: [notificationId, userId],
    );
  }

  /// 将用户所有未读通知标记为已读
  Future<void> markAllAsRead(String userId) async {
    final db = await _dbHelper.database;
    await db.update(
      'notification_recipients',
      {
        'is_read': 1,
        'read_at': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ? AND is_read = 0',
      whereArgs: [userId],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 删除通知（级联删除 notification_recipients）
  // ─────────────────────────────────────────────────────────────────────────

  /// 删除通知（ON DELETE CASCADE 自动清理收件人表）
  Future<void> deleteNotification(int id) async {
    final db = await _dbHelper.database;
    await db.delete('notifications', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 自动提醒去重
  // ─────────────────────────────────────────────────────────────────────────

  /// 检查是否已为某实体创建过自动提醒
  ///
  /// 用于 NotificationService.checkAndCreateReminders() 去重
  Future<bool> reminderExists(String entityType, String entityId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM notifications "
      "WHERE type = 'auto_reminder' "
      "AND related_entity_type = ? AND related_entity_id = ?",
      [entityType, entityId],
    );
    return ((result.first['c'] as int?) ?? 0) > 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 阅读状态统计（教师/管理员查看）
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取某条通知的所有收件人阅读状态
  ///
  /// 返回 List<Map> 包含：user_id, real_name, is_read, read_at
  Future<List<Map<String, dynamic>>> getNotificationReadStatus(
      int notificationId) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT
        nr.user_id,
        u.real_name,
        nr.is_read,
        nr.read_at
      FROM notification_recipients nr
      LEFT JOIN users u ON nr.user_id = u.user_id
      WHERE nr.notification_id = ?
      ORDER BY nr.is_read ASC, u.real_name
    ''', [notificationId]);
  }

  /// 获取某条通知的已读/总人数统计
  Future<Map<String, int>> getNotificationReadStats(
      int notificationId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN is_read = 1 THEN 1 ELSE 0 END) AS read_count
      FROM notification_recipients
      WHERE notification_id = ?
    ''', [notificationId]);
    return {
      'total': (result.first['total'] as int?) ?? 0,
      'read_count': (result.first['read_count'] as int?) ?? 0,
    };
  }
}
