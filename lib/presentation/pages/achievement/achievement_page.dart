import 'package:flutter/material.dart';
import '../../../core/design/noir_tokens.dart';
import '../../../data/local/achievement_dao.dart';
import '../../../services/auth_service.dart';
import '../../widgets/agent_entry_button.dart';
import 'tabs/overview_tab.dart';
import 'tabs/scores_tab.dart';
import 'tabs/report_tab.dart';
import 'tabs/analysis_tab.dart';

/// 课程达成度计算系统 — 8 Tab 壳页面
///
/// 各 Tab 实现已拆分至 tabs/ 子目录：
/// - overview_tab.dart: 达成度概览 + 批次详情
/// - scores_tab.dart: 成绩管理 + 平时/实验/考核达成
/// - report_tab.dart: 报告生成 + 预览对话框
/// - analysis_tab.dart: 计算过程 + 持续改进
class AchievementPage extends StatefulWidget {
  const AchievementPage({super.key});

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _authService = AuthService();
  final _achievementDao = AchievementDao();

  static const _tabSpecs = <(IconData, String, String)>[
    (Icons.analytics_outlined, '达成度概览', '01'),
    (Icons.edit_note, '成绩管理', '02'),
    (Icons.school_outlined, '平时达成', '03'),
    (Icons.science_outlined, '实验达成', '04'),
    (Icons.assignment_outlined, '考核达成', '05'),
    (Icons.calculate_outlined, '计算过程', '06'),
    (Icons.summarize_outlined, '报告生成', '07'),
    (Icons.build_outlined, '持续改进', '08'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabSpecs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 编辑级章节条：黑底 paper 字 + 琥珀编号 + 1px 琥珀底线 ──
        Container(
          decoration: BoxDecoration(
            color: NoirTokens.ink,
            border: Border(
              bottom: BorderSide(
                color: NoirTokens.accent.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: NoirTokens.paper,
                  unselectedLabelColor: NoirTokens.paper.withValues(alpha: 0.45),
                  indicatorColor: NoirTokens.accent,
                  indicatorWeight: 2,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.6,
                  ),
                  tabs: [
                    for (final (icon, label, serial) in _tabSpecs)
                      Tab(
                        height: 56,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(serial,
                                style: NoirTokens.serial(
                                    color: NoirTokens.accent)),
                            const SizedBox(width: 8),
                            Icon(icon, size: 16),
                            const SizedBox(width: 6),
                            Text(label),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Theme(
                  // 顶栏入口在黑底上要可见，反转图标颜色
                  data: Theme.of(context).copyWith(
                    iconTheme: const IconThemeData(color: NoirTokens.paper),
                  ),
                  child: const AgentEntryButton(agentId: 'achievement'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AchievementOverviewTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              ScoreManagementTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              PingshiAchievementTab(
                achievementDao: _achievementDao,
              ),
              ExperimentAchievementTab(
                achievementDao: _achievementDao,
              ),
              ExamAchievementTab(
                achievementDao: _achievementDao,
              ),
              CalculationProcessTab(
                achievementDao: _achievementDao,
              ),
              ReportTab(
                authService: _authService,
                achievementDao: _achievementDao,
              ),
              ContinuousImprovementTab(
                achievementDao: _achievementDao,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
