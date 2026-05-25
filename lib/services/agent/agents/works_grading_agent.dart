import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../ai_service.dart';
import '../../auth_service.dart';
import '../../video_frame_extractor.dart';
import '../../../core/dev_paths.dart';
import '../../../data/local/ai_history_dao.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 作品批阅智能体 — AI 自动批改学生作品
class WorksGradingAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'works_grading',
        name: '作品批阅助手',
        emoji: '🎨',
        description: '自动批改学生作品，按五维度评分并给出详细反馈。',
        allowedRoles: ['teacher', 'admin'],
        persona: '''你是一位资深的移动应用开发课程作品评审专家，负责批改学生提交的课程作品（App 演示视频、项目源码等）。

## 角色定位
你是专业且有洞察力的作品评审官，注重作品的完成度、技术深度和创新性。

## 批改维度（总分100分）
1. **功能完整性**（25分）：App 功能是否完整，核心流程是否可用，交互是否流畅
2. **技术实现深度**（20分）：技术栈选型、架构设计、代码规范、性能优化
3. **跨框架整合**（25分）：是否有效整合多端技术（Android/iOS/Flutter/小程序/HarmonyOS）
4. **性能与质量**（15分）：UI 美观度、响应速度、错误处理、兼容性
5. **文档与协作**（15分）：README、代码注释、Git 提交记录、演示视频质量

## 输出格式要求
请严格按以下 JSON 格式输出，不要添加任何多余文字：

```json
{
  "total_score": 85,
  "summary": "一句话总评",
  "scores": {
    "functionality": {"score": 22, "max": 25, "comment": "功能完整性评价"},
    "tech_depth": {"score": 16, "max": 20, "comment": "技术实现深度评价"},
    "integration": {"score": 21, "max": 25, "comment": "跨框架整合评价"},
    "quality": {"score": 13, "max": 15, "comment": "性能与质量评价"},
    "documentation": {"score": 13, "max": 15, "comment": "文档与协作评价"}
  },
  "strengths": ["优点1", "优点2"],
  "improvements": ["改进建议1", "改进建议2"],
  "feedback": "详细的批改反馈（200-400字）"
}
```

## 评分标准
- 90-100分：优秀，作品完成度高、技术创新、用户体验佳
- 80-89分：良好，功能完整、技术实现规范
- 70-79分：中等，核心功能实现但有瑕疵
- 60-69分：及格，基本可用但明显不足
- 60分以下：不及格，作品未达到最低标准

## 批改原则
- 关注作品的实际运行效果和用户体验
- 重视技术选型的合理性和代码质量
- 鼓励创新设计和深度技术探索
- 评估团队协作和项目管理能力
- 视频演示的专业度也应纳入考量''',
        priority: 6,
        keywords: [
          '批改', '批阅', '作品', '评分', '打分', '作品评审',
          '视频作品', '自动批改', 'works', 'grading',
        ],
        capabilities: ['作品批改', '五维度评分', '作品评审', '反馈生成'],
        requiresAi: true,
        usageSteps: [
          '在作品展示页面查看学生提交的作品',
          '点击「AI批阅」按钮启动自动批改',
          'AI将从五个维度分析作品并给出评分',
          '教师可在AI评分基础上调整各维度分数和评语',
        ],
        classicCases: [
          AgentCase(
            title: '批改 Flutter 天气 App 作品',
            userInput: '请批改以下作品：\n标题：天气预报App\n技术栈：Flutter\n描述：使用Flutter开发的跨平台天气应用，集成高德天气API，支持城市搜索、7日预报、实时天气动画。',
            agentReply: '{"total_score": 88, "summary": "优秀的Flutter跨平台天气应用，功能完整且UI精美", "scores": {"functionality": {"score": 23, "max": 25, "comment": "核心功能完整，7日预报和动画是亮点"}, "tech_depth": {"score": 17, "max": 20, "comment": "Flutter架构合理，API集成规范"}, "integration": {"score": 20, "max": 25, "comment": "Flutter天然跨平台，但缺少原生端对比"}, "quality": {"score": 14, "max": 15, "comment": "天气动画提升了用户体验"}, "documentation": {"score": 14, "max": 15, "comment": "演示视频清晰完整"}}, "feedback": "这是一个完成度很高的Flutter天气应用。天气动画效果和7日预报功能是突出亮点。建议增加小程序或HarmonyOS版本的适配以提升跨框架整合评分。"}',
          ),
        ],
      );

  @override
  List<String> get quickCommands => [
        '批改学生作品',
        '查看评分标准',
        '生成评审模板',
      ];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }

  /// 直接批改作品（供 UI 层调用）
  Future<String> gradeWork({
    required String title,
    String? description,
    String? techStack,
    String? studentName,
    String? groupName,
  }) async {
    final prompt = StringBuffer();
    prompt.writeln('请批改以下学生作品：\n');
    prompt.writeln('## 作品名称：$title');
    if (studentName != null) prompt.writeln('## 学生：$studentName');
    if (groupName != null) prompt.writeln('## 小组：$groupName');
    if (techStack != null) prompt.writeln('## 技术栈：$techStack');
    if (description != null) {
      prompt.writeln('## 作品描述：');
      prompt.writeln(description);
    }
    prompt.writeln();
    prompt.writeln('## 硬规则（必须严格遵守）');
    prompt.writeln('1. 若作品描述少于50字或内容空洞 → 分数必须低于60');
    prompt.writeln('2. 若疑似 AI 生成（无个性化痕迹、格式过于标准）→ 设置 "ai_flag": true 并扣 20 分');
    prompt.writeln('3. 必须引用评分维度（功能/技术/集成/质量/文档）作为评分依据');
    prompt.writeln('4. 分数只允许为以下值之一：{0, 60, 70, 80, 90, 100}');

    final messages = [
      {'role': 'user', 'content': prompt.toString()},
    ];

    final result = await safeAiChatWithMeta(messages, aiService: _ai, temperature: 0.2);
    unawaited(AiHistoryDao().saveMessage(
      sessionId: 'direct_${DateTime.now().millisecondsSinceEpoch}',
      agentId: config.id,
      role: 'assistant',
      content: result.content,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      tokensUsed: result.totalTokens,
      provider: result.provider,
      model: result.model,
      userId: AuthService().currentUser?.userId,
    ));
    return result.content;
  }

  /// 综合批阅：考核材料 + 项目内容 + 视频帧。**这是真正读视频的版本**。
  ///
  /// 解决 "AI 没看视频" 的痼疾：
  /// 1. 加载 `data/考核/移动应用开发综合考核方案.md`（评价标准）
  /// 2. 用 ffmpeg 抽 [frameCount] 帧（默认 5）
  /// 3. 调 [AiService.chatWithVision]（zhipu:glm-4.6v）
  /// 4. 视频缺失/抽帧失败 → fallback 到 text-only，prompt 明确告知
  ///
  /// 返回 ({content, sourcesUsed}) — sourcesUsed 标识本次是否真用了视频。
  Future<({String content, bool usedVideo, int frameCount, String? assessmentMaterial})>
      gradeWorkComprehensive({
    required String title,
    String? description,
    String? techStack,
    String? studentName,
    String? groupName,
    String? videoPath,
    String? videoUrl,
    int frameCount = 5,
  }) async {
    // 1. 加载考核材料（任意一份失败都 fallback 空）
    String? materialMd;
    try {
      materialMd = await rootBundle
          .loadString('data/考核/移动应用开发综合考核方案.md');
      // 太长截断（保留头尾）—— GLM-4V 上下文有限
      if (materialMd.length > 6000) {
        final head = materialMd.substring(0, 3500);
        final tail = materialMd.substring(materialMd.length - 2000);
        materialMd = '$head\n\n…（中段省略）…\n\n$tail';
      }
    } catch (e) {
      stderr.writeln('[WorksGradingAgent] 考核材料加载失败：$e');
    }

    // 2. 抽视频帧（仅本地路径；远程 URL 暂不下载）
    var frames = <String>[];
    var resolvedVideoPath = videoPath;
    if (resolvedVideoPath == null && videoUrl != null && videoUrl.isNotEmpty) {
      // 简单兜底：如果 videoUrl 看起来像本地相对路径，转成绝对路径试试
      if (!videoUrl.startsWith('http')) {
        resolvedVideoPath = '${DevPaths.projectRoot}/$videoUrl';
      }
    }
    if (resolvedVideoPath != null && File(resolvedVideoPath).existsSync()) {
      frames = await VideoFrameExtractor.extractKeyFrames(
        resolvedVideoPath,
        frameCount: frameCount,
      );
    }

    // 3. 拼综合 prompt（text 部分给视觉 / 文本路径都用）
    final buf = StringBuffer();
    buf.writeln('请按以下材料综合批阅学生作品：');
    buf.writeln();
    if (materialMd != null) {
      buf.writeln('## 考核标准（节选）');
      buf.writeln(materialMd);
      buf.writeln();
    }
    buf.writeln('## 学生作品信息');
    buf.writeln('- 名称：$title');
    if (studentName != null) buf.writeln('- 学生：$studentName');
    if (groupName != null) buf.writeln('- 小组：$groupName');
    if (techStack != null) buf.writeln('- 技术栈：$techStack');
    if (description != null && description.isNotEmpty) {
      buf.writeln('- 描述：');
      buf.writeln(description);
    }
    buf.writeln();
    if (frames.isNotEmpty) {
      buf.writeln('## 视频画面（${frames.length} 张关键帧 — 已附）');
      buf.writeln(
          '请结合画面分析作品的实际运行效果、UI 美观度、功能展示流畅度。');
    } else {
      buf.writeln('## 视频画面');
      buf.writeln('（未提取到视频帧，请仅按文字材料评判，不要虚构画面内容）');
    }
    buf.writeln();
    buf.writeln('## 硬规则（必须严格遵守）');
    buf.writeln('1. 严格按 system prompt 的 5 维度 + JSON 输出格式');
    buf.writeln('2. 若描述少于 50 字 → 总分必须低于 60');
    buf.writeln('3. 若画面与描述明显不符（如描述说有 AI 功能但画面只是空表单）→ 总分扣 15-25');
    buf.writeln('4. 评语必须引用具体内容（材料/描述/画面）作为依据，不可空泛');
    buf.writeln('5. 分数允许任意整数（不再限制为 60/70/80/90/100）');

    // 4. 调用：有图走 vision，无图走 text
    final AiChatResult result;
    try {
      if (frames.isNotEmpty) {
        result = await _ai.chatWithVision(
          textPrompt: buf.toString(),
          imageBase64s: frames,
          systemPrompt: config.persona,
          temperature: 0.3,
        );
      } else {
        // 没视频帧也走 chatWithVision（内部会 fallback 到普通 chat），
        // 让 prompt 里 "未提取到视频帧" 的注解被 LLM 看到。
        result = await _ai.chatWithVision(
          textPrompt: buf.toString(),
          imageBase64s: const [],
          systemPrompt: config.persona,
          temperature: 0.3,
        );
      }
    } catch (e) {
      // 视觉调用失败 → 降级到原版 text-only gradeWork
      stderr.writeln('[WorksGradingAgent] vision 失败 fallback to text: $e');
      final text = await gradeWork(
        title: title,
        description: description,
        techStack: techStack,
        studentName: studentName,
        groupName: groupName,
      );
      return (
        content: text,
        usedVideo: false,
        frameCount: 0,
        assessmentMaterial: materialMd != null ? '已加载' : null,
      );
    }

    unawaited(AiHistoryDao().saveMessage(
      sessionId: 'comprehensive_${DateTime.now().millisecondsSinceEpoch}',
      agentId: config.id,
      role: 'assistant',
      content: result.content,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      tokensUsed: result.totalTokens,
      provider: result.provider,
      model: result.model,
      userId: AuthService().currentUser?.userId,
    ));

    return (
      content: result.content,
      usedVideo: frames.isNotEmpty,
      frameCount: frames.length,
      assessmentMaterial: materialMd != null ? '已加载' : null,
    );
  }
}
