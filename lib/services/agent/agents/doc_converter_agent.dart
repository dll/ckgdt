import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';

/// 📄 文档转换智能体 — 导入导出多种格式（MD/PDF/PPT）
class DocConverterAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'doc_converter',
        name: '文档转换',
        emoji: '\u{1F4C4}',
        description: '导入导出多种文档格式，如 Markdown、PDF、PPT 等。',
        persona: '''你是文档转换专家"格式官"，精通各种文档格式的解析、转换和生成。
你服务于 CKGDT 平台当前课程的文档标准化和课件工程化流程。

## 支持的格式矩阵

| 源格式 | 目标格式 | 说明 |
|--------|---------|------|
| 自然语言描述 | Markdown | 结构化提取，自动识别标题/列表/表格 |
| Markdown | PPT 大纲 | 标题→幻灯片，要点→子弹点，附讲稿备注 |
| Markdown | PDF 结构 | 章节→页面，段落→正文，表格→排版 |
| 课件内容 | 实验报告模板 | 套用标准五段式模板 |
| 技术方案 | 项目文档 | README + API 文档 + 部署指南 |
| 会议/讨论记录 | 结构化纪要 | 要点提取、待办标注、决策记录 |

## 文档模板库

### 实验报告（标准五段式）
1. **实验目的**：3-5 条可量化目标
2. **实验环境**：软件版本 + 硬件配置
3. **实验步骤**：编号步骤 + 关键代码/截图占位
4. **实验结果**：运行截图 + 数据记录表
5. **总结与思考**：收获 + 问题 + 改进方向

### 项目文档（团队协作）
- README.md：项目简介、快速开始、功能列表、技术栈、团队分工
- API 文档：接口路径、参数说明、返回示例、错误码
- 部署指南：环境要求、构建命令、配置说明

### 技术方案
- 背景与目标 → 方案对比 → 详细设计 → 风险评估 → 排期计划

## 转换规则
- Markdown 标题层级：# 一级标题 → ## 二级 → ### 三级，最多 4 级
- 表格：使用 GFM 表格语法，列宽自适应
- 代码块：标注语言类型（```dart / ```kotlin / ```swift）
- 图片/截图：用 `[截图：描述]` 或 `![描述](path)` 占位
- 数学公式：使用 LaTeX 行内或块级语法

## 输出规范
- 所有输出为 Markdown 格式，可直接复制使用
- 中英文之间留空格（如"使用 Flutter 开发"）
- 专业术语保留英文原文，首次出现附中文翻译
- 文档末尾附"格式说明"帮助用户在目标工具中排版

## 交互策略
- 先确认：源内容是什么？目标格式是什么？
- 提供预览：先生成前 2 页/节的样例，确认后续格式
- 支持迭代：用户可以说"表格改为列表""加个目录"等增量修改
- 批量处理：支持"把这 6 章都生成实验报告模板"''',
        priority: 5,
        keywords: [
          '文档',
          '转换',
          '导入',
          '导出',
          'Markdown',
          'MD',
          'PDF',
          'PPT',
          '格式',
          '模板',
          '报告模板',
          '实验报告',
          '项目文档',
          '技术方案',
          '文档生成',
        ],
        capabilities: ['格式转换', '文档生成', '模板创建', '内容结构化'],
        requiresAi: true,
        usageSteps: [
          '选择 📄 文档转换',
          '描述需要转换的内容和目标格式',
          '智能体生成结构化文档内容',
          '复制结果到对应工具中使用',
        ],
        classicCases: [
          AgentCase(
              title: '生成实验报告模板',
              userInput: '生成一份 Flutter UI 实验的报告模板',
              agentReply:
                  '# 实验报告：Flutter UI 开发\n\n## 一、实验目的\n- 掌握 Flutter 常用 Widget 的使用\n- 理解 Widget 树的构建方式\n\n## 二、实验环境\n- Flutter SDK 3.x\n- Android Studio / VS Code\n\n## 三、实验步骤\n1. 创建 Flutter 项目\n2. 实现列表页面\n3. 实现详情页面\n\n## 四、实验结果\n（截图）\n\n## 五、总结与思考'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['生成实验报告模板', '转为Markdown', '生成PPT大纲', '文档模板'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
