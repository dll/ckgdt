part of '../assessment_page.dart';

class _AssessmentReportTab extends StatefulWidget {
  final AuthService authService;
  const _AssessmentReportTab({required this.authService});

  @override
  State<_AssessmentReportTab> createState() => _AssessmentReportTabState();
}

class _AssessmentReportTabState extends State<_AssessmentReportTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  final _dao = AssessmentDao();
  List<Map<String, dynamic>> _submissions = [];
  bool _loading = true;
  String? _currentUserId;

  bool get _isStudent =>
      !widget.authService.isTeacher && !widget.authService.isAdmin;

  /// 验证考核报告文件名：必须为 学号+姓名+报告类型.pdf
  String? _validateReportFileName(String fileName, String reportType) {
    final userId = _currentUserId ?? '';
    final realName = widget.authService.currentUser?.realName ?? '';
    if (userId.isEmpty || realName.isEmpty) {
      return '提交失败：无法获取当前用户信息，请重新登录';
    }

    // 去掉扩展名
    final baseName = fileName.endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    // 检查非法后缀：(1) (2) 1 2 new copy 副本 - 复制 等
    if (RegExp(r'[\(\（]\d+[\)\）]$').hasMatch(baseName) ||
        RegExp(r'[_\-\s]?\d+$').hasMatch(baseName) &&
            !baseName.endsWith(reportType) ||
        RegExp(r'(new|copy|副本|复制|备份)', caseSensitive: false)
            .hasMatch(baseName)) {
      return '提交失败：文件名不规范，不允许包含(1)、new、copy、副本等后缀\n'
          '正确格式：$userId$realName$reportType.pdf';
    }

    // 检查学号是否匹配当前登录用户
    if (!baseName.startsWith(userId)) {
      return '提交失败：文件名中的学号与当前登录用户不匹配\n'
          '正确格式：$userId$realName$reportType.pdf';
    }

    // 检查是否包含姓名
    if (!baseName.contains(realName)) {
      return '提交失败：文件名中未包含姓名"$realName"\n'
          '正确格式：$userId$realName$reportType.pdf';
    }

    // 检查是否包含报告类型
    if (!baseName.contains(reportType)) {
      return '提交失败：文件名中未包含报告类型"$reportType"\n'
          '正确格式：$userId$realName$reportType.pdf';
    }

    // 严格匹配：学号+姓名+报告类型
    final expected = '$userId$realName$reportType';
    if (baseName != expected) {
      return '提交失败：文件命名不规范\n'
          '正确格式：$userId$realName$reportType.pdf';
    }

    return null; // 验证通过
  }

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _currentUserId = widget.authService.getCurrentUserId();
      await _loadSubmissions();
    } catch (e, st) {
      swallowDebug(e, tag: 'AssessmentReportTab.init', stack: st);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSubmissions() async {
    try {
      final queryUserId = _isStudent ? _currentUserId : null;
      final subs = await _dao.getSubmittedReports(userId: queryUserId);
      if (mounted) {
        setState(() {
          _submissions = subs;
        });
      }
    } catch (e, st) {
      swallowDebug(e, tag: 'AssessmentReportTab.loadSubs', stack: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final indigo = Colors.indigo;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: indigo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: indigo.withValues(alpha: 0.10)),
          ),
          child: TabBar(
            controller: _subTabController,
            labelColor: indigo[700],
            unselectedLabelColor: Colors.grey,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: indigo.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            tabs: const [
              Tab(icon: Icon(Icons.timeline, size: 18), text: '过程报告'),
              Tab(icon: Icon(Icons.assignment, size: 18), text: '最终报告'),
              Tab(icon: Icon(Icons.print, size: 18), text: '审核打印'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _buildProcessReports(),
              _buildAssessmentReports(),
              _buildSubmissionPanel(),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab1: 4周过程性报告（时间线 + 每周要求）
  // ══════════════════════════════════════════════════════════
  Widget _buildProcessReports() {
    final weeks = [
      {
        'week': '第一周',
        'title': '项目启动',
        'period': '第1-3天',
        'color': Colors.blue,
        'icon': Icons.rocket_launch,
        'tasks': [
          '组建6人团队，确定技术栈分工',
          '完成项目选题与需求分析',
          '设计系统架构（前端/后端/数据库）',
          '搭建各平台开发环境',
          '建立Git仓库，制定分支策略',
          '确定编码规范与协作流程',
        ],
        'deliverables': [
          '团队信息表（成员/技术栈/职责）',
          '需求分析文档（功能需求 + 非功能需求）',
          '系统架构设计图',
          '技术选型对比分析',
          '开发计划与里程碑',
        ],
        'focus': '重点: 分工明确、架构合理、环境就绪',
      },
      {
        'week': '第二周',
        'title': '核心开发',
        'period': '第4-7天',
        'color': Colors.green,
        'icon': Icons.code,
        'tasks': [
          '各平台基础功能开发（UI框架搭建）',
          '实现核心业务逻辑',
          '完成数据库设计与接口开发',
          '各平台独立功能测试',
          'AI功能集成（GLM/DeepSeek/讯飞）',
          '代码审查与质量控制',
        ],
        'deliverables': [
          '各平台开发进度表（功能数/完成率/代码行数）',
          '核心功能截图/录屏',
          '遇到的技术难点与解决方案',
          '代码质量报告（覆盖率/规范检查）',
        ],
        'focus': '重点: 功能实现、代码质量、进度把控',
      },
      {
        'week': '第三周',
        'title': '系统整合',
        'period': '第8-12天',
        'color': Colors.orange,
        'icon': Icons.merge_type,
        'tasks': [
          '跨平台数据同步架构实现',
          'API统一对接与联调',
          '性能优化（启动/渲染/网络/内存）',
          '跨平台UI一致性调整',
          '集成测试与Bug修复',
          '用户体验优化',
        ],
        'deliverables': [
          '整合测试报告（同步成功率/API响应/一致性）',
          '性能测试数据对比表',
          '已修复Bug列表',
          '跨平台兼容性矩阵',
        ],
        'focus': '重点: 数据同步、性能指标、整合质量',
      },
      {
        'week': '第四周',
        'title': '测试交付',
        'period': '第13-15天',
        'color': Colors.purple,
        'icon': Icons.verified,
        'tasks': [
          '全面功能测试（回归测试矩阵）',
          '性能验收测试',
          '安全审计与漏洞修复',
          '编写部署文档与用户手册',
          '准备答辩材料（PPT/视频/录音）',
          '最终版本发布与打包',
        ],
        'deliverables': [
          '功能测试矩阵（通过率/覆盖率）',
          '性能验收数据',
          '部署文档与安装包',
          '答辩PPT/视频演示',
          '项目总结与反思',
        ],
        'focus': '重点: 测试充分、文档完整、答辩准备',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 总览卡片
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  Colors.indigo.withValues(alpha: 0.08),
                  Colors.purple.withValues(alpha: 0.04),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 20, color: Colors.indigo[700]),
                    const SizedBox(width: 8),
                    Text('四周考核流程',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[700])),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '15天完成项目开发与考核。每周提交过程性报告，记录进展。四份过程报告整合为最终考核大作业的支撑材料。',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600], height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 四周时间线
        ...weeks.asMap().entries.map((entry) {
          final i = entry.key;
          final w = entry.value;
          return _buildWeekCard(w, isLast: i == 3);
        }),
      ],
    );
  }

  Widget _buildWeekCard(Map<String, dynamic> w, {bool isLast = false}) {
    final color = w['color'] as Color;
    final tasks = w['tasks'] as List<String>;
    final deliverables = w['deliverables'] as List<String>;
    final focus = w['focus'] as String;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 时间线指示器
        SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(w['icon'] as IconData, size: 14, color: Colors.white),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 200,
                  color: color.withValues(alpha: 0.3),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 卡片
        Expanded(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: color, width: 3),
                  ),
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${w['week']}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: color)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${w['title']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  subtitle: Text('${w['period']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  children: [
                    // 主要任务
                    _reportSubHeader('主要任务', Icons.checklist, color),
                    const SizedBox(height: 4),
                    ...tasks.map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 14,
                                  color: color.withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(t,
                                      style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        )),
                    const SizedBox(height: 10),
                    // 交付物
                    _reportSubHeader('交付物', Icons.inventory, Colors.orange),
                    const SizedBox(height: 4),
                    ...deliverables.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.description,
                                  size: 14,
                                  color: Colors.orange.withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(d,
                                      style: const TextStyle(fontSize: 12))),
                            ],
                          ),
                        )),
                    const SizedBox(height: 8),
                    // 重点提示
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Text(focus,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ),
                    const SizedBox(height: 10),
                    // 上传/批阅 操作行
                    _buildReportActions(
                      reportType: '${w['week']}报告',
                      color: color,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportSubHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(title,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  /// 报告操作行：学生上传/重新上传 + 教师批阅 + AI批阅入口
  ///
  /// 在过程报告卡片和最终报告卡片底部统一展示。匹配规则：
  /// 通过 [reportType]（如"第一周报告"/"答辩报告"）查找已提交记录。
  Widget _buildReportActions({
    required String reportType,
    required Color color,
  }) {
    final matched = _submissions
        .where((s) => (s['title'] as String?)?.contains(reportType) == true)
        .toList();
    final hasSubmitted = matched.isNotEmpty;
    final score = hasSubmitted ? matched.first['score'] as int? : null;
    final status =
        hasSubmitted ? (matched.first['status'] as String? ?? '已提交') : '未提交';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasSubmitted
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 14,
                color: hasSubmitted ? color : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasSubmitted
                      ? '$status${score != null ? "  ·  $score 分" : ""}'
                      : '尚未上传',
                  style: TextStyle(
                    fontSize: 11,
                    color: hasSubmitted ? Colors.grey[700] : Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasSubmitted &&
                  (matched.first['file_path'] as String? ?? '').isNotEmpty)
                IconButton(
                  icon: Icon(Icons.visibility, size: 16, color: color),
                  tooltip: '预览',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openPdfPreview(
                    matched.first['file_path'] as String,
                    reportType,
                    userId: matched.first['user_id'] as String?,
                    fileName: matched.first['content_json'] as String?,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_isStudent)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickAndUploadPdf(reportType),
                    icon: Icon(
                      hasSubmitted ? Icons.refresh : Icons.upload_file,
                      size: 14,
                    ),
                    label: Text(
                      hasSubmitted ? '重新上传' : '上传报告',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasSubmitted
                        ? () => _showReportGradeDialog(matched.first)
                        : null,
                    icon: const Icon(Icons.grading, size: 14),
                    label: const Text('教师批阅', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasSubmitted
                        ? () => _showReportGradeDialog(matched.first)
                        : null,
                    icon: const Icon(Icons.auto_awesome, size: 14),
                    label: const Text('AI 批阅', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab2: 4份最终报告要求
  // ══════════════════════════════════════════════════════════
  Widget _buildAssessmentReports() {
    final reports = [
      {
        'num': '1',
        'title': '答辩报告',
        'subtitle': '演示答辩 · 占大作业25%',
        'color': Colors.red,
        'icon': Icons.record_voice_over,
        'requirements': [
          '回答三个必答题（核心技术20分+架构设计30分+创新点40分）',
          '回答一个随机题（10分）',
          '提交视频演示（≤10分钟）',
          '答辩现场实时录音 + 录音转文本',
          '提交个人源码压缩包和部署说明',
        ],
        'keyContent': [
          '项目概述与分工说明',
          '核心技术实现方案（必答题1）',
          '系统架构设计图与说明（必答题2）',
          '创新点与技术亮点展示（必答题3）',
          '现场演示与录音记录',
        ],
        'tips': '答辩前3天提交初稿，答辩当天提交最终版。录音和转录文本必须一致。',
      },
      {
        'num': '2',
        'title': '个人报告',
        'subtitle': '个人贡献总结 · 占大作业25%',
        'color': Colors.blue,
        'icon': Icons.person,
        'requirements': [
          '系统核心类图（UML Class Diagram）— 必须',
          '核心功能顺序图（UML Sequence Diagram）— 必须',
          '系统架构图（Architecture Diagram）— 必须',
          '个人代码贡献统计（提交次数/代码行数）',
          '技术难点与解决方案记录',
        ],
        'keyContent': [
          '个人基本信息与技术栈',
          '个人负责模块的详细实现',
          '3种必须的UML/架构图（图表不规范=0分）',
          '个人代码贡献量化数据',
          '学习收获与技术成长总结',
        ],
        'tips': '图表必须规范（PlantUML/EA/StarUML），必须与个人负责模块相关，图表不规范则此报告0分。',
      },
      {
        'num': '3',
        'title': '小组报告',
        'subtitle': '团队协作总结 · 占大作业25%',
        'color': Colors.green,
        'icon': Icons.groups,
        'requirements': [
          '每位成员独立整合完成（禁止复制他人报告）',
          '个人贡献度与个人报告保持一致',
          '团队数据由全体成员共同确认',
          '包含团队协作流程与沟通记录',
          '禁止修改他人个人贡献数据',
        ],
        'keyContent': [
          '小组基本信息与成员分工表',
          '团队协作流程（Git工作流/代码审查/会议）',
          '成员贡献度矩阵（自评+互评）',
          '团队问题与解决方案',
          '团队协作反思与改进',
        ],
        'tips': '每人独立提交，内容相同但需独立整合。个人贡献部分必须与个人报告数据一致。',
      },
      {
        'num': '4',
        'title': '项目报告',
        'subtitle': '技术文档 · 占大作业25%',
        'color': Colors.orange,
        'icon': Icons.folder_special,
        'requirements': [
          '每位成员独立整合完成',
          '技术栈描述与实际开发一致',
          '包含完整的技术架构文档',
          '测试报告与性能数据',
          '部署文档与用户手册',
        ],
        'keyContent': [
          '项目基本信息（名称/类型/周期/版本）',
          '技术栈详解（≥5种技术栈对比分析）',
          '系统架构设计（分层/模块/数据流）',
          '核心功能实现详解',
          '测试报告（功能测试+性能测试+安全审计）',
          '项目总结与未来展望',
        ],
        'tips': '技术文档必须真实准确，与实际代码一致。推荐包含部署步骤截图。',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 警告卡片
        Card(
          color: Colors.red.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 18, color: Colors.red),
                    const SizedBox(width: 6),
                    Text('重要提示',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700])),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• 四份报告必须全部提交，缺一不可\n'
                  '• 缺少任何一份报告，大作业成绩为0分（占总成绩50%）\n'
                  '• 迟交任何一份报告，按缺交处理\n'
                  '• 建议顺序：答辩 → 个人 → 小组 → 项目',
                  style: TextStyle(
                      fontSize: 12, color: Colors.red[600], height: 1.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 四份报告
        ...reports.map((r) => _buildReportRequirementCard(r)),
      ],
    );
  }

  Widget _buildReportRequirementCard(Map<String, dynamic> r) {
    final color = r['color'] as Color;
    final requirements = r['requirements'] as List<String>;
    final keyContent = r['keyContent'] as List<String>;
    final tips = r['tips'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 4),
            ),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Center(
                child: Text(r['num'] as String,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color)),
              ),
            ),
            title: Text(r['title'] as String,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            subtitle: Text(r['subtitle'] as String,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            children: [
              // 基本要求
              _reportSubHeader('基本要求', Icons.rule, color),
              const SizedBox(height: 6),
              ...requirements.map((req) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_box_outlined,
                            size: 14, color: color.withValues(alpha: 0.6)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(req,
                                style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  )),
              const SizedBox(height: 10),
              // 核心内容
              _reportSubHeader('核心内容（每项都要写）', Icons.edit_note, Colors.indigo),
              const SizedBox(height: 6),
              ...keyContent.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text('${e.key + 1}',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo[700])),
                          ),
                        ),
                        Expanded(
                            child: Text(e.value,
                                style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
              // 提示
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb, size: 14, color: Colors.amber[700]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tips,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber[800],
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 上传/批阅 操作行
              _buildReportActions(
                reportType: r['title'] as String,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  Tab3: 审核打印面板（步骤一审核 → 步骤二打印 PDF）
  // ══════════════════════════════════════════════════════════
  Widget _buildSubmissionPanel() {
    return AuditPrintPanel(
      isStudent: _isStudent,
      currentUserId: _currentUserId,
      authService: widget.authService,
      submissions: _submissions,
      onPickAndUploadPdf: _pickAndUploadPdf,
      onShowGradeDialog: _showReportGradeDialog,
      onOpenPdfPreview: _openPdfPreview,
      onDeleteSubmission: (id) async {
        await _dao.deleteSubmittedReport(id);
        await _loadSubmissions();
      },
      onReload: _loadSubmissions,
    );
  }

  Future<void> _pickAndUploadPdf(String reportType) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final userId = _currentUserId ?? '';
      final userName = widget.authService.currentUser?.realName ?? userId;

      // 学生提交时验证文件名规范
      if (_isStudent) {
        final error = _validateReportFileName(file.name, reportType);
        if (error != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // AI 检查：报告内容是否匹配小组技术栈和特色功能
      String? pdfTextForGrading;
      if (_isStudent && file.path != null) {
        final techInfo = await _dao.getStudentGroupTechInfo(userId);
        if (techInfo != null &&
            (techInfo['techStack']?.isNotEmpty == true ||
                techInfo['features']?.isNotEmpty == true)) {
          final pdfText = await PdfTextService.extractFromFile(
            file.path!,
            maxChars: 2000,
          );
          pdfTextForGrading = pdfText;
          if (pdfText != null && pdfText.isNotEmpty) {
            // ignore: use_build_context_synchronously
            final reason = await GradingAgent().checkReportTechStackAlignment(
              reportContent: pdfText,
              groupTechStack: techInfo['techStack'] ?? '',
              groupFeatures: techInfo['features'] ?? '',
            );
            if (reason != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '提交失败：报告内容未体现小组技术栈和特色功能 — $reason',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red[700],
                  duration: const Duration(seconds: 6),
                ),
              );
              return;
            }
          }
        }
      }

      final reportId = await _dao.submitReport(
        userId: userId,
        studentName: userName,
        reportType: reportType,
        fileName: file.name,
        filePath: file.path ?? '',
      );

      // 没拿到 PDF 文本前先尝试解析（学生路径走过 alignment 检查会有，
      // 教师代上传 / 验证跳过的情况下这里需要补抽一次）
      if (pdfTextForGrading == null && file.path != null) {
        try {
          pdfTextForGrading =
              await PdfTextService.extractFromFile(file.path!, maxChars: 6000);
        } catch (e, st) {
          swallowDebug(e, tag: 'AssessmentReportTab.pdfText', stack: st);
        }
      }

      if (!mounted) return;

      // 学生路径：AI 初评达到评价分数线后才算提交成功；教师代上传则不拦截。
      if (_isStudent && reportId > 0) {
        if (pdfTextForGrading == null || pdfTextForGrading.isEmpty) {
          await _dao.deleteSubmittedReport(reportId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('提交失败：无法读取 PDF 正文，不能进行 AI 审核'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final passScore = await SettingsService.getEvaluationPassScore();
        final draft = await AutoGradingService.instance.gradeAssessmentReport(
          reportId: reportId,
          studentId: userId,
          studentName: userName,
          reportType: reportType,
          content: pdfTextForGrading,
          returnDraft: true,
          notifyStudent: false,
        );

        if (draft == null || !draft.isUsable || draft.score < passScore) {
          await _dao.deleteSubmittedReport(reportId);
          await GradingResultDao()
              .deletePendingForTarget('assessment', reportId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(draft == null
                    ? '提交失败：AI 审核未完成，请稍后重试'
                    : '提交失败：AI 初评 ${draft.score} 分，未达到 $passScore 分达标线，请修改后重新提交'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // 通知教师
      NotificationService().notifyAssessmentSubmission(
        studentId: userId,
        studentName: userName,
        reportType: reportType,
      );

      await _loadSubmissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$reportType 已提交: ${file.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    }
  }

  void _openPdfPreview(String filePath, String title,
      {String? userId, String? fileName}) {
    final file = filePath.isNotEmpty ? File(filePath) : null;
    if (file != null && file.existsSync()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InAppPdfViewerPage(filePath: filePath, title: title),
        ),
      );
      return;
    }

    final shownName = fileName?.isNotEmpty == true
        ? fileName!
        : (filePath.isNotEmpty
            ? filePath.split(Platform.pathSeparator).last
            : '附件');
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          '该 PDF 在学生本机提交，尚未同步到当前设备。\n文件名：$shownName',
          style: const TextStyle(height: 1.4),
        ),
        action: (userId == null || userId.isEmpty)
            ? null
            : SnackBarAction(
                label: '立即同步',
                onPressed: () async {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(SnackBar(
                    content: Text('正在从云端拉取 $userId 的提交…'),
                    duration: const Duration(seconds: 2),
                  ));
                  try {
                    final r = await SyncService().downloadOwnData(userId);
                    if (!mounted) return;
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(SnackBar(
                      content: Text(r.success
                          ? '同步完成：${r.message}'
                          : '同步失败：${r.message}'),
                      backgroundColor: r.success ? null : Colors.red,
                    ));
                    if (r.success) await _loadSubmissions();
                  } catch (e) {
                    if (!mounted) return;
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(SnackBar(
                      content: Text('同步出错：$e'),
                      backgroundColor: Colors.red,
                    ));
                  }
                },
              ),
      ),
    );
  }

  /// 教师批改考核报告对话框（含 AI 批阅）
  void _showReportGradeDialog(Map<String, dynamic> submission) {
    final reportId = submission['id'] as int?;
    final title = submission['title'] as String? ?? '最终报告';
    final content = submission['content_json'] as String? ?? '';
    final filePath = submission['file_path'] as String? ?? '';
    final userId = submission['user_id'] as String? ?? '';
    final status = submission['status'] as String? ?? '已提交';
    final existingScore = submission['score'] as int?;
    final existingFeedback = submission['feedback'] as String?;

    double scoreValue = (existingScore ?? 80).toDouble();
    final feedbackCtrl = TextEditingController(text: existingFeedback ?? '');
    bool isGrading = false;
    bool isAiGrading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final scoreColor = scoreValue >= 90
              ? Colors.green
              : scoreValue >= 80
                  ? Colors.blue
                  : scoreValue >= 60
                      ? Colors.orange
                      : Colors.red;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.grading, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('批改 - $title',
                      style: const TextStyle(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 学生信息
                    Text('学生：$userId',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('提交文件：$content',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                    // PDF 预览按钮
                    if (filePath.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _openPdfPreview(
                          filePath,
                          title,
                          userId: userId,
                          fileName: content,
                        ),
                        icon: const Icon(Icons.visibility, size: 16),
                        label: const Text('预览 PDF',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                    Text('状态：$status',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 16),
                    // 评分
                    Row(
                      children: [
                        const Text('评分',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('${scoreValue.round()} / 100',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: scoreColor)),
                      ],
                    ),
                    Slider(
                      value: scoreValue,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '${scoreValue.round()}',
                      onChanged: (v) => setDialogState(() => scoreValue = v),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [60, 70, 80, 85, 90, 95, 100].map((v) {
                        final isSelected = scoreValue.round() == v;
                        return ActionChip(
                          label: Text('$v',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : null)),
                          backgroundColor: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          onPressed: () =>
                              setDialogState(() => scoreValue = v.toDouble()),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: feedbackCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: '教师反馈',
                        hintText: '请输入批改意见和建议...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // AI 批阅按钮
              OutlinedButton.icon(
                onPressed: isAiGrading
                    ? null
                    : () async {
                        setDialogState(() => isAiGrading = true);
                        try {
                          final agent = GradingAgent();
                          final result = await agent.gradeReport(
                            reportType: title,
                            studentName: userId,
                            content: content.isNotEmpty
                                ? content
                                : '（学生提交了PDF文件：$title）',
                          );
                          final parsed = _tryParseGradingJson(result);
                          if (parsed != null) {
                            setDialogState(() {
                              scoreValue =
                                  (parsed['total_score'] as num?)?.toDouble() ??
                                      (parsed['score'] as num?)?.toDouble() ??
                                      scoreValue;
                              if (scoreValue > 100) scoreValue = 100;
                              feedbackCtrl.text =
                                  parsed['feedback'] as String? ?? '';
                            });
                          } else {
                            setDialogState(() {
                              feedbackCtrl.text = result;
                            });
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('AI批阅失败: $e')),
                            );
                          }
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => isAiGrading = false);
                          }
                        }
                      },
                icon: isAiGrading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(isAiGrading ? 'AI批阅中...' : 'AI批阅'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton.icon(
                onPressed: isGrading
                    ? null
                    : () async {
                        setDialogState(() => isGrading = true);
                        try {
                          if (reportId != null) {
                            final db = await DatabaseHelper.instance.database;
                            await db.update(
                              'student_reports',
                              {
                                'score': scoreValue.round(),
                                'feedback': feedbackCtrl.text.trim().isNotEmpty
                                    ? feedbackCtrl.text.trim()
                                    : null,
                                'status': '已批改',
                              },
                              where: 'id = ?',
                              whereArgs: [reportId],
                            );
                          }
                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('批改成功！'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadSubmissions();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('批改失败: $e')),
                            );
                          }
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => isGrading = false);
                          }
                        }
                      },
                icon: isGrading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(isGrading ? '提交中...' : '提交批改'),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, dynamic>? _tryParseGradingJson(String text) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch == null) return null;
      final jsonStr = jsonMatch.group(0)!;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map.containsKey('total_score') ||
          map.containsKey('score') ||
          map.containsKey('feedback')) {
        return map;
      }
      return null;
    } catch (e, st) {
      swallowDebug(e, tag: 'AssessmentReportTab.parseGradingJson', stack: st);
      return null;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 成绩统计 Tab
// ══════════════════════════════════════════════════════════════════════════════
