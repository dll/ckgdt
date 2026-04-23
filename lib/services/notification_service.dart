import 'package:flutter/foundation.dart';
import '../data/local/notification_dao.dart';

/// 通知服务 — 纯事件驱动，仅在业务事件发生时创建通知
///
/// 单例模式，负责：
/// - 学生提交实验/考核/作品/贡献评分时通知教师
/// - 提供未读计数查询
///
/// 不做任何定时轮询或自动生成通知。
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final NotificationDao _notificationDao = NotificationDao();

  // ─────────────────────────────────────────────────────────────────────────
  // 便捷方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取用户未读通知数量（代理到 DAO）
  Future<int> getUnreadCount(String userId) async {
    return await _notificationDao.getUnreadCount(userId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 事件驱动通知 — 业务事件触发时调用
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
