import 'package:flutter/foundation.dart';
import '../data/local/database_helper.dart';
import '../data/local/notification_dao.dart';

/// 通知服务 — 自动提醒检测与创建
///
/// 单例模式，负责：
/// - 检查即将截止的实验任务和问卷调查
/// - 自动生成截止提醒通知（去重）
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final NotificationDao _notificationDao = NotificationDao();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 自动提醒检测
  // ─────────────────────────────────────────────────────────────────────────

  /// 检查即将截止的任务和问卷，自动创建提醒通知
  ///
  /// 检测规则：
  /// - lab_tasks: due_date 在 [now, now+24h] 区间且 status='active'
  /// - surveys:   deadline 在 [now, now+24h] 区间且 status='active'
  /// - 每个实体仅创建一次提醒（通过 reminderExists 去重）
  Future<void> checkAndCreateReminders() async {
    try {
      final db = await _dbHelper.database;
      final now = DateTime.now();
      final nowStr = now.toIso8601String();
      final deadline = now.add(const Duration(hours: 24)).toIso8601String();

      // ── 检查即将截止的实验任务 ────────────────────────────────────────
      final dueTasks = await db.rawQuery('''
        SELECT id, title, due_date FROM lab_tasks
        WHERE status = 'active'
          AND due_date IS NOT NULL
          AND due_date >= ? AND due_date <= ?
      ''', [nowStr, deadline]);

      for (final task in dueTasks) {
        final taskId = task['id'].toString();
        final taskTitle = task['title'] as String? ?? '';
        final dueDate = task['due_date'] as String? ?? '';

        // 去重：已创建过则跳过
        if (await _notificationDao.reminderExists('lab_task', taskId)) {
          continue;
        }

        await _notificationDao.createNotification(
          title: '⏰ 截止提醒：$taskTitle',
          content: '实验任务 "$taskTitle" 将于 $dueDate 截止，请及时完成。',
          type: 'auto_reminder',
          targetType: 'all',
          relatedEntityType: 'lab_task',
          relatedEntityId: taskId,
        );

        debugPrint('NotificationService: 创建实验任务截止提醒 — $taskTitle');
      }

      // ── 检查即将截止的问卷调查 ────────────────────────────────────────
      final dueSurveys = await db.rawQuery('''
        SELECT id, title, deadline FROM surveys
        WHERE status = 'active'
          AND deadline IS NOT NULL
          AND deadline >= ? AND deadline <= ?
      ''', [nowStr, deadline]);

      for (final survey in dueSurveys) {
        final surveyId = survey['id'].toString();
        final surveyTitle = survey['title'] as String? ?? '';
        final surveyDeadline = survey['deadline'] as String? ?? '';

        // 去重：已创建过则跳过
        if (await _notificationDao.reminderExists('survey', surveyId)) {
          continue;
        }

        await _notificationDao.createNotification(
          title: '⏰ 截止提醒：$surveyTitle',
          content: '问卷调查 "$surveyTitle" 将于 $surveyDeadline 截止，请及时完成。',
          type: 'auto_reminder',
          targetType: 'all',
          relatedEntityType: 'survey',
          relatedEntityId: surveyId,
        );

        debugPrint('NotificationService: 创建问卷截止提醒 — $surveyTitle');
      }
    } catch (e) {
      debugPrint('NotificationService: 检查提醒时出错 — $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 便捷方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取用户未读通知数量（代理到 DAO）
  Future<int> getUnreadCount(String userId) async {
    return await _notificationDao.getUnreadCount(userId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 学生提交通知 — 通知教师/管理员
  // ─────────────────────────────────────────────────────────────────────────

  /// 学生提交实验报告时通知所有教师
  Future<void> notifyLabSubmission({
    required String studentId,
    required String studentName,
    required String taskTitle,
    required int taskId,
  }) async {
    try {
      final entityId = 'lab_${taskId}_$studentId';
      await _notificationDao.createNotification(
        title: '实验提交：$studentName',
        content: '$studentName 提交了实验「$taskTitle」的报告，请及时批改。',
        creatorId: studentId,
        targetType: 'teachers',
        type: 'submission',
        relatedEntityType: 'lab_submission',
        relatedEntityId: entityId,
      );
      debugPrint('NotificationService: 实验提交通知 — $studentName → $taskTitle');
    } catch (e) {
      debugPrint('NotificationService: 发送实验提交通知失败 — $e');
    }
  }

  /// 学生提交考核报告时通知所有教师
  Future<void> notifyAssessmentSubmission({
    required String studentId,
    required String studentName,
    required String reportType,
  }) async {
    try {
      final entityId = 'assessment_${reportType}_$studentId';
      await _notificationDao.createNotification(
        title: '考核提交：$studentName',
        content: '$studentName 提交了「$reportType」，请查阅。',
        creatorId: studentId,
        targetType: 'teachers',
        type: 'submission',
        relatedEntityType: 'assessment_report',
        relatedEntityId: entityId,
      );
      debugPrint('NotificationService: 考核提交通知 — $studentName → $reportType');
    } catch (e) {
      debugPrint('NotificationService: 发送考核提交通知失败 — $e');
    }
  }

  /// 学生提交贡献评分时通知所有教师
  Future<void> notifyContributionScore({
    required String scorerId,
    required String scorerName,
    required String targetName,
    required String dimension,
  }) async {
    try {
      final entityId = 'contrib_${dimension}_${scorerId}_$targetName';
      await _notificationDao.createNotification(
        title: '贡献评分：$scorerName',
        content: '$scorerName 提交了对 $targetName 的$dimension评价。',
        creatorId: scorerId,
        targetType: 'teachers',
        type: 'submission',
        relatedEntityType: 'contribution_score',
        relatedEntityId: entityId,
      );
      debugPrint('NotificationService: 贡献评分通知 — $scorerName → $targetName ($dimension)');
    } catch (e) {
      debugPrint('NotificationService: 发送贡献评分通知失败 — $e');
    }
  }

  /// 学生提交/上传作品时通知所有教师
  Future<void> notifyWorkSubmission({
    required String studentId,
    required String studentName,
    required String workTitle,
  }) async {
    try {
      final entityId = 'work_${workTitle}_$studentId';
      await _notificationDao.createNotification(
        title: '作品提交：$studentName',
        content: '$studentName 提交了作品「$workTitle」，请查看。',
        creatorId: studentId,
        targetType: 'teachers',
        type: 'submission',
        relatedEntityType: 'work_submission',
        relatedEntityId: entityId,
      );
      debugPrint('NotificationService: 作品提交通知 — $studentName → $workTitle');
    } catch (e) {
      debugPrint('NotificationService: 发送作品提交通知失败 — $e');
    }
  }
}
