import '../agent_model.dart';
import '../base_agent.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/resource_generation_service.dart';

/// 课件工坊智能体 — 从课程包 MD 生成 PDF / PPT / 视频脚本
class CoursewareWorkshopAgent extends BaseAgent {
  @override
  AgentConfig get config => AgentConfig(
        id: 'courseware_workshop',
        name: '课件工坊',
        emoji: '\u{1F3A8}',
        description: '从课程包自动生成 PDF 课件、PPT 幻灯片和视频脚本',
        persona: '你是一个专业的课件生成助手，擅长将课程内容转换为多种格式的教学资源。',
        keywords: ['课件', '工坊', '生成pdf', '生成ppt', '视频脚本', '生成资源', '资源生成'],
        useRag: false,
      );

  @override
  double matchScore(String userMessage, AgentSession session) {
    var score = super.matchScore(userMessage, session);
    final lower = userMessage.toLowerCase();
    if (lower.contains('课件') || lower.contains('工坊')) score += 0.9;
    if (lower.contains('生成pdf') || lower.contains('pdf课件')) score += 0.85;
    if (lower.contains('生成ppt') || lower.contains('ppt课件')) score += 0.85;
    if (lower.contains('视频脚本')) score += 0.8;
    if (lower.contains('生成资源') || lower.contains('生成全部')) score += 0.85;
    return score;
  }

  @override
  Future<AgentMessage> handleMessage(String userMessage, AgentSession session) async {
    final db = await DatabaseHelper.instance.database;

    // 获取当前课程 ID
    String? courseId;
    try {
      final sessionResult = await db.rawQuery(
          "SELECT value FROM app_settings WHERE key = 'current_course_id'");
      if (sessionResult.isNotEmpty) {
        courseId = sessionResult.first['value']?.toString();
      }
    } catch (_) {}

    if (courseId == null || courseId.isEmpty) {
      return buildReply('请先选择一个课程，然后再生成资源。');
    }

    // 判断生成类型
    final lower = userMessage.toLowerCase();
    String sourceType = 'preset';
    if (lower.contains('扩展') || lower.contains('学生')) {
      sourceType = 'extended';
    }

    // 执行生成
    final service = ResourceGenerationService();
    try {
      final results = await service.generateAll(
        courseId: courseId,
        sourceType: sourceType,
      );

      final totalGenerated =
          results.fold<int>(0, (sum, r) => sum + r.generated.length);
      final totalErrors =
          results.fold<int>(0, (sum, r) => sum + r.errors.length);

      if (totalGenerated == 0 && totalErrors > 0) {
        return buildReply('生成失败：$totalErrors 个错误。\n可能原因：课程包中没有找到 Markdown 文件。');
      }

      final buffer = StringBuffer();
      buffer.writeln('✅ 已生成 $totalGenerated 个资源：');
      for (final r in results) {
        if (r.generated.isNotEmpty) {
          buffer.writeln('  • ${r.chapter}: ${r.generated.join(", ")}');
        }
      }
      if (totalErrors > 0) {
        buffer.writeln('\n⚠️ $totalErrors 个错误：');
        for (final r in results) {
          if (r.errors.isNotEmpty) {
            buffer.writeln('  • ${r.chapter}: ${r.errors.join(", ")}');
          }
        }
      }

      return buildReply(buffer.toString());
    } catch (e) {
      return buildReply('生成过程出错: $e');
    }
  }
}
