import '../data/models/skill_def_model.dart';
import 'skill_registry.dart';

void initializeSkills() {
  final registry = SkillRegistry.instance;
  final skills = _builtinSkills();
  registry.registerAll(skills);
}

List<SkillDef> _builtinSkills() => [
      SkillDef(
        id: 'graph',
        name: '图谱技能',
        subtitle: 'AI 生成知识图谱',
        iconName: 'account_tree',
        colorHex: 'FF2196F3',
        description: '利用 AI 根据指定主题自动生成知识图谱的核心概念和关系结构。'
            '系统会分析主题领域，提取关键概念节点，建立概念间的层次和关联关系，'
            '输出结构化的知识图谱方案，可直接用于教学设计和课程规划。',
        features: [
          '自动提取主题核心概念（8-15 个节点）',
          '建立概念间层次关系（包含、依赖、关联）',
          '标注概念难度等级和学习顺序',
          '输出结构化 JSON 可导入系统',
        ],
        examples: [
          '数据结构与算法基础',
          '软件工程核心概念',
          '数据库设计原理',
          '计算机网络基础',
        ],
        systemPrompt: '你是知识图谱设计专家。请根据用户给出的主题，生成一份知识图谱方案。'
            '输出格式为 Markdown，包含：\n'
            '1. 核心概念列表（8-15个），每个注明难度（初级/中级/高级）\n'
            '2. 概念间关系表（source → target，关系类型：包含/依赖/关联/扩展）\n'
            '3. 推荐学习顺序\n'
            '4. 图谱应用建议\n'
            '请用中文回答，结构清晰。',
        usageSteps: [
          '进入 AI 技能中心，选择"图谱技能"',
          '在"使用"页面输入知识主题（如"数据结构与算法"）',
          'AI 自动分析主题，生成概念节点和关系结构',
          '查看生成结果，可复制或保存为 Markdown 文件',
          '将图谱方案导入系统知识图谱模块使用',
        ],
        keywords: ['图谱', '知识图谱', '概念图', '概念关系', '节点'],
        priority: 6,
        classicCases: [
          SkillCase(title: '数据结构与算法体系', userInput: '数据结构与算法基础',
              resultSummary: '生成 12 个核心概念节点，建立包含、依赖、关联三类关系 18 条。'),
          SkillCase(title: '软件工程核心概念', userInput: '软件工程核心概念图谱',
              resultSummary: '生成需求分析/设计/编码/测试/维护五大核心节点共 15 个。'),
        ],
      ),
      SkillDef(
        id: 'path',
        name: '路径技能',
        subtitle: 'AI 规划学习路径',
        iconName: 'route',
        colorHex: 'FF3F51B5',
        description: '根据学习目标和当前水平，AI 智能规划个性化学习路径。'
            '系统会分析知识依赖关系，设计从基础到进阶的阶梯式学习计划，'
            '包含每个阶段的学习目标、推荐资源和预计时长。',
        features: [
          '基于目标逆向设计学习路线',
          '标注每阶段的前置知识和学习时长',
          '推荐配套学习资源和练习项目',
          '支持不同基础水平的差异化路径',
        ],
        examples: ['零基础掌握核心专业知识', '跨领域知识拓展学习', '基础到进阶的能力提升'],
        systemPrompt: '你是学习规划专家。请根据用户的学习目标，设计一份详细的学习路径。'
            '输出格式为 Markdown，包含：\n'
            '1. 路径概览（总时长、阶段数、目标）\n'
            '2. 各阶段详情（阶段名、时长、学习目标、核心知识点、推荐资源、练习任务）\n'
            '3. 里程碑检查点\n'
            '4. 学习建议和注意事项',
        usageSteps: [
          '进入 AI 技能中心，选择"路径技能"',
          '输入学习目标和当前水平',
          'AI 分析知识依赖，设计阶梯式学习路径',
          '查看各阶段目标、时长和推荐资源',
          '保存路径方案，按计划执行学习',
        ],
        keywords: ['路径', '学习路径', '学习计划', '路线', '规划'],
        priority: 5,
        classicCases: [
          SkillCase(title: '零基础入门学习路径', userInput: '零基础掌握核心专业知识',
              resultSummary: '规划 12 周学习路径，分 4 阶段：基础入门→核心知识→进阶提升→综合应用，每阶段含学习目标和练习。'),
          SkillCase(title: '跨领域拓展路径', userInput: '跨领域知识拓展学习',
              resultSummary: '规划 8 周拓展路径，涵盖核心理论、实践方法、综合应用等模块，适合有基础的学习者。'),
        ],
      ),
      SkillDef(
        id: 'learning',
        name: '学习技能',
        subtitle: 'AI 生成学习笔记',
        iconName: 'menu_book',
        colorHex: 'FF009688',
        description: '输入任意知识点或章节主题，AI 自动生成结构化学习笔记。'
            '包含核心概念解释、示例说明、对比表格、易错点提醒等，'
            '适合课前预习、课后复习和考前速查。',
        features: [
          '自动生成概念解释 + 示例说明',
          '关键知识点对比表格',
          '常见易错点和面试高频问题',
          '思维导图式的知识结构梳理',
        ],
        examples: ['核心概念的生命周期', '异步编程基础概念', '组件启动与管理模式'],
        systemPrompt: '你是课程教学助手。请根据用户给出的知识点，生成一份结构化学习笔记。'
            '输出格式为 Markdown，包含：\n'
            '1. 知识点概述\n2. 核心概念详解\n3. 关键对比表格\n4. 常见易错点\n5. 练习思考题',
        usageSteps: [
          '进入 AI 技能中心，选择"学习技能"',
          '输入要学习的知识点',
          'AI 生成结构化学习笔记',
          '查看对比表格、易错点和练习题',
          '保存笔记用于课前预习或考前复习',
        ],
        keywords: ['学习', '笔记', '知识点', '预习', '复习'],
        priority: 5,
        classicCases: [
          SkillCase(title: '核心概念生命周期笔记', userInput: '核心概念的生命周期',
              resultSummary: '生成结构化笔记：创建→执行→销毁流程详解、5 个常见易错点、3 道练习思考题。'),
          SkillCase(title: '异步编程基础笔记', userInput: '异步编程基础概念',
              resultSummary: '生成同步/异步/并发对比笔记，含回调机制、事件驱动处理等关键概念对比表格。'),
        ],
      ),
      SkillDef(
        id: 'quiz',
        name: '测验技能',
        subtitle: 'AI 自动出题',
        iconName: 'quiz',
        colorHex: 'FFFF9800',
        description: '根据指定章节或知识点，AI 自动生成高质量的四选一选择题。'
            '题目涵盖概念理解、案例分析、场景应用等多个层次，每题附标准答案和详细解析。',
        features: [
          '自动生成四选一选择题（5-10 题）',
          '覆盖记忆、理解、应用三个层次',
          '每题附正确答案和解析说明',
          '可直接导入系统题库使用',
        ],
        examples: ['第1章 基础知识', '第3章 核心方法', '概念理解与辨析'],
        systemPrompt: '你是课程出题专家。请根据用户给出的主题，生成选择题。'
            '输出格式为 Markdown，每题包含：\n'
            '- 题目编号和题干\n- A/B/C/D 四个选项\n- 正确答案标记\n- 简短解析\n'
            '请生成 5 道题，难度从易到难排列。',
        usageSteps: [
          '进入 AI 技能中心，选择"测验技能"',
          '输入出题范围',
          'AI 自动生成 5 道四选一选择题',
          '每题附正确答案和解析说明',
          '可保存题目，后续导入系统题库',
        ],
        keywords: ['测验', '出题', '选择题', '题目', '考试', '测试'],
        priority: 6,
        classicCases: [
          SkillCase(title: '章节知识测验', userInput: '第3章 核心方法',
              resultSummary: '生成 5 道选择题，覆盖原理理解、概念辨析、场景应用等难度梯度，每题含正确答案和解析。'),
          SkillCase(title: '概念辨析测验', userInput: '概念理解与辨析',
              resultSummary: '生成 5 道选择题，考查易混概念的区分与理解，适合阶段性复习自测。'),
        ],
      ),
      SkillDef(
        id: 'repo',
        name: '仓库技能',
        subtitle: 'AI 代码仓库分析',
        iconName: 'source',
        colorHex: 'FF546E7A',
        description: '输入项目仓库的基本信息（技术栈、功能描述），AI 自动生成代码分析报告。'
            '包含架构评估、代码质量建议、性能优化方向和重构建议。',
        features: [
          '项目架构合理性评估',
          '代码规范和最佳实践检查建议',
          '性能瓶颈分析和优化方向',
          '重构优先级排序和具体建议',
        ],
        examples: ['课程项目（含数据库和自定义组件）', '信息管理应用', '跨平台 Web 应用项目'],
        systemPrompt: '你是代码审查和架构评估专家。请根据用户描述的项目信息，生成一份代码仓库分析报告。'
            '输出格式为 Markdown，包含：\n'
            '1. 项目概览\n2. 架构评估\n3. 代码质量\n4. 性能分析\n5. 安全检查\n6. 改进建议',
        usageSteps: [
          '进入 AI 技能中心，选择"仓库技能"',
          '输入项目描述',
          'AI 生成代码仓库分析报告',
          '查看架构评估、代码质量和优化建议',
          '保存报告用于项目改进或教学评估',
        ],
        keywords: ['仓库', '代码', '分析', '审查', 'Git'],
        priority: 4,
        classicCases: [
          SkillCase(title: '课程项目仓库分析', userInput: '课程项目（含数据库和自定义组件）',
              resultSummary: '生成架构评估报告：5 层分层合理，列出代码质量建议 3 条、性能优化方向 2 条、Top 5 改进建议。'),
        ],
      ),
      SkillDef(
        id: 'assessment',
        name: '考核技能',
        subtitle: 'AI 生成考核方案',
        iconName: 'assessment',
        colorHex: 'FF9C27B0',
        description: '根据课程主题和教学目标，AI 自动生成多维度考核方案。'
            '包含考核维度、评分标准、权重分配和评分量表。',
        features: [
          '多维度考核指标设计（5-7 维）',
          '每维度的评分标准和等级描述',
          '权重分配和总分计算方案',
          '支持 OBE 达成度映射',
        ],
        examples: ['课程期末项目考核方案设计', '项目实践评分', '小组协作项目答辩评分'],
        systemPrompt: '你是课程考核设计专家，熟悉 OBE 理念。'
            '请根据用户给出的考核主题，设计一份考核方案。'
            '输出格式为 Markdown，包含：\n'
            '1. 考核概述\n2. 考核维度表\n3. 每维度的评分标准\n4. 评分流程\n5. 达成度映射',
        usageSteps: [
          '进入 AI 技能中心，选择"考核技能"',
          '输入考核主题和教学目标',
          'AI 设计多维度考核方案',
          '查看评分标准、权重分配和等级描述',
          '保存方案用于课程考核实施',
        ],
        keywords: ['考核', '评分', '评价', '评估', 'OBE'],
        priority: 5,
        classicCases: [
          SkillCase(title: '期末项目考核方案', userInput: '课程期末项目考核方案设计',
              resultSummary: '设计 6 维考核方案：功能完整性(25%)、方案设计(20%)、技术实现(15%)、创新性(15%)、文档规范(15%)、答辩表现(10%)。'),
          SkillCase(title: '小组协作答辩评分', userInput: '小组协作项目答辩评分',
              resultSummary: '设计 5 维答辩评分表：内容完整性(25%)、创新性(20%)、团队协作(20%)、表达清晰(20%)、问答表现(15%)。'),
        ],
      ),
      SkillDef(
        id: 'lab',
        name: '实践技能',
        subtitle: 'AI 设计实践任务',
        iconName: 'science',
        colorHex: 'FF673AB7',
        description: '根据课程内容和教学进度，AI 自动设计实践任务方案。'
            '包含实践目标、步骤指导、代码或操作框架、验收标准和扩展挑战。',
        features: [
          '实践目标与知识点对应',
          '分步骤操作指导',
          '验收标准和评分要点',
          '扩展挑战任务',
        ],
        examples: ['基础功能实现入门实践', '数据存储与查询实践', '自定义模块开发实践'],
        systemPrompt: '你是课程实践任务设计专家。请根据用户给出的主题，设计一个实践任务。'
            '输出格式为 Markdown，包含：\n'
            '1. 实践任务名称和学时\n2. 实践目标\n3. 前置知识要求\n'
            '4. 实践步骤\n5. 验收标准\n6. 常见问题 FAQ',
        usageSteps: [
          '进入 AI 技能中心，选择"实践技能"',
          '输入实践主题',
          'AI 设计完整实践任务方案',
          '查看实践步骤和验收标准',
          '保存方案用于课程实践教学',
        ],
        keywords: ['实践', '实验', '任务', '操作', '练习'],
        priority: 5,
        classicCases: [
          SkillCase(title: '数据存储与查询实践', userInput: '数据存储与查询实践',
              resultSummary: '设计 4 学时实践任务：含环境说明、核心步骤 4 步、验收标准 5 项、扩展挑战 2 项。'),
          SkillCase(title: '功能实现入门实践', userInput: '基础功能实现入门实践',
              resultSummary: '设计 2 学时入门实践：前置知识要求、分步操作指导 5 步、必做验收项 3 项、选做加分项 2 项。'),
        ],
      ),
      SkillDef(
        id: 'works',
        name: '作品技能',
        subtitle: 'AI 生成项目指南',
        iconName: 'workspace_premium',
        colorHex: 'FF00BCD4',
        description: '输入项目创意或方向，AI 自动生成完整的项目开发指南。'
            '包含需求分析、技术选型、架构设计、功能模块划分和开发计划。',
        features: [
          '项目需求分析和功能拆解',
          '技术选型建议和对比',
          '架构设计和模块划分',
          '开发里程碑和时间规划',
        ],
        examples: ['校园二手交易平台设计', '智能学习助手方案', '运动健康管理工具'],
        systemPrompt: '你是课程项目开发指导专家。请根据用户给出的项目主题，生成一份项目开发指南。'
            '输出格式为 Markdown，包含：\n'
            '1. 项目概述\n2. 功能需求\n3. 技术选型\n4. 架构设计\n5. 数据库设计\n6. 开发计划\n7. 答辩建议',
        usageSteps: [
          '进入 AI 技能中心，选择"作品技能"',
          '输入项目创意或方向',
          'AI 生成完整项目开发指南',
          '查看需求分析、技术选型和开发计划',
          '保存指南，按里程碑推进开发',
        ],
        keywords: ['作品', '项目', '开发', '指南', '设计'],
        priority: 5,
        classicCases: [
          SkillCase(title: '校园二手交易平台', userInput: '校园二手交易平台设计',
              resultSummary: '生成完整开发指南：6 个核心功能模块、技术选型建议、核心数据结构设计、4 周开发里程碑计划。'),
          SkillCase(title: '智能学习助手', userInput: '智能学习助手方案',
              resultSummary: '生成项目方案：包含需求分析、功能模块划分、技术架构设计、开发计划与验收标准。'),
        ],
      ),
      SkillDef(
        id: 'achievement',
        name: '达成技能',
        subtitle: '达成审核与归档闭环',
        iconName: 'emoji_events',
        colorHex: 'FFFF5722',
        description: '面向当前课程生成 OBE 达成度分析、材料审核和归档闭环建议。'
            '联动大纲、进度表、课程表、成绩、达成报告和结课材料。',
        features: [
          '课程目标达成度量化分析',
          '期初、期中、期末、结课材料一致性审核',
          '薄弱环节诊断和原因分析',
          '持续改进措施（CQI）建议',
        ],
        examples: ['达成材料一键审核', '课程达成度分析', 'OBE 课程目标与毕业要求映射分析'],
        systemPrompt: '你是 OBE 达成度分析专家。'
            '请根据当前课程信息和本地达成归档审核上下文，生成面向教师的达成闭环报告。'
            '输出格式为 Markdown，包含：\n'
            '1. 课程目标与考核依据梳理\n2. 材料状态审核\n'
            '3. 达成度评价方法\n4. 缺口与风险清单\n5. 操作建议\n6. CQI 改进措施',
        usageSteps: [
          '进入 AI 技能中心，选择"达成技能"',
          '输入"达成材料一键审核"或具体课程问题',
          'AI 读取当前课程达成和归档上下文',
          '查看材料缺口、审核风险和达成度结果',
          '保存报告用于打印、归档和 CQI',
        ],
        keywords: ['达成', 'OBE', '审核', '归档', 'CQI', '达成度'],
        priority: 6,
        classicCases: [
          SkillCase(title: '课程达成度审核', userInput: '达成材料一键审核',
              resultSummary: '生成当前课程达成材料审核报告：含大纲、进度表、课程表、成绩、达成报告、结课归档材料状态和 CQI 改进建议。'),
        ],
      ),
      SkillDef(
        id: 'archive',
        name: '归档技能',
        subtitle: 'AI 生成教学归档材料',
        iconName: 'archive',
        colorHex: 'FF795548',
        description: '根据课程类型和教学阶段，AI 自动生成规范的教学归档文档。'
            '覆盖课程总结、试卷审核表、教学过程记录等常见归档类型。',
        features: [
          '覆盖期初/期中/期末全阶段归档',
          '支持考试/考查两种课程类型',
          '自动填充课程信息和教学数据',
          '输出结构化的 Markdown 文档',
        ],
        examples: ['期末课程总结报告', '试卷命题审核表', '教学过程记录表'],
        systemPrompt: '你是一位经验丰富的教学归档专家，熟悉课程教学文档的规范与格式。'
            '请根据用户需求生成相应文档内容，使用 Markdown 格式输出。',
        usageSteps: [
          '进入 AI 技能中心，选择"归档技能"',
          '输入归档类型和教学阶段',
          'AI 自动生成规范的教学归档文档',
          '预览并确认文档内容完整准确',
          '保存 Markdown 文档，用于打印或归档',
        ],
        keywords: ['归档', '档案', '总结', '教学文档', '结课'],
        priority: 4,
        classicCases: [
          SkillCase(title: '期末课程总结', userInput: '期末课程总结报告',
              resultSummary: '生成包含教学概况、成绩分析、经验反思的完整课程总结报告，含数据表格和持续改进建议。'),
          SkillCase(title: '试卷审核表', userInput: '试卷命题审核表',
              resultSummary: '生成包含命题质量评估、难度分布分析、审核意见的试卷审核表，适用于考试课程归档。'),
        ],
      ),
    ];
