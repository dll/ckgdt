import 'package:flutter/material.dart';

import '../../../core/design/noir_tokens.dart';
import '../../widgets/noir_page_shell.dart';

class CourseObjectivesPage extends StatelessWidget {
  const CourseObjectivesPage({super.key});

  static const _intro =
      '通过本课程的学习，掌握移动应用开发的多元技术体系（原生/混合/小程序/多端），理解不同开发模式的适用场景，熟悉主流跨平台开发框架及 AI 编程工具的使用，具备跨平台应用系统分析、设计和开发能力，能够运用 RESTful API 实现移动端与后端的数据交互，培养学生科学思维、创新意识和良好的职业道德，为从事移动开发工作及毕业设计奠定基础。';

  static const _objectives = [
    _CourseObjective(
      index: 1,
      weight: '15%',
      objective:
          '掌握移动应用开发技术体系（原生/混合/跨平台）及主流平台特性，理解技术选型逻辑，熟悉跨平台开发框架和 AI 编程工具的基本使用。',
      graduationRequirement:
          '1.4 能够将数学、自然科学、工程基础和专业知识综合应用于解决计算机领域复杂工程问题，能够判别计算机系统的复杂性',
      chapters: '第1章、第2章、第6章',
      labs: '实验1、实验2',
      assessment: '项目架构设计：主流框架项目结构设计与技术选型分析',
      color: Color(0xFFE53935),
    ),
    _CourseObjective(
      index: 2,
      weight: '25%',
      objective:
          '运用跨平台开发框架及小程序技术，结合 AI 编程工具与后端 API 交互，设计实现跨平台应用，具备需求建模与创新应用能力。',
      graduationRequirement: '3.2 能够针对特定工程需求设计计算机应用系统，并在设计环节中体现创新意识',
      chapters: '第3章、第4章、第6章',
      labs: '实验3、实验4',
      assessment: '数据交互实现：RESTful API 对接、数据存储方案设计与实现',
      color: Color(0xFF1E88E5),
    ),
    _CourseObjective(
      index: 3,
      weight: '30%',
      objective: '调研对比多端开发方案，分析不同技术栈在跨设备适配场景中的优劣，具备技术方案评估与选型能力。',
      graduationRequirement:
          '4.2 针对计算机领域复杂工程问题，能够收集、分析与解释已存在的相关产品、模型、系统、方案、开源资料库等资料，并通过信息综合得到合理有效的结论',
      chapters: '第5章、第6章',
      labs: '实验5',
      assessment: '技术方案评估：多端适配方案对比分析与选型论证',
      color: Color(0xFF43A047),
    ),
    _CourseObjective(
      index: 4,
      weight: '30%',
      objective: '遵循软件工程规范，使用现代开发工具（含 AI 编程工具、Git 版本控制）完成应用测试与优化，具备工程实践能力。',
      graduationRequirement: '5.1 能够运用现代信息技术和工具获取计算机专业重要资料与信息',
      chapters: '第6章',
      labs: '实验6',
      assessment: '工程实践能力：AI 工具深度应用、代码重构、性能优化与 Git 协作规范',
      color: Color(0xFFFF9800),
    ),
  ];

  static const _achievementRows = [
    ['课程目标1', '0.15', '支撑毕业要求 1.4', '15（20%）', '15（30%）', '15（50%）'],
    ['课程目标2', '0.25', '支撑毕业要求 3.2', '25（20%）', '25（30%）', '25（50%）'],
    ['课程目标3', '0.30', '支撑毕业要求 4.2', '30（20%）', '30（30%）', '30（50%）'],
    ['课程目标4', '0.30', '支撑毕业要求 5.1', '30（20%）', '30（30%）', '30（50%）'],
    ['合计', '1', '', '100（20%）', '100（30%）', '100（50%）'],
  ];

