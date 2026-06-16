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

  /// AI 已自动生成批阅草稿，通知教师审核
  Future<void> notifyLabAutoGraded({
    required String studentId,
    required String studentName,
    required String taskTitle,
    required int taskId,
    required int score,
  }) async {
    try {
      final entityId = 'lab_grade_${taskId}_$studentId';
      await _notificationDao.createNotification(
        title: 'AI 批阅就绪：$studentName',
        content: 'AI 已为 $studentName 的实验「$taskTitle」生成评分草稿（$score 分），等待教师审核。',
        creatorId: 'system',
        targetType: 'teachers',
        type: 'ai_grading',
        relatedEntityType: 'lab_submission',
        relatedEntityId: entityId,
      );
      debugPrint('NotificationService: AI 批阅就绪通知 — $studentName / $score 分');
    } catch (e) {
      debugPrint('NotificationService: AI 批阅就绪通知失败 — $e');
    }
  }

  /// 通知学生：教师已审核完成 AI 批阅
  Future<void> notifyLabGradeApproved({
    required String studentId,
    required String taskTitle,
    required int score,
  }) async {
    try {
      await _notificationDao.createNotification(
        title: '实验批阅已完成',
        content: '你的实验「$taskTitle」已批阅完成，得分 $score 分，请到实验 Tab 查看详情。',
        creatorId: 'system',
        targetType: 'individual',
        targetId: studentId,
        type: 'grade',
        relatedEntityType: 'lab_submission',
      );
    } catch (e) {
      debugPrint('NotificationService: 学生批阅完成通知失败 — $e');
    }
  }

  /// 通知学生：实验报告被教师打回，需要重新提交
  Future<void> notifyLabSubmissionReturned({
    required String studentId,
    required String taskTitle,
    required String reason,
  }) async {
    try {
      final preview =
          reason.length > 160 ? '${reason.substring(0, 160)}...' : reason;
      await _notificationDao.createNotification(
        title: '实验报告已打回',
        content: '你的实验「$taskTitle」未通过审核，需要修改后重新提交。原因：$preview',
        creatorId: 'system',
        targetType: 'individual',
        targetId: studentId,
        type: 'return',
        relatedEntityType: 'lab_submission',
      );
    } catch (e) {
      debugPrint('NotificationService: 实验打回通知学生失败 — $e');
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
      debugPrint(
          'NotificationService: 贡献评分通知 — $scorerName → $targetName ($dimension)');
    } catch (e) {
      debugPrint('NotificationService: 发送贡献评分通知失败 — $e');
    }
  }

  /// 学生/用户提交问题反馈时通知所有教师和管理员
  Future<void> notifyFeedbackSubmission({
    required String userId,
    required String userName,
    required String content,
  }) async {
    try {
      final preview =
          content.length > 80 ? '${content.substring(0, 80)}...' : content;
      await _notificationDao.createNotification(
        title: '用户反馈：$userName',
        content: '$userName 提交了问题反馈：$preview',
        creatorId: userId,
        targetType: 'teachers',
        type: 'feedback',
        relatedEntityType: 'feedback',
        relatedEntityId: 'feedback_$userId',
      );
      debugPrint('NotificationService: 反馈提交通知 — $userName');
    } catch (e) {
      debugPrint('NotificationService: 发送反馈提交通知失败 — $e');
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

  // ─────────────────────────────────────────────────────────────────────────
  // AI 自动批阅 → 教师待复核（assessment / works）
  // ─────────────────────────────────────────────────────────────────────────

  /// AI 已为考核报告生成评分草稿，通知教师审核
  Future<void> notifyAssessmentAutoGraded({
    required String studentId,
    required String studentName,
    required String reportType,
    required int score,
  }) async {
    try {
      await _notificationDao.createNotification(
        title: 'AI 批阅就绪：$studentName',
        content: 'AI 已为 $studentName 的「$reportType」生成评分草稿（$score 分），等待教师审核。',
        creatorId: 'system',
        targetType: 'teachers',
        type: 'ai_grading',
        relatedEntityType: 'assessment_report',
        relatedEntityId: 'assessment_grade_${reportType}_$studentId',
      );
    } catch (e) {
      debugPrint('NotificationService: 考核 AI 批阅就绪通知失败 — $e');
    }
  }

  /// AI 已为作品生成评分草稿，通知教师审核
  Future<void> notifyWorkAutoGraded({
    required String studentId,
    required String studentName,
    required String workTitle,
    required int workId,
    required int score,
  }) async {
    try {
      await _notificationDao.createNotification(
        title: 'AI 批阅就绪：$studentName',
        content: 'AI 已为 $studentName 的作品「$workTitle」生成评分草稿（$score 分），等待教师审核。',
        creatorId: 'system',
        targetType: 'teachers',
        type: 'ai_grading',
        relatedEntityType: 'work_submission',
        relatedEntityId: 'work_grade_$workId',
      );
    } catch (e) {
      debugPrint('NotificationService: 作品 AI 批阅就绪通知失败 — $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AI 草稿就绪 → 通知学生（提交后选择"稍后通知"路径）
  // ─────────────────────────────────────────────────────────────────────────

  /// AI 草稿就绪 — 学生侧 "AI 已批阅，等待教师复核"
  Future<void> notifyStudentAiDraftReady({
    required String studentId,
    required String domain, // 'lab' / 'assessment' / 'work'
    required String entityTitle,
    required int aiScore,
  }) async {
    final domainName = {
          'lab': '实验',
          'assessment': '考核',
          'work': '作品',
        }[domain] ??
        '提交';
    try {
      await _notificationDao.createNotification(
        title: 'AI 已批阅 ($domainName)：$entityTitle',
        content: 'AI 给出 $aiScore 分（草稿）。教师复核后即为最终成绩，可在通知或对应页面查看优点 / 改进建议。',
        creatorId: 'system',
        targetType: 'individual',
        targetId: studentId,
        type: 'ai_grading',
        relatedEntityType: '${domain}_submission',
      );
    } catch (e) {
      debugPrint('NotificationService: AI 草稿就绪通知学生失败 — $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 教师复核完成 → 通知学生（assessment / works，lab 已有 notifyLabGradeApproved）
  // ─────────────────────────────────────────────────────────────────────────

  /// 通知学生：教师已审核完成 AI 批阅（考核报告）
  Future<void> notifyAssessmentGradeApproved({
    required String studentId,
    required String reportType,
    required int score,
  }) async {
    try {
      await _notificationDao.createNotification(
        title: '考核批阅已完成',
        content: '你的「$reportType」已批阅完成，得分 $score 分。请到考核 Tab 查看详情。',
        creatorId: 'system',
        targetType: 'individual',
        targetId: studentId,
        type: 'grade',
        relatedEntityType: 'assessment_report',
      );
    } catch (e) {
      debugPrint('NotificationService: 考核批阅完成通知学生失败 — $e');
    }
  }

  /// 通知学生：教师已审核完成 AI 批阅（作品）
  Future<void> notifyWorkGradeApproved({
    required String studentId,
    required String workTitle,
    required int score,
  }) async {
    try {
      await _notificationDao.createNotification(
        title: '作品批阅已完成',
        content: '你的作品「$workTitle」已批阅完成，得分 $score 分。请到作品页查看详情。',
        creatorId: 'system',
        targetType: 'individual',
        targetId: studentId,
        type: 'grade',
        relatedEntityType: 'work_submission',
      );
    } catch (e) {
      debugPrint('NotificationService: 作品批阅完成通知学生失败 — $e');
    }
  }

  /// 通知学生已被授权答辩直播
  Future<int?> notifyDefenseAuthorized({
    required String studentId,
    required String studentName,
    required String serverIp,
  }) async {
    try {
      final notificationId = await _notificationDao.createNotification(
        title: '答辩直播授权',
        content: '你已被授权参加答辩直播。教师机 IP: $serverIp，请打开答辩页面连接。',
        creatorId: 'system',
        targetType: 'individual',
        targetId: studentId,
        type: 'defense',
        relatedEntityType: 'defense_live',
        relatedEntityId: 'defense_auth_$studentId',
      );
      debugPrint('NotificationService: 答辩授权通知 — $studentName → $serverIp');
      return notificationId;
    } catch (e) {
      debugPrint('NotificationService: 发送答辩授权通知失败 — $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 应用更新通知
  // ─────────────────────────────────────────────────────────────────────────

  /// 新版本发布时通知所有用户
  Future<void> notifyAppUpdate({
    required String newVersion,
    required String releaseNotes,
  }) async {
    try {
      final preview = releaseNotes.length > 100
          ? '${releaseNotes.substring(0, 100)}...'
          : releaseNotes;
      await _notificationDao.createNotification(
        title: '新版本 v$newVersion 已发布',
        content: '新版本 v$newVersion 可供更新。$preview',
        creatorId: 'system',
        targetType: 'all',
        type: 'update',
        relatedEntityType: 'app_update',
        relatedEntityId: 'app_update_v$newVersion',
      );
      await _notificationDao.createNotification(
        title: '新版本 v$newVersion 已发布',
        content: '新版本 v$newVersion 可供更新。$preview',
        creatorId: 'system',
        targetType: 'teachers',
        type: 'update',
        relatedEntityType: 'app_update',
        relatedEntityId: 'app_update_v$newVersion',
      );
      debugPrint('NotificationService: 应用更新通知 — v$newVersion');
    } catch (e) {
      debugPrint('NotificationService: 发送应用更新通知失败 — $e');
    }
  }
}
