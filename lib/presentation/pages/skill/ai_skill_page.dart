import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_theme.dart';
import '../../../services/ai_service.dart';
import '../../../services/plantuml_service.dart';
import '../../../data/local/skill_dao.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 技能定义
// ═══════════════════════════════════════════════════════════════════════════════

class _SkillDef {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String description;
  final List<String> features;
  final List<String> examples;
  final String systemPrompt;

  const _SkillDef({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.description,
    required this.features,
    required this.examples,
    required this.systemPrompt,
  });
}

const _skills = <_SkillDef>[
  _SkillDef(
    id: 'graph',
    name: '图谱技能',
    subtitle: 'AI 生成知识图谱',
    icon: Icons.account_tree,
    color: Colors.blue,
    description: '利用 AI 根据指定主题自动生成知识图谱的核心概念和关系结构。'
        '系统会分析主题领域，提取关键概念节点，建立概念间的层次和关联关系，'
        '输出结构化的知识图谱方案，可直接用于教学设计和课程规划。',
    features: [
      '自动提取主题核心概念（8-15 个节点）',
      '建立概念间层次关系（包含、依赖、关联）',
      '标注概念难度等级和学习顺序',
      '输出结构化 JSON 可导入系统',
    ],
    examples: ['Flutter 跨平台开发技术体系', 'Android 四大组件', '微信小程序开发流程', 'RESTful API 设计'],
    systemPrompt: '你是知识图谱设计专家。请根据用户给出的主题，生成一份知识图谱方案。'
        '输出格式为 Markdown，包含：\n'
        '1. 核心概念列表（8-15个），每个注明难度（初级/中级/高级）\n'
        '2. 概念间关系表（source → target，关系类型：包含/依赖/关联/扩展）\n'
        '3. 推荐学习顺序\n'
        '4. 图谱应用建议\n'
        '请用中文回答，结构清晰。',
  ),
  _SkillDef(
    id: 'path',
    name: '路径技能',
    subtitle: 'AI 规划学习路径',
    icon: Icons.route,
    color: Colors.indigo,
    description: '根据学习目标和当前水平，AI 智能规划个性化学习路径。'
        '系统会分析知识依赖关系，设计从基础到进阶的阶梯式学习计划，'
        '包含每个阶段的学习目标、推荐资源和预计时长。',
    features: [
      '基于目标逆向设计学习路线',
      '标注每阶段的前置知识和学习时长',
      '推荐配套学习资源和练习项目',
      '支持不同基础水平的差异化路径',
    ],
    examples: ['零基础学 Flutter 到独立开发 App', 'Android 开发者转型鸿蒙开发', '前端工程师学习移动端开发', '大学生 4 周掌握 Dart 语言'],
    systemPrompt: '你是学习规划专家。请根据用户的学习目标，设计一份详细的学习路径。'
        '输出格式为 Markdown，包含：\n'
        '1. 路径概览（总时长、阶段数、目标）\n'
        '2. 各阶段详情（阶段名、时长、学习目标、核心知识点、推荐资源、练习任务）\n'
        '3. 里程碑检查点（每阶段完成后应达到的能力）\n'
        '4. 学习建议和注意事项\n'
        '请用中文回答，适合大学生水平。',
  ),
  _SkillDef(
    id: 'learning',
    name: '学习技能',
    subtitle: 'AI 生成学习笔记',
    icon: Icons.menu_book,
    color: Colors.teal,
    description: '输入任意知识点或章节主题，AI 自动生成结构化学习笔记。'
        '包含核心概念解释、代码示例、对比表格、易错点提醒等，'
        '适合课前预习、课后复习和考前速查。',
    features: [
      '自动生成概念解释 + 代码示例',
      '关键知识点对比表格',
      '常见易错点和面试高频问题',
      '思维导图式的知识结构梳理',
    ],
    examples: ['Flutter Widget 生命周期', 'Dart 异步编程 Future/Stream', 'Android Activity 启动模式', '状态管理 Provider vs Riverpod'],
    systemPrompt: '你是移动应用开发课程的教学助手。请根据用户给出的知识点，生成一份结构化学习笔记。'
        '输出格式为 Markdown，包含：\n'
        '1. 知识点概述（2-3句话）\n'
        '2. 核心概念详解（每个概念配代码示例）\n'
        '3. 关键对比表格（如适用）\n'
        '4. 常见易错点（3-5个）\n'
        '5. 练习思考题（2-3题）\n'
        '请用中文回答，代码使用 Dart/Flutter。',
  ),
  _SkillDef(
    id: 'quiz',
    name: '测验技能',
    subtitle: 'AI 自动出题',
    icon: Icons.quiz,
    color: Colors.orange,
    description: '根据指定章节或知识点，AI 自动生成高质量的四选一选择题。'
        '题目涵盖概念理解、代码分析、场景应用等多个层次，'
        '每题附标准答案和详细解析。',
    features: [
      '自动生成四选一选择题（5-10 题）',
      '覆盖记忆、理解、应用三个层次',
      '每题附正确答案和解析说明',
      '可直接导入系统题库使用',
    ],
    examples: ['第1章 移动开发技术体系', '第3章 Flutter 混合开发', 'Dart 面向对象编程', '第5章 HarmonyOS 开发'],
    systemPrompt: '你是移动应用开发课程的出题专家。请根据用户给出的主题，生成选择题。'
        '输出格式为 Markdown，每题包含：\n'
        '- 题目编号和题干\n'
        '- A/B/C/D 四个选项\n'
        '- 正确答案标记\n'
        '- 简短解析（1-2句话）\n'
        '请生成 5 道题，难度从易到难排列，用中文出题。',
  ),
  _SkillDef(
    id: 'repo',
    name: '仓库技能',
    subtitle: 'AI 代码仓库分析',
    icon: Icons.source,
    color: Colors.blueGrey,
    description: '输入项目仓库的基本信息（技术栈、功能描述），AI 自动生成代码分析报告。'
        '包含架构评估、代码质量建议、性能优化方向和重构建议，'
        '帮助教师快速评估学生项目质量。',
    features: [
      '项目架构合理性评估',
      '代码规范和最佳实践检查建议',
      '性能瓶颈分析和优化方向',
      '重构优先级排序和具体建议',
    ],
    examples: ['Flutter 知识图谱 App（sqflite + CustomPainter）', 'Android 天气预报 App（Retrofit + Room）',
      'React Native 电商 App', '微信小程序校园服务平台'],
    systemPrompt: '你是代码审查和架构评估专家。请根据用户描述的项目信息，生成一份代码仓库分析报告。'
        '输出格式为 Markdown，包含：\n'
        '1. 项目概览（技术栈总结）\n'
        '2. 架构评估（分层是否合理、模块划分）\n'
        '3. 代码质量（命名规范、注释、错误处理）\n'
        '4. 性能分析（可能的瓶颈、优化建议）\n'
        '5. 安全检查（数据存储、网络请求、权限管理）\n'
        '6. 改进建议（按优先级排序的 Top 5）\n'
        '请用中文回答，专业但易懂。',
  ),
  _SkillDef(
    id: 'assessment',
    name: '考核技能',
    subtitle: 'AI 生成考核方案',
    icon: Icons.assessment,
    color: Colors.purple,
    description: '根据课程主题和教学目标，AI 自动生成多维度考核方案。'
        '包含考核维度、评分标准、权重分配和评分量表，'
        '支持 OBE 成果导向的达成度评价体系。',
    features: [
      '多维度考核指标设计（5-7 维）',
      '每维度的评分标准和等级描述',
      '权重分配和总分计算方案',
      '支持 OBE 达成度映射',
    ],
    examples: ['移动应用开发期末项目考核', 'Flutter App 开发实践评分', '小组协作项目答辩评分', '课程综合达成度评价方案'],
    systemPrompt: '你是课程考核设计专家，熟悉 OBE（成果导向教育）理念。'
        '请根据用户给出的考核主题，设计一份考核方案。'
        '输出格式为 Markdown，包含：\n'
        '1. 考核概述（目标、形式、总分）\n'
        '2. 考核维度表（维度名、权重%、满分、说明）\n'
        '3. 每维度的评分标准（优秀/良好/合格/不合格的具体描述）\n'
        '4. 评分流程和注意事项\n'
        '5. 与课程目标的达成度映射\n'
        '请用中文回答，适合高校课程使用。',
  ),
  _SkillDef(
    id: 'lab',
    name: '实验技能',
    subtitle: 'AI 设计实验任务',
    icon: Icons.science,
    color: Colors.deepPurple,
    description: '根据课程内容和教学进度，AI 自动设计实验任务方案。'
        '包含实验目标、步骤指导、代码框架、验收标准和扩展挑战，'
        '覆盖从入门到进阶的难度梯度。',
    features: [
      '实验目标与知识点对应',
      '分步骤操作指导（含代码框架）',
      '验收标准和评分要点',
      '扩展挑战任务（选做加分）',
    ],
    examples: ['Flutter 计数器 App 入门实验', 'SQLite 数据库 CRUD 实验', '自定义 Widget 绘制实验', 'RESTful API 对接实验'],
    systemPrompt: '你是移动应用开发课程的实验设计专家。请根据用户给出的主题，设计一个实验任务。'
        '输出格式为 Markdown，包含：\n'
        '1. 实验名称和学时\n'
        '2. 实验目标（3-4条）\n'
        '3. 前置知识要求\n'
        '4. 实验步骤（5-8步，每步含说明和关键代码片段）\n'
        '5. 验收标准（必做项 + 选做加分项）\n'
        '6. 常见问题 FAQ（3-5个）\n'
        '请用中文回答，代码使用 Dart/Flutter。',
  ),
  _SkillDef(
    id: 'works',
    name: '作品技能',
    subtitle: 'AI 生成项目指南',
    icon: Icons.workspace_premium,
    color: Colors.cyan,
    description: '输入项目创意或方向，AI 自动生成完整的项目开发指南。'
        '包含需求分析、技术选型、架构设计、功能模块划分和开发计划，'
        '帮助学生从零开始规划高质量的课程作品。',
    features: [
      '项目需求分析和功能拆解',
      '技术选型建议和对比',
      '架构设计和模块划分',
      '开发里程碑和时间规划',
    ],
    examples: ['校园二手交易 App', '智能学习助手应用', '运动健康管理 App', '旅游攻略分享平台'],
    systemPrompt: '你是移动应用项目开发指导专家。请根据用户给出的项目主题，生成一份项目开发指南。'
        '输出格式为 Markdown，包含：\n'
        '1. 项目概述（一句话描述 + 目标用户 + 核心价值）\n'
        '2. 功能需求（核心功能 + 扩展功能，用表格列出）\n'
        '3. 技术选型（推荐技术栈 + 选择理由）\n'
        '4. 架构设计（分层结构 + 核心模块）\n'
        '5. 数据库设计（核心表结构，3-5张表）\n'
        '6. 开发计划（4周里程碑）\n'
        '7. 答辩展示建议\n'
        '请用中文回答，面向大学生水平。',
  ),
  _SkillDef(
    id: 'achievement',
    name: '达成技能',
    subtitle: 'AI 达成度分析',
    icon: Icons.emoji_events,
    color: Colors.deepOrange,
    description: '输入课程目标和学生表现数据描述，AI 生成 OBE 达成度分析报告。'
        '包含各课程目标的达成情况评估、薄弱环节诊断、'
        '持续改进建议和教学策略优化方案。',
    features: [
      '课程目标达成度量化分析',
      '薄弱环节诊断和原因分析',
      '持续改进措施（CQI）建议',
      '教学策略优化方案',
    ],
    examples: ['移动应用开发课程达成度分析', '程序设计基础课程改进报告', 'OBE 课程目标与毕业要求映射分析', '实践教学环节达成度评价'],
    systemPrompt: '你是 OBE（成果导向教育）达成度分析专家。'
        '请根据用户给出的课程信息，生成一份达成度分析报告。'
        '输出格式为 Markdown，包含：\n'
        '1. 课程目标梳理（3-5个课程目标）\n'
        '2. 达成度评价方法（考核方式与目标对应关系矩阵）\n'
        '3. 达成度计算模板（公式 + 示例数据）\n'
        '4. 薄弱环节诊断（可能的问题 + 原因分析）\n'
        '5. 持续改进措施（CQI，3-5条具体建议）\n'
        '6. 教学优化方案（下一轮教学调整建议）\n'
        '请用中文回答，符合工程教育认证标准。',
  ),
];