  @override
  Widget build(BuildContext context) {
    return NoirPageShell(
      title: '课程目标',
      eyebrow: 'COURSE OBJECTIVES',
      showBackdrop: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        children: [
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('二、课程目标及其对毕业要求的支撑',
                    style: NoirTokens.title(color: NoirTokens.paper)),
                const SizedBox(height: 12),
                Text(
                  _intro,
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.82),
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildObjectiveTable(context),
          const SizedBox(height: 12),
          _buildAchievementTable(context),
          const SizedBox(height: 12),
          ..._objectives.map(_buildObjectiveCard),
        ],
      ),
    );
  }

  Widget _buildObjectiveTable(BuildContext context) {
    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('课程目标与毕业要求支撑关系',
              style: NoirTokens.title(color: NoirTokens.paper)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(
                dataTableTheme: _darkTableTheme(),
              ),
              child: DataTable(
                columnSpacing: 22,
                horizontalMargin: 8,
                columns: const [
                  DataColumn(label: Text('序号')),
                  DataColumn(label: Text('课程目标')),
                  DataColumn(label: Text('支撑的毕业要求')),
                ],
                rows: [
                  for (final objective in _objectives)
                    DataRow(cells: [
                      DataCell(Text('${objective.index}')),
                      DataCell(SizedBox(
                        width: 420,
                        child: Text(objective.objective),
                      )),
                      DataCell(SizedBox(
                        width: 460,
                        child: Text(objective.graduationRequirement),
                      )),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementTable(BuildContext context) {
    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('课程目标达成考核与评价方式及成绩评定对照表',
              style: NoirTokens.title(color: NoirTokens.paper)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Theme(
              data: Theme.of(context).copyWith(
                dataTableTheme: _darkTableTheme(),
              ),
              child: DataTable(
                columnSpacing: 24,
                horizontalMargin: 8,
                columns: const [
                  DataColumn(label: Text('课程目标')),
                  DataColumn(label: Text('权重')),
                  DataColumn(label: Text('毕业要求')),
                  DataColumn(label: Text('平时')),
                  DataColumn(label: Text('实验')),
                  DataColumn(label: Text('考核')),
                ],
                rows: [
                  for (final row in _achievementRows)
                    DataRow(cells: [
                      for (final cell in row)
                        DataCell(Text(
                          cell,
                          style: row.first == '合计'
                              ? const TextStyle(fontWeight: FontWeight.w800)
                              : null,
                        )),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjectiveCard(_CourseObjective objective) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NoirTokens.paper.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 90,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: objective.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '目标${objective.index}',
                  style: TextStyle(
                    color: objective.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '权重${objective.weight}',
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.62),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  objective.objective,
                  style: const TextStyle(
                    color: NoirTokens.paper,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '支撑毕业要求 ${objective.graduationRequirement} · 考核：${objective.assessment}',
                  style: TextStyle(
                    color: NoirTokens.paper.withValues(alpha: 0.64),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '章节：${objective.chapters}    实验：${objective.labs}',
                  style: TextStyle(
                    color: objective.color.withValues(alpha: 0.86),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataTableThemeData _darkTableTheme() {
    return DataTableThemeData(
      headingTextStyle: TextStyle(
        color: NoirTokens.paper.withValues(alpha: 0.86),
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
      dataTextStyle: TextStyle(
        color: NoirTokens.paper.withValues(alpha: 0.82),
        fontSize: 13,
        height: 1.4,
      ),
      headingRowColor: WidgetStatePropertyAll(
        NoirTokens.paper.withValues(alpha: 0.06),
      ),
      dividerThickness: 0.4,
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NoirTokens.paper.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NoirTokens.paper.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _CourseObjective {
  final int index;
  final String weight;
  final String objective;
  final String graduationRequirement;
  final String chapters;
  final String labs;
  final String assessment;
  final Color color;

  const _CourseObjective({
    required this.index,
    required this.weight,
    required this.objective,
    required this.graduationRequirement,
    required this.chapters,
    required this.labs,
    required this.assessment,
    required this.color,
  });
}
