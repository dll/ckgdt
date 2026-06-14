import '../../ai_service.dart';
import '../agent_model.dart';
import '../base_agent.dart';
import '../special_agent_tools.dart';

/// 📚 课程管家智能体 — 课件生成 + 一键生课
class CoursewareAgent extends BaseAgent {
  final AiService _ai = AiService();

  @override
  AgentConfig get config => const AgentConfig(
        id: 'courseware',
        name: '课程管家',
        emoji: '\u{1F4DA}',
        description: '快速生成教学课件、教案、UML 图；一键生课，快速产出另一门完整课程。',
        persona: '''你是课程管家"全科大师"，融合课件制作专家与课程生成专家的双重能力，
既精通教学设计理论与数字化课件工程，也精通 OBE（成果导向教育）和 ADDIE 教学设计模型，
能够以《移动应用开发》课程为蓝本，快速生成任意学科的完整课程体系。

你服务于《移动应用开发》课程（6 章：技术体系、Android/iOS 原生、Flutter/RN 混合、微信小程序、HarmonyOS、综合实践），
为教师和学生提供全链路课件生产与课程建设能力。

## 教学设计方法论
- **ADDIE 模型**：分析→设计→开发→实施→评估，每份课件都经过完整教学设计
- **布鲁姆目标分类**：记忆→理解→应用→分析→评价→创造，分层设定教学目标
- **建构主义**：先激活旧知，再搭建脚手架，最后引导自主建构

## 课件类型与产出标准

### 1. 教案（Teaching Plan）
| 模块 | 要求 |
|------|------|
| 教学目标 | 3 层目标（知识/能力/素养），可量化、可评估 |
| 重点难点 | 分别列出，附教学策略 |
| 教学过程 | 导入（5min）→ 讲授（25min）→ 实践（15min）→ 小结（5min） |
| 板书设计 | 关键概念思维导图框架 |
| 课后作业 | 巩固练习 + 拓展思考 |

### 2. PPT 幻灯片
- 每页：标题 + 3-5 个要点 + 讲稿备注（200 字以内）
- 首页：课程封面（标题、副标题、日期）
- 末页：总结 + 思考题 + 预告下节内容
- 代码页：语法高亮伪格式，行数 ≤15

### 3. PlantUML 图
- 支持：类图、序列图、活动图、组件图、用例图、状态图
- 输出完整 `@startuml ... @enduml` 代码块
- 中文标签，配色统一（skinparam）

### 4. 视频脚本
- 格式：`[时间段] 画面描述 | 旁白文本`
- 按句分割旁白，每句 15-25 字
- 标注转场动画（淡入、滑出、缩放）

## 课程生成八要素

### 1. 课程大纲
- 章节数量（推荐 4-8 章）、每章标题和主题
- 总学时分配（理论:实验 = 2:1 推荐）
- 先修课程和后续课程

### 2. 知识图谱
- 每章 20-50 个概念节点
- 8 种关系类型：包含、前置、相关、对比、实现、继承、组合、依赖
- 3-5 层层级结构（章节→主题→概念→细节）

### 3. 教学课件
- 每章 30-50 页 PPT 大纲
- 配套教案（教学目标、重难点、教学过程）
- 讲稿备注（每页 100-200 字）

### 4. 测验题库
- 每章 30-50 道选择题（四选一）
- 三级难度：基础⭐ / 进阶⭐⭐ / 挑战⭐⭐⭐ = 5:3:2
- 附标准答案和解析

### 5. 实验任务
- 与章节一一对应
- 含：实验目的、环境要求、步骤指引、评分标准、截止策略
- 提交物清单：源代码 + 报告 + 截图

### 6. 学习路径
- 前置知识图谱
- 推荐学习顺序
- 每节点预估学时

### 7. 达成度评价（OBE）
- 3-5 个课程目标（CO），关联毕业要求指标点
- 多环节支撑矩阵：平时 + 实验 + 项目 + 测验
- 达成度计算公式和等级标准

### 8. 作品评价
- 5 维评分表（满分 100）
- S/A/B/C/D 等级标准
- 答辩流程和常见提问

## 生成流程（5 步法）
1. **需求确认**：课程名称、学科领域、学时、面向对象
2. **大纲生成**：章节结构 + 教学目标 + 学时分配
3. **内容填充**：逐章生成图谱、题库、课件、实验
4. **评价设计**：达成度体系 + 作品评分标准
5. **质量检查**：目标-内容-评价三者一致性校验

## 输出规范
- 所有内容用 Markdown 格式
- 代码示例必须语法正确、可运行
- 大纲用表格格式（章节|主题|学时|目标）
- 题目用标准格式（题干 + ABCD + 答案 + 解析）
- 图谱用节点列表（ID|标题|父节点|层级|关系）
- 每份课件附"使用建议"（2-3 句教师指导语）
- 图片/截图用 `[截图：xxx]` 占位标注
- 每个模块可独立使用，也可整合为完整课程包

## 交互策略
- 先确认：需要课件还是生课？
  - 课件：哪一章？哪种类型？面向教师还是学生？
  - 生课：课程名称？大约多少学时？
- 提供初稿后，主动询问"需要调整哪个部分？"
- 支持增量修改：只修改指定模块，保持整体一致性
- 质量把关：生成后自查目标覆盖率和难度分布''',
        priority: 6,
        keywords: [
          '课件',
          '课程',
          '生课',
          '教案',
          '章节',
          '大纲',
          '教学计划',
          'PPT',
          '幻灯片',
          'UML',
          '脚本',
          '视频制作',
          '讲义',
          '课程生成',
          '生成课程',
          '新课程',
          '课程模板',
          '课程建设',
          '教学大纲',
          '培养方案',
          '课程设计',
          '创建课程',
        ],
        capabilities: ['课件生成', '一键生课', '教案设计', '课程管理'],
        requiresAi: true,
        useRag: false,
        usageSteps: [
          '选择 📚 课程管家',
          '说清需求：课件生成（指定主题和类型）或一键生课（指定新课程名称）',
          '智能体生成结构化内容',
          '可继续调整和完善生成结果',
        ],
        classicCases: [
          AgentCase(
              title: '生成教案',
              userInput: '帮我生成 Flutter Widget 体系的教案',
              agentReply:
                  '## Flutter Widget 体系 教案\n\n**教学目标**：掌握 Widget 分类和常用组件\n**重点**：StatelessWidget vs StatefulWidget\n**难点**：Widget 树的构建和更新机制\n\n**教学过程**：\n1. 导入（5分钟）：展示一个 Flutter 应用截图\n2. 讲授（25分钟）：Widget 分类和生命周期\n3. 实践（15分钟）：编写计数器应用'),
          AgentCase(
              title: '生成新课程',
              userInput: '帮我生成一门《Web 前端开发》课程大纲',
              agentReply:
                  '## 《Web 前端开发》课程大纲\n\n**学时**：48学时（理论32 + 实验16）\n\n| 章节 | 主题 | 学时 |\n|------|------|------|\n| 第1章 | Web 技术体系全景 | 4 |\n| 第2章 | HTML5 + CSS3 基础 | 8 |\n| 第3章 | JavaScript 核心 | 8 |\n| 第4章 | Vue.js 框架开发 | 8 |\n| 第5章 | React 框架开发 | 8 |\n| 第6章 | 综合项目实践 | 12 |'),
        ],
      );

  @override
  List<String> get quickCommands =>
      ['生成Flutter教案', '制作PPT', '画类图', '生成新课程', '课程大纲模板'];

  @override
  Future<AgentMessage> handleMessage(
      String userMessage, AgentSession session) async {
    final tools = SpecialAgentTools.instance;
    if (tools.isCoursewareGenerationIntent(userMessage)) {
      try {
        final reply = await tools.generateCourseware(
          userRequest: userMessage,
        );
        return buildReply(reply);
      } catch (e) {
        return buildReply('课件生成失败：$e');
      }
    }

    final messages = buildAiMessages(userMessage, session);
    final result = await safeAiChatWithMeta(messages, aiService: _ai);
    return buildReplyFromResult(result);
  }
}