_SkillDef _getSkill(String id) =>
    _skills.firstWhere((s) => s.id == id, orElse: () => _skills.first);

// ═══════════════════════════════════════════════════════════════════════════════
// 技能中心页 — 展示所有 9 个 AI 技能
// ═══════════════════════════════════════════════════════════════════════════════

class SkillsHubPage extends StatefulWidget {
  const SkillsHubPage({super.key});

  @override
  State<SkillsHubPage> createState() => _SkillsHubPageState();
}

class _SkillsHubPageState extends State<SkillsHubPage> {
  final _skillDao = SkillDao();
  Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await _skillDao.getResultCounts();
      if (mounted) setState(() => _counts = counts);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final gradient = AppGradientTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AI 技能中心')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部渐变卡片
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: gradient.linearGradient,
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                        SizedBox(width: 10),
                        Text('AI 教学技能',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '利用 AI 为每个教学模块生成新内容，涵盖图谱构建、路径规划、'
                      '自动出题、实验设计等 9 大技能，助力智慧教学。',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 技能网格
            const Text('全部技能',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth > 900
                    ? 4
                    : constraints.maxWidth > 600
                        ? 3
                        : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: 1.05,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _skills.length,
                  itemBuilder: (context, index) {
                    final skill = _skills[index];
                    final count = _counts[skill.id] ?? 0;
                    return _buildSkillCard(skill, count);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillCard(_SkillDef skill, int count) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AiSkillPage(skillId: skill.id)),
          );
          _loadCounts();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: skill.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(skill.icon, color: skill.color, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                skill.name,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: skill.color),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                skill.subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                overflow: TextOverflow.ellipsis,
              ),
              if (count > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: skill.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count 条',
                      style: TextStyle(fontSize: 10, color: skill.color)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI 技能详情页 — 3 Tab（说明 / 使用 / 下载）
// ═══════════════════════════════════════════════════════════════════════════════

class AiSkillPage extends StatefulWidget {
  final String skillId;
  const AiSkillPage({super.key, required this.skillId});

  @override
  State<AiSkillPage> createState() => _AiSkillPageState();
}

class _AiSkillPageState extends State<AiSkillPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final _SkillDef _skill;

  final _aiService = AiService();
  final _skillDao = SkillDao();
  final _inputController = TextEditingController();

  bool _loading = false;
  String? _result;
  List<Map<String, dynamic>> _savedResults = [];

  @override
  void initState() {
    super.initState();
    _skill = _getSkill(widget.skillId);
    _tabController = TabController(length: 3, vsync: this);
    _loadSavedResults();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedResults() async {
    try {
      final results = await _skillDao.getResults(widget.skillId);
      if (mounted) setState(() => _savedResults = results);
    } catch (_) {}
  }

  Future<void> _generate() async {
    final topic = _inputController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入主题或描述')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final reply = await _aiService.chat(
        [
          {'role': 'user', 'content': topic}
        ],
        systemPrompt: _skill.systemPrompt,
      );
      if (mounted) setState(() => _result = reply);
    } catch (e) {
      if (mounted) {
        setState(() => _result = '❌ 生成失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveResult() async {
    if (_result == null || _result!.startsWith('❌')) return;
    final topic = _inputController.text.trim();
    try {
      await _skillDao.saveResult(
        skillId: widget.skillId,
        title: topic.length > 50 ? '${topic.substring(0, 50)}...' : topic,
        content: _result!,
      );
      await _loadSavedResults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到下载列表')),
        );
        _tabController.animateTo(2); // 切换到下载 Tab
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  Future<void> _deleteResult(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条生成记录吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _skillDao.deleteResult(id);
      await _loadSavedResults();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(_skill.name),
        bottom: TabBar(
          controller: _tabController,
          labelColor: primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: '说明'),
            Tab(icon: Icon(Icons.play_arrow), text: '使用'),
            Tab(icon: Icon(Icons.download), text: '下载'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDescriptionTab(),
          _buildUsageTab(),
          _buildDownloadTab(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 1: 说明
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDescriptionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 技能头部
          Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    _skill.color,
                    _skill.color.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child:
                        Icon(_skill.icon, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(_skill.name,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(_skill.subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white70)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 技能描述
          _sectionTitle('技能描述'),
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_skill.description,
                  style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
          ),
          const SizedBox(height: 16),

          // 功能特点
          _sectionTitle('功能特点'),
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _skill.features.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle,
                            color: _skill.color, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(f,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 示例主题
          _sectionTitle('示例主题'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _skill.examples.map((e) {
              return ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 12)),
                avatar: Icon(Icons.lightbulb_outline,
                    size: 16, color: _skill.color),
                onPressed: () {
                  _inputController.text = e;
                  _tabController.animateTo(1); // 切换到使用 Tab
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // 快速开始按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始使用'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _skill.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 2: 使用
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildUsageTab() {
    return Column(
      children: [
        // 输入区域
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('输入主题',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _skill.color)),
              const SizedBox(height: 8),
              TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: '例如：${_skill.examples.first}',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: _inputController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _inputController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                maxLines: 2,
                minLines: 1,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              // 快捷示例 Chips
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _skill.examples.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          _inputController.text = e;
                          setState(() {});
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _skill.color.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(e,
                              style: TextStyle(
                                  fontSize: 11, color: _skill.color)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _generate,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_loading ? '正在生成...' : 'AI 生成'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _skill.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 结果区域
        Expanded(
          child: _result == null && !_loading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_skill.icon,
                          size: 64,
                          color: _skill.color.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text('输入主题，点击 AI 生成',
                          style: TextStyle(color: Colors.grey[400])),
                    ],
                  ),
                )
              : _loading && _result == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: _skill.color),
                          const SizedBox(height: 16),
                          Text('AI 正在生成中...',
                              style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          child: Card(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border(
                                  left: BorderSide(
                                      color: _skill.color, width: 4),
                                ),
                              ),
                              child: _buildMarkdownContent(
                                _result ?? '',
                              ),
                            ),
                          ),
                        ),
                        // 底部操作栏
                        if (_result != null && !_result!.startsWith('❌'))
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _copyToClipboard(_result!),
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('复制'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[700],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _saveResult,
                                    icon: const Icon(Icons.save, size: 18),
                                    label: const Text('保存'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _skill.color,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab 3: 下载
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDownloadTab() {
    if (_savedResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done,
                size: 64, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text('暂无保存的生成结果',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            Text('在「使用」页面生成内容后点击保存',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 统计栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: _skill.color.withValues(alpha: 0.05),
          child: Row(
            children: [
              Icon(Icons.folder, color: _skill.color, size: 20),
              const SizedBox(width: 8),
              Text('共 ${_savedResults.length} 条生成记录',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _skill.color)),
            ],
          ),
        ),
        // 结果列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSavedResults,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _savedResults.length,
              itemBuilder: (context, index) {
                final item = _savedResults[index];
                final title = item['title'] as String? ?? '未命名';
                final content = item['content'] as String? ?? '';
                final createdAt = item['created_at'] as String? ?? '';
                final dateStr = createdAt.length >= 10
                    ? createdAt.substring(0, 10)
                    : createdAt;
                final id = item['id'] as int;
                final previewLen =
                    content.length > 80 ? 80 : content.length;

                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => _showResultDetail(title, content),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_skill.icon,
                                  size: 18, color: _skill.color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(title,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Text(dateStr,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400])),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            content.substring(0, previewLen) +
                                (content.length > 80 ? '...' : ''),
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                height: 1.4),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _miniButton(
                                Icons.copy,
                                '复制',
                                () => _copyToClipboard(content),
                              ),
                              const SizedBox(width: 8),
                              _miniButton(
                                Icons.download,
                                '下载',
                                () => _downloadAsFile(title, content),
                              ),
                              const SizedBox(width: 8),
                              _miniButton(
                                Icons.visibility,
                                '查看',
                                () => _showResultDetail(title, content),
                              ),
                              const SizedBox(width: 8),
                              _miniButton(
                                Icons.delete_outline,
                                '删除',
                                () => _deleteResult(id),
                                color: Colors.red,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: _skill.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// 预处理 Markdown：将 PlantUML 代码块转换为 Kroki 图片 URL
  String _preprocessMarkdown(String content) {
    final pumlRegex = RegExp(
      r'```(?:plantuml|puml|uml)\s*\n([\s\S]*?)```',
      multiLine: true,
    );
    final pumlService = PlantUmlService();
    return content.replaceAllMapped(pumlRegex, (match) {
      final pumlCode = match.group(1)!.trim();
      // 确保有 @startuml / @enduml 包裹
      final wrapped = pumlCode.contains('@startuml')
          ? pumlCode
          : '@startuml\n$pumlCode\n@enduml';
      try {
        final url = pumlService.getKrokiUrl(wrapped);
        return '\n![UML 模型图]($url)\n';
      } catch (_) {
        return '\n```\n$pumlCode\n```\n';
      }
    });
  }

  /// 构建 Markdown 渲染 Widget（支持 PlantUML 图片）
  Widget _buildMarkdownContent(String content) {
    final processed = _preprocessMarkdown(content);
    return MarkdownBody(
      data: processed,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 14, height: 1.7),
        h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.5),
        h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.5),
        h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
        h4: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
        strong: const TextStyle(fontWeight: FontWeight.bold),
        em: const TextStyle(fontStyle: FontStyle.italic),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Colors.deepPurple[700],
          backgroundColor: Colors.deepPurple.withValues(alpha: 0.06),
        ),
        codeblockPadding: const EdgeInsets.all(14),
        codeblockDecoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        blockquoteDecoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.04),
          border: const Border(
            left: BorderSide(color: Color(0xFF667eea), width: 4),
          ),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        listBullet: TextStyle(fontSize: 14, color: _skill.color),
        tableHead: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        tableBody: const TextStyle(fontSize: 13),
        tableBorder: TableBorder.all(color: Colors.grey.withValues(alpha: 0.3)),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 1),
          ),
        ),
        blockSpacing: 10,
      ),
    );
  }

  /// 下载内容为 .md 文件
  Future<void> _downloadAsFile(String title, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = '${safeTitle.length > 60 ? safeTitle.substring(0, 60) : safeTitle}.md';
      final skillDir = Directory('${dir.path}/skill_exports');
      if (!await skillDir.exists()) {
        await skillDir.create(recursive: true);
      }
      final file = File('${skillDir.path}/$fileName');
      await file.writeAsString(content, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到: ${file.path}'),
            action: SnackBarAction(
              label: '打开目录',
              onPressed: () {
                // 尝试打开文件所在目录
                try {
                  if (Platform.isWindows) {
                    Process.run('explorer', [skillDir.path]);
                  } else if (Platform.isMacOS) {
                    Process.run('open', [skillDir.path]);
                  }
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Widget _miniButton(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? _skill.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: c.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }

  void _showResultDetail(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            // 把手
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(_skill.icon, color: _skill.color, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(content),
                    tooltip: '复制全文',
                  ),
                  IconButton(
                    icon: const Icon(Icons.download, size: 20),
                    onPressed: () => _downloadAsFile(title, content),
                    tooltip: '下载为文件',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 内容
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: _buildMarkdownContent(content),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
